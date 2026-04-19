"""
Rural Health AI — Skin Disease Classifier (Kaggle training script)
==================================================================
Paste this whole file into a single Kaggle notebook cell and run.

SETUP ON KAGGLE:
  1. New Notebook → Settings →
       • Accelerator: GPU P100 (or T4 x2 — both fine)
       • Persistence: Files only
       • Internet: On (for ImageNet weights)
  2. Add Input → search for and add:
       ★ shubhamgoel27/dermnet   ← DEFAULT

       Optional alternatives (the script auto-detects whichever is attached):
         • ismailpromus/skin-diseases-image-dataset
         • pacificrm/skindiseasedataset
         • haroonalam16/20-skin-diseases-image-dataset
  3. Paste this file in a cell. Run All.

DERMNET-SPECIFIC FIX — 8-GROUP CLINICAL MERGING:
  Vanilla 23-class DermNet at 128×128 tops out at ~27% val_acc on
  MobileNetV2. The classes are too fine-grained and visually overlapping
  (Eczema vs Atopic Dermatitis vs Contact Dermatitis are hard even for
  trained dermatologists).

  This script auto-detects DermNet and collapses the 23 classes into 8
  clinically-meaningful supergroups (Fungal / Bacterial / Viral /
  Parasitic / Inflammatory / Allergic / Neoplastic / Autoimmune-Other).
  This is also more useful for an ASHA worker in the field: the triage
  decision is 'is this infectious vs inflammatory vs refer-to-specialist',
  not the exact ICD-10 code.

  Toggle CLINICAL_MERGE_DERMNET=False below to run on raw 23 classes.

UPGRADE LEVERS (post-hackathon retrain targeting the 70% ship gate):
  1. BACKBONE = "efficientnetb0"
     Swaps MobileNetV2 for EfficientNetB0 @ 224×224 (pre-trained native
     res). More expressive, ~1.5x training time, ~1 MB larger TFLite.
     Expected val_acc lift on DermNet-8: +0.10 to +0.20.

  2. DROP_SUPERGROUPS = {"Bacterial Infection"}
     The Apr 2026 run had Bacterial at 0.09 recall — actively
     dangerous to keep in production. Dropping it before training
     frees the model to put its capacity into the remaining 7
     supergroups, which typically lifts their individual recalls by
     5–10% because the "noise class" stops absorbing gradient.

  3. If BACKBONE is changed, the Dart preprocessing in
     assessment_screen.dart must resize images to the new IMG_SIZE.
     At 224×224 the preprocessing block there becomes:
         img.copyResize(decoded, width: 224, height: 224)
     Update ml_service.dart's comment too.

INPUT-RANGE CONVENTION:
  This script feeds [0, 1] float pixels into the network (no
  preprocess_input). That matches model_training/train_images.py's
  convention, which in turn matches the Dart caller's
  _preprocessImage at android_app/lib/screens/assessment_screen.dart.
  Previous builds used mobilenet_v2.preprocess_input which expected
  [0, 255] — a mismatch that required a stopgap scale-by-255 in
  ml_service.dart. Dropping that stopgap is pending a retrain with
  this script.

OUTPUT (downloadable from the notebook's "Output" panel after run):
  • skin_disease_model.tflite              (~2.5 MB, float16-quantized)
  • skin_disease_model_classes.json        (class labels in JSON array)
  • skin_disease_model_metadata.json       (accuracy, architecture, gate status)

ACCEPTANCE GATE (hard rule from CLAUDE.md):
  Validation accuracy must be ≥ 70%. If this run fails the gate, the
  artifacts still save so you can inspect, but DO NOT bundle into the app.
  The previous skin model shipped at 32% and was permanently removed.
"""

import os, json
from pathlib import Path
import numpy as np
import tensorflow as tf
from tensorflow.keras import layers, models, applications, callbacks
from sklearn.metrics import classification_report

# ═══════════════════════════════════════════════════════════════════════
# CONFIG
# ═══════════════════════════════════════════════════════════════════════

# ─── Backbone ─────────────────────────────────────────────────────
# "mobilenetv2" is the default and matches the other siblings. Switch
# to "efficientnetb0" for the post-hackathon upgrade attempt — more
# expressive backbone at the cost of ~1.5x training time and ~1 MB
# larger TFLite output.
BACKBONE = "mobilenetv2"      # one of: "mobilenetv2", "efficientnetb0"

# MobileNetV2 was pre-trained on 128×128 and the eye/lung/malaria
# siblings use 128. EfficientNetB0 is pre-trained on 224×224 and its
# feature extractor is much weaker at 128 — bump IMG_SIZE when using
# it. Dart callers must resize to match.
IMG_SIZE = 224 if BACKBONE == "efficientnetb0" else 128

BATCH_SIZE = 32
EPOCHS_HEAD = 12              # stage 1: frozen backbone, train head only
EPOCHS_FINE = 15              # stage 2: unfreeze top N layers
UNFREEZE_LAYERS = 30          # how many top layers to fine-tune in stage 2
FINE_TUNE_LR = 3e-5           # stage 2 learning rate
SEED = 42
VAL_SPLIT = 0.2
MIN_VAL_ACC = 0.70            # CLAUDE.md hard gate
MIN_PER_CLASS_RECALL = 0.50   # no confident-wrong class allowed
USE_CLASS_WEIGHTS = True      # essential for imbalanced datasets

# ─── Drop broken classes (post-hoc class reduction) ───────────────
# The Apr 2026 DermNet run had Bacterial Infection at 0.09 recall —
# essentially non-functional, and worse than useless in the field
# because it contaminates the other supergroups with false negatives.
# Add class names here to drop them entirely before training; the
# remaining supergroups get the full training budget.
DROP_SUPERGROUPS = set()      # e.g. {"Bacterial Infection"}

# Safety guard: if stage 2 fine-tuning makes val_acc *worse* than stage 1
# ended at, revert to stage 1 weights. (Prior DermNet runs saw stage 2
# regress by 2–3% because heavy aug + class weights + low LR destabilized
# the backbone. The guard catches that automatically.)
STAGE2_REVERT_ON_REGRESSION = True

# ─── DermNet 23 → 8 clinical supergroup merging ───────────────────────
# Collapses DermNet's fine-grained 23 classes into 8 clinically-meaningful
# groups that match what an ASHA worker actually needs for triage.
# Only applied if we detect DermNet's class-name signature.
CLINICAL_MERGE_DERMNET = True

DERMNET_TO_CLINICAL = {
    # Fungal — common in rural India, treatable OTC
    "Nail Fungus and other Nail Disease":                                       "Fungal Infection",
    "Tinea Ringworm Candidiasis and other Fungal Infections":                   "Fungal Infection",

    # Bacterial — needs antibiotics
    "Cellulitis Impetigo and other Bacterial Infections":                       "Bacterial Infection",

    # Viral
    "Herpes HPV and other STDs Photos":                                         "Viral Infection",
    "Warts Molluscum and other Viral Infections":                               "Viral Infection",

    # Parasitic / contact — scabies is very common in rural India
    "Scabies Lyme Disease and other Infestations and Bites":                    "Parasitic and Contact",
    "Poison Ivy Photos and other Contact Dermatitis":                           "Parasitic and Contact",

    # Chronic inflammatory / eczema family
    "Acne and Rosacea Photos":                                                  "Inflammatory and Eczema",
    "Atopic Dermatitis Photos":                                                 "Inflammatory and Eczema",
    "Eczema Photos":                                                            "Inflammatory and Eczema",
    "Psoriasis pictures Lichen Planus and related diseases":                    "Inflammatory and Eczema",

    # Allergic / acute drug reaction — triage-urgent
    "Urticaria Hives":                                                          "Allergic and Drug Reaction",
    "Exanthems and Drug Eruptions":                                             "Allergic and Drug Reaction",

    # Tumors — refer for biopsy
    "Actinic Keratosis Basal Cell Carcinoma and other Malignant Lesions":       "Neoplastic or Tumor",
    "Melanoma Skin Cancer Nevi and Moles":                                      "Neoplastic or Tumor",
    "Seborrheic Keratoses and other Benign Tumors":                             "Neoplastic or Tumor",
    "Vascular Tumors":                                                          "Neoplastic or Tumor",

    # Autoimmune / systemic / structural — needs specialist referral
    "Bullous Disease Photos":                                                   "Autoimmune or Systemic",
    "Lupus and other Connective Tissue diseases":                               "Autoimmune or Systemic",
    "Vasculitis Photos":                                                        "Autoimmune or Systemic",
    "Systemic Disease":                                                         "Autoimmune or Systemic",
    "Hair Loss Photos Alopecia and other Hair Diseases":                        "Autoimmune or Systemic",
    "Light Diseases and Disorders of Pigmentation":                             "Autoimmune or Systemic",
}

# The 8 supergroups in the order we want them emitted (determines softmax
# output index → label mapping).
CLINICAL_GROUP_ORDER = [
    "Bacterial Infection",
    "Fungal Infection",
    "Viral Infection",
    "Parasitic and Contact",
    "Inflammatory and Eczema",
    "Allergic and Drug Reaction",
    "Neoplastic or Tumor",
    "Autoimmune or Systemic",
]

OUTPUT_DIR = Path("/kaggle/working")

# ─── DATASET AUTO-DETECT ──────────────────────────────────────────────
# We walk /kaggle/input/* looking for any folder that has the
# "class_name/*.jpg" structure (≥2 class folders, each with images).
# That way this script works with *any* skin dataset attached without
# hardcoded paths.
INPUT_ROOT = Path("/kaggle/input")
IMG_EXTS = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}

def _has_images(p: Path, min_imgs: int = 3) -> bool:
    try:
        return sum(1 for f in p.iterdir()
                   if f.is_file() and f.suffix.lower() in IMG_EXTS) >= min_imgs
    except Exception:
        return False

def _looks_like_classification_root(p: Path, min_classes: int = 2) -> bool:
    """A dir that contains ≥N subdirectories which themselves contain images."""
    try:
        subdirs = [c for c in p.iterdir() if c.is_dir()]
        class_like = [c for c in subdirs if _has_images(c)]
        return len(class_like) >= min_classes
    except Exception:
        return False

def _find_dataset_root(root: Path, max_depth: int = 4) -> Path | None:
    """BFS for a directory matching the classification-root shape."""
    if not root.exists():
        return None
    frontier = [(root, 0)]
    while frontier:
        cur, depth = frontier.pop(0)
        if _looks_like_classification_root(cur):
            return cur
        if depth < max_depth:
            try:
                frontier.extend((c, depth + 1) for c in cur.iterdir() if c.is_dir())
            except Exception:
                pass
    return None

def _find_all_dataset_roots(root: Path, max_depth: int = 5) -> list[Path]:
    """Find ALL classification roots inside a tree (so we can pick best one)."""
    out: list[Path] = []
    if not root.exists():
        return out
    frontier = [(root, 0)]
    while frontier:
        cur, depth = frontier.pop(0)
        if _looks_like_classification_root(cur):
            out.append(cur)
            # Don't recurse INTO a classification root — its children are
            # class folders, not nested datasets.
            continue
        if depth < max_depth:
            try:
                frontier.extend((c, depth + 1) for c in cur.iterdir() if c.is_dir())
            except Exception:
                pass
    return out

def _score_root(p: Path) -> tuple[int, int]:
    """Higher score wins. We prefer (a) bigger total image count and
    (b) folders named 'train' over 'test'/'val'."""
    try:
        total_imgs = sum(
            1
            for cls in p.iterdir() if cls.is_dir()
            for f in cls.iterdir() if f.is_file() and f.suffix.lower() in IMG_EXTS
        )
    except Exception:
        total_imgs = 0
    name_bonus = 0
    name = p.name.lower()
    if name in ("train", "training"):
        name_bonus = 1_000_000  # massively prefer train splits
    elif name in ("test", "testing", "val", "validation", "valid"):
        name_bonus = -500_000   # de-prefer eval splits
    return (name_bonus + total_imgs, total_imgs)

DATA_DIR = None
DATA_DIR_SECONDARY = None  # if we find a 'test' split too, we'll merge it in
if INPUT_ROOT.exists():
    all_roots: list[Path] = []
    for ds in sorted(INPUT_ROOT.iterdir()):
        if ds.is_dir():
            all_roots.extend(_find_all_dataset_roots(ds))
    if all_roots:
        all_roots.sort(key=_score_root, reverse=True)
        DATA_DIR = str(all_roots[0])
        # If the dataset has a sibling 'test' split with the same parent,
        # remember it — we'll combine both for max training data.
        primary = all_roots[0]
        for cand in all_roots[1:]:
            if cand.parent == primary.parent and cand.name.lower() in (
                "test", "testing", "val", "validation", "valid"
            ):
                DATA_DIR_SECONDARY = str(cand)
                break

if DATA_DIR is None:
    print("❌ No dataset with class-folder structure found under /kaggle/input/.")
    print()
    print("   Fix: right sidebar → '+ Add Input' → search one of:")
    print("         • shubhamgoel27/dermnet   (recommended, 23 classes)")
    print("         • ismailpromus/skin-diseases-image-dataset   (8 classes)")
    print("         • nodoubttome/skin-cancer9-classesisic")
    print("   Click 'Add', wait for it to download, then re-run this cell.")
    print()
    print("   What's currently under /kaggle/input/:")
    if INPUT_ROOT.exists():
        children = list(INPUT_ROOT.iterdir())
        if not children:
            print("     (empty — no datasets attached yet)")
        else:
            for c in children:
                print(f"     {c}")
                if c.is_dir():
                    for sub in list(c.iterdir())[:5]:
                        print(f"       └─ {sub.name}{'/' if sub.is_dir() else ''}")
    else:
        print("     /kaggle/input/ does not exist — are you on Kaggle?")
    raise SystemExit(1)

print(f"✅ Using dataset: {DATA_DIR}")
if DATA_DIR_SECONDARY:
    print(f"   + merging in eval split: {DATA_DIR_SECONDARY}")
_num_classes = len([p for p in Path(DATA_DIR).iterdir() if p.is_dir()])
print(f"   Detected {_num_classes} class folders")

# Confirm GPU is on
gpus = tf.config.list_physical_devices("GPU")
print(f"   GPUs visible to TF: {len(gpus)}  {[g.name for g in gpus]}")

# ═══════════════════════════════════════════════════════════════════════
# DATA
# ═══════════════════════════════════════════════════════════════════════

tf.random.set_seed(SEED)
np.random.seed(SEED)

# If we have both train + test/val splits with the same class layout,
# merge them and re-split. This gives the model more data to learn from
# and matches what the original Kaggle notebook author likely did.
def _load_split(directory: str, subset: str):
    return tf.keras.utils.image_dataset_from_directory(
        directory,
        validation_split=VAL_SPLIT,
        subset=subset,
        seed=SEED,
        image_size=(IMG_SIZE, IMG_SIZE),
        batch_size=BATCH_SIZE,
        shuffle=True,
    )

train_ds_raw = _load_split(DATA_DIR, "training")
val_ds_raw = _load_split(DATA_DIR, "validation")
class_names = train_ds_raw.class_names

if DATA_DIR_SECONDARY:
    # Verify class layout matches before merging
    sec_train = _load_split(DATA_DIR_SECONDARY, "training")
    sec_val = _load_split(DATA_DIR_SECONDARY, "validation")
    if sec_train.class_names == class_names:
        print(f"   merging {DATA_DIR_SECONDARY} (same class layout) into the training pool")
        train_ds_raw = train_ds_raw.concatenate(sec_train).concatenate(sec_val)
    else:
        print(f"   ⚠️  {DATA_DIR_SECONDARY} has different classes — skipping merge")

# ── DermNet clinical merging (23 → 8 supergroups) ───────────────────
# We detect DermNet by checking how many of its class names appear in the
# dataset we just loaded. If ≥18 match (out of 23), we treat this as DermNet
# and collapse to the 8 ASHA-triage-relevant groups. This is the fix for
# the "24% val_acc, can't even fit" problem — the model has plenty of
# capacity for 8 coarser classes but not for 23 overlapping fine ones.
dermnet_match_count = sum(1 for c in class_names if c in DERMNET_TO_CLINICAL)
is_dermnet = dermnet_match_count >= 18
clinical_merge_active = CLINICAL_MERGE_DERMNET and is_dermnet

if clinical_merge_active:
    print(f"\n🔬 DermNet detected ({dermnet_match_count}/23 classes match).")
    print(f"   Collapsing to {len(CLINICAL_GROUP_ORDER)} clinical supergroups:")

    # Build label-remap array: old_label_idx → new_label_idx
    group_to_idx = {g: i for i, g in enumerate(CLINICAL_GROUP_ORDER)}
    remap_arr = []
    for old_label in class_names:
        supergroup = DERMNET_TO_CLINICAL.get(old_label, "Autoimmune or Systemic")
        remap_arr.append(group_to_idx[supergroup])
    remap_tensor = tf.constant(remap_arr, dtype=tf.int64)

    def _remap_labels(x, y):
        return x, tf.gather(remap_tensor, tf.cast(y, tf.int64))

    train_ds_raw = train_ds_raw.map(_remap_labels, num_parallel_calls=tf.data.AUTOTUNE)
    val_ds_raw = val_ds_raw.map(_remap_labels, num_parallel_calls=tf.data.AUTOTUNE)

    # Replace class_names with the supergroup list (this is what TFLite will emit)
    ORIGINAL_CLASS_NAMES = class_names
    class_names = CLINICAL_GROUP_ORDER[:]
    for i, g in enumerate(class_names):
        members = [c for c in ORIGINAL_CLASS_NAMES if DERMNET_TO_CLINICAL.get(c) == g]
        print(f"   [{i}] {g}  ← {len(members)} orig classes")
else:
    ORIGINAL_CLASS_NAMES = class_names[:]
    print(f"\nℹ️  Clinical merging not applied "
          f"(detected {dermnet_match_count}/23 DermNet classes; "
          f"CLINICAL_MERGE_DERMNET={CLINICAL_MERGE_DERMNET}).")

# ─── Drop-broken-supergroup filter ────────────────────────────────────
# Apply AFTER clinical merging so we can drop e.g. "Bacterial Infection"
# by name. Filters the datasets to exclude images whose remapped label
# hits a dropped supergroup, and rewrites class_names + remap_tensor so
# the softmax head only emits kept classes.
if DROP_SUPERGROUPS:
    keep_mask = [c not in DROP_SUPERGROUPS for c in class_names]
    kept_classes = [c for c, k in zip(class_names, keep_mask) if k]
    dropped = [c for c in class_names if not keep_mask[class_names.index(c)]]
    if dropped:
        print(f"\n🗑  Dropping supergroups: {dropped}")
    # Build one dense lookup table: old_label_idx → new_label_idx, or -1 for
    # dropped classes. This avoids the earlier argmax-after-boolean-mask
    # trick, which silently mis-mapped labels if the masked batch happened
    # to exclude a dropped class (argmax over an all-zero row returned 0,
    # the first class, instead of "no match").
    drop_sentinel = -1
    remap_arr_drop = [drop_sentinel] * len(class_names)
    for old_idx, cls in enumerate(class_names):
        if cls in kept_classes:
            remap_arr_drop[old_idx] = kept_classes.index(cls)
    remap_table_drop = tf.constant(remap_arr_drop, dtype=tf.int64)

    def _filter_and_relabel(x, y):
        new_y = tf.gather(remap_table_drop, tf.cast(y, tf.int64))
        keep = tf.greater_equal(new_y, 0)
        return tf.boolean_mask(x, keep), tf.boolean_mask(new_y, keep)

    # .unbatch().batch(...) is intentional: the filter produces
    # variable-size batches per call, so we re-batch to a consistent size
    # for the downstream model.fit loop. Order within the shuffle buffer is
    # preserved, so this does not introduce non-determinism beyond what
    # image_dataset_from_directory's initial shuffle already introduces.
    train_ds_raw = train_ds_raw.unbatch().batch(BATCH_SIZE).map(
        _filter_and_relabel, num_parallel_calls=tf.data.AUTOTUNE
    )
    val_ds_raw = val_ds_raw.unbatch().batch(BATCH_SIZE).map(
        _filter_and_relabel, num_parallel_calls=tf.data.AUTOTUNE
    )
    class_names = kept_classes
    print(f"   {len(class_names)} classes remain after drop: {class_names}")

num_classes = len(class_names)
print(f"\n📊 Classes ({num_classes}):")
for i, c in enumerate(class_names):
    print(f"   [{i:2d}] {c}")

# ── Class weights for imbalanced datasets ─────────────────────────────
class_weights = None
if USE_CLASS_WEIGHTS:
    print("\n⚖️  Computing class weights from disk (handles imbalance)...")
    # Count per ORIGINAL class, then sum into supergroup bucket if merging
    orig_counts = np.zeros(len(ORIGINAL_CLASS_NAMES), dtype=np.int64)
    for src in [DATA_DIR] + ([DATA_DIR_SECONDARY] if DATA_DIR_SECONDARY else []):
        for i, cls in enumerate(ORIGINAL_CLASS_NAMES):
            cls_dir = Path(src) / cls
            if cls_dir.exists():
                orig_counts[i] += sum(
                    1 for f in cls_dir.iterdir()
                    if f.is_file() and f.suffix.lower() in IMG_EXTS
                )

    if clinical_merge_active:
        counts = np.zeros(num_classes, dtype=np.int64)
        for i, orig_cls in enumerate(ORIGINAL_CLASS_NAMES):
            counts[remap_arr[i]] += orig_counts[i]
    else:
        counts = orig_counts

    total = counts.sum()
    # sklearn's "balanced" formula: total / (n_classes * count)
    class_weights = {
        i: float(total / (num_classes * max(c, 1)))
        for i, c in enumerate(counts)
    }
    print(f"   total imgs={total}, min/max class size={counts.min()}/{counts.max()}")
    print(f"   weight range: {min(class_weights.values()):.2f} to {max(class_weights.values()):.2f}")

# Data augmentation — somewhat aggressive because skin photos vary wildly
# in lighting/angle/distance from rural-clinic conditions.
aug = tf.keras.Sequential([
    layers.RandomFlip("horizontal_and_vertical"),
    layers.RandomRotation(0.15),
    layers.RandomZoom(0.15),
    layers.RandomContrast(0.15),
    layers.RandomBrightness(0.15),
])

AUTOTUNE = tf.data.AUTOTUNE
train_ds = (
    train_ds_raw
    .map(lambda x, y: (aug(x, training=True), y), num_parallel_calls=AUTOTUNE)
    .cache()
    .prefetch(AUTOTUNE)
)
val_ds = val_ds_raw.cache().prefetch(AUTOTUNE)

# ═══════════════════════════════════════════════════════════════════════
# MODEL — transfer learning, backbone chosen by BACKBONE constant
# ═══════════════════════════════════════════════════════════════════════
#
# Input-range convention: match the existing eye/lung/malaria pipeline
# which feeds [0, 1] normalized floats (train_images.py line 169 does
# `np.array(img, dtype=np.float32) / 255.0`; assessment_screen.dart
# _preprocessImage does `pixel.r / 255.0`). We do NOT apply the
# backbone's preprocess_input because that expects [0, 255] raw and
# would mismatch the Dart caller.
#
# Imagenet weights were trained on mean-subtracted pixels, so feeding
# raw [0, 1] is slightly off-distribution. Fine-tuning absorbs the
# shift, and this is what the sibling models already do — swapping
# conventions just for skin would break the Dart code or require a
# stopgap multiplication there, which is what the previous build had.

if BACKBONE == "mobilenetv2":
    base = applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
elif BACKBONE == "efficientnetb0":
    base = applications.EfficientNetB0(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights="imagenet",
    )
else:
    raise ValueError(f"Unknown BACKBONE: {BACKBONE!r}")
base.trainable = False

inp = layers.Input(shape=(IMG_SIZE, IMG_SIZE, 3))
# NO preprocess_input — the Dart caller feeds [0, 1] normalized floats.
x = base(inp, training=False)
x = layers.GlobalAveragePooling2D()(x)
# EfficientNetB0 benefits from a bit more dropout than MobileNetV2 on
# small fine-grained datasets — the backbone is more expressive and
# overfits faster.
dropout_rate = 0.40 if BACKBONE == "efficientnetb0" else 0.25
x = layers.Dropout(dropout_rate)(x)
out = layers.Dense(num_classes, activation="softmax", dtype="float32")(x)

model = models.Model(inp, out)
print(f"   Backbone: {BACKBONE}  |  input: {IMG_SIZE}×{IMG_SIZE}×3 in [0, 1]")
print(f"   Dropout: {dropout_rate}  |  softmax head: {num_classes} classes")
model.compile(
    optimizer=tf.keras.optimizers.Adam(1e-3),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"],
)
model.summary(line_length=100)

cb = [
    callbacks.EarlyStopping(
        monitor="val_accuracy", patience=3,
        restore_best_weights=True, verbose=1,
    ),
    callbacks.ReduceLROnPlateau(
        monitor="val_loss", factor=0.5, patience=2, min_lr=1e-6, verbose=1,
    ),
]

# ─── STAGE 1: HEAD ONLY ────────────────────────────────────────────────
print("\n🎯 STAGE 1 — training classifier head (backbone frozen)")
h1 = model.fit(
    train_ds, validation_data=val_ds, epochs=EPOCHS_HEAD,
    callbacks=cb, class_weight=class_weights,
)
stage1_best_val_acc = max(h1.history.get("val_accuracy", [0.0]))
stage1_weights = model.get_weights()  # snapshot in case stage 2 regresses
print(f"   Stage 1 best val_acc: {stage1_best_val_acc:.4f}")

# ─── STAGE 2: UNFREEZE TOP N LAYERS ────────────────────────────────────
print(f"\n🎯 STAGE 2 — fine-tuning top {UNFREEZE_LAYERS} layers of MobileNetV2")
base.trainable = True
for layer in base.layers[:-UNFREEZE_LAYERS]:
    layer.trainable = False

model.compile(
    optimizer=tf.keras.optimizers.Adam(FINE_TUNE_LR),
    loss="sparse_categorical_crossentropy",
    metrics=["accuracy"],
)
h2 = model.fit(
    train_ds, validation_data=val_ds, epochs=EPOCHS_FINE,
    callbacks=cb, class_weight=class_weights,
)
stage2_best_val_acc = max(h2.history.get("val_accuracy", [0.0]))
print(f"   Stage 2 best val_acc: {stage2_best_val_acc:.4f}")

# Safety guard — if fine-tuning regressed, revert
if STAGE2_REVERT_ON_REGRESSION and stage2_best_val_acc < stage1_best_val_acc:
    print(
        f"\n⚠️  Stage 2 regressed ({stage2_best_val_acc:.4f} < {stage1_best_val_acc:.4f}). "
        "Reverting to Stage 1 weights. Consider lowering FINE_TUNE_LR or UNFREEZE_LAYERS."
    )
    model.set_weights(stage1_weights)
    final_best_val_acc = stage1_best_val_acc
    stage_used = "stage1"
else:
    final_best_val_acc = max(stage1_best_val_acc, stage2_best_val_acc)
    stage_used = "stage2"
print(f"   Final model comes from: {stage_used}  (val_acc={final_best_val_acc:.4f})")

# ═══════════════════════════════════════════════════════════════════════
# EVAL + GATE
# ═══════════════════════════════════════════════════════════════════════

print("\n📏 EVALUATION")
val_loss, val_acc = model.evaluate(val_ds, verbose=1)
print(f"   Validation accuracy: {val_acc:.4f}")
print(f"   Validation loss:     {val_loss:.4f}")

# Per-class report — we care about recall, not just overall accuracy
y_true, y_pred = [], []
for xb, yb in val_ds:
    p = model.predict(xb, verbose=0).argmax(axis=1)
    y_true.extend(yb.numpy().tolist())
    y_pred.extend(p.tolist())

print("\n📋 Per-class report:")
print(classification_report(
    y_true, y_pred, target_names=class_names, digits=3, zero_division=0,
))

from sklearn.metrics import recall_score
per_class_recall = recall_score(y_true, y_pred, average=None, zero_division=0)
weak_classes = [
    (class_names[i], float(r))
    for i, r in enumerate(per_class_recall)
    if r < MIN_PER_CLASS_RECALL
]

gate_overall = val_acc >= MIN_VAL_ACC
gate_per_class = len(weak_classes) == 0

if not gate_overall:
    print(f"\n⛔ OVERALL ACCURACY GATE FAILED: {val_acc:.3f} < {MIN_VAL_ACC}")
    print("   Previous skin model shipped at 0.32 and was permanently removed.")
    print("   Do NOT bundle this model. Options:")
    print("     • Try a different dataset (see script header)")
    print("     • Merge visually-similar classes")
    print("     • Collect more data for under-represented classes")
if not gate_per_class:
    print(f"\n⚠️  PER-CLASS GATE FAILED. Classes with recall < {MIN_PER_CLASS_RECALL}:")
    for name, r in weak_classes:
        print(f"     • {name}: recall={r:.3f}")
    print("   A class with low recall will show up as a *confident wrong answer* in the field.")
    print("   That's worse than no model. Consider dropping these classes.")

if gate_overall and gate_per_class:
    print(f"\n✅ ALL GATES PASSED — val_acc={val_acc:.3f}, min_class_recall={per_class_recall.min():.3f}")

# ═══════════════════════════════════════════════════════════════════════
# TFLITE EXPORT (float16 quantized → ~2.5 MB)
# ═══════════════════════════════════════════════════════════════════════

print("\n💾 TFLITE EXPORT")
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.target_spec.supported_types = [tf.float16]
tflite_bytes = converter.convert()

tflite_path = OUTPUT_DIR / "skin_disease_model.tflite"
tflite_path.write_bytes(tflite_bytes)
size_mb = tflite_path.stat().st_size / 1024 / 1024
print(f"   {tflite_path}  ({size_mb:.2f} MB)")

classes_path = OUTPUT_DIR / "skin_disease_model_classes.json"
classes_path.write_text(json.dumps(class_names, ensure_ascii=False, indent=2))
print(f"   {classes_path}")

meta_path = OUTPUT_DIR / "skin_disease_model_metadata.json"
meta_path.write_text(json.dumps({
    "model": f"{BACKBONE} (imagenet transfer, top-{UNFREEZE_LAYERS} fine-tuned)",
    "backbone": BACKBONE,
    "img_size": IMG_SIZE,
    "input_shape": [IMG_SIZE, IMG_SIZE, 3],
    "input_normalization": "[0, 1] raw — img / 255.0 — matches train_images.py",
    "dropout_rate": dropout_rate,
    "dropped_supergroups": sorted(DROP_SUPERGROUPS),
    "num_classes": num_classes,
    "classes": class_names,
    "val_accuracy": float(val_acc),
    "val_loss": float(val_loss),
    "per_class_recall": {class_names[i]: float(per_class_recall[i]) for i in range(num_classes)},
    "weak_classes": [{"name": n, "recall": r} for n, r in weak_classes],
    "training": {
        "stage1_epochs": EPOCHS_HEAD,
        "stage2_epochs": EPOCHS_FINE,
        "stage1_best_val_acc": float(stage1_best_val_acc),
        "stage2_best_val_acc": float(stage2_best_val_acc),
        "stage_used_in_final_model": stage_used,
        "unfreeze_layers": UNFREEZE_LAYERS,
        "fine_tune_lr": FINE_TUNE_LR,
        "batch_size": BATCH_SIZE,
        "val_split": VAL_SPLIT,
        "seed": SEED,
        "dataset_dir": DATA_DIR,
        "dataset_dir_secondary": DATA_DIR_SECONDARY,
    },
    "clinical_merging": {
        "active": bool(clinical_merge_active),
        "detected_as_dermnet": bool(is_dermnet),
        "dermnet_match_count": int(dermnet_match_count),
        "original_class_count": len(ORIGINAL_CLASS_NAMES),
        "supergroup_count": int(num_classes),
        "original_classes": list(ORIGINAL_CLASS_NAMES),
        "supergroup_membership": (
            {g: [c for c in ORIGINAL_CLASS_NAMES if DERMNET_TO_CLINICAL.get(c) == g]
             for g in CLINICAL_GROUP_ORDER}
            if clinical_merge_active else None
        ),
    },
    "gates": {
        "min_val_accuracy": MIN_VAL_ACC,
        "min_per_class_recall": MIN_PER_CLASS_RECALL,
        "overall_passed": bool(gate_overall),
        "per_class_passed": bool(gate_per_class),
    },
    "ship_approved": bool(gate_overall and gate_per_class),
}, indent=2))
print(f"   {meta_path}")

print("\n🏁 DONE.")
if gate_overall and gate_per_class:
    print("   Next: download the three files above from the Output panel,")
    print("         copy them into android_app/assets/models/,")
    print("         then wire the Dart edits per KAGGLE_SKIN_TRAINING.md.")
else:
    print("   Gates FAILED — do not ship. See warnings above.")
