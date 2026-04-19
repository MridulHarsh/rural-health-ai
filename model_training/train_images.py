#!/usr/bin/env python3
"""
Rural Health AI — Image Model Training (M2 Optimized)
=====================================================
Trains MobileNetV2-based classifiers for skin, eye, and lung diseases.
Optimized for Apple M2: Metal GPU, mixed precision, data prefetching.

Usage:
    python train_images.py --data_dir /path/to/kaggle_datasets
    python train_images.py --data_dir /path/to/kaggle_datasets --m2_optimize
"""

import os, sys, json, argparse, warnings
import numpy as np
from pathlib import Path
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

warnings.filterwarnings('ignore')
os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'

import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers
from PIL import Image

OUTPUT_DIR = Path("output")
OUTPUT_DIR.mkdir(exist_ok=True)

IMG_SIZE = 128
RANDOM_STATE = 42

# ═══════════════════════════════════════════════════════════════
# M2 HARDWARE OPTIMIZATION
# ═══════════════════════════════════════════════════════════════

def setup_m2(optimize=False):
    """Configure TensorFlow for maximum M2 utilization."""
    config = {
        'batch_size': 32,
        'epochs': 15,
        'max_per_class': 1000,
        'use_mixed_precision': False,
        'prefetch': True,
    }

    if optimize:
        # ── Metal GPU ──
        gpus = tf.config.list_physical_devices('GPU')
        if gpus:
            for gpu in gpus:
                tf.config.experimental.set_memory_growth(gpu, True)
            print(f"  🔥 Metal GPU: ACTIVE ({len(gpus)} device)")
        else:
            print("  ⚠️  Metal GPU not found. Install: pip install tensorflow-metal")

        # ── Mixed precision for GPU speedup ──
        # Uses float16 for compute, float32 for variables → ~2x faster on GPU
        try:
            tf.keras.mixed_precision.set_global_policy('mixed_float16')
            config['use_mixed_precision'] = True
            print("  🔥 Mixed precision: float16 ACTIVE")
        except Exception:
            print("  ⚠️  Mixed precision not available, using float32")

        # ── Larger batch size to saturate GPU ──
        config['batch_size'] = 64
        config['max_per_class'] = 1500  # Load more images
        config['epochs'] = 20  # More epochs since training is faster

        # ── Parallel image loading threads ──
        os.environ['OMP_NUM_THREADS'] = str(os.cpu_count() or 8)
        print(f"  🔥 Batch size: {config['batch_size']}")
        print(f"  🔥 Max images/class: {config['max_per_class']}")
        print(f"  🔥 Epochs: {config['epochs']}")
        print(f"  🔥 CPU threads: {os.cpu_count()}")
    else:
        print("  ℹ️  Standard mode (add --m2_optimize for GPU acceleration)")

    return config


# ═══════════════════════════════════════════════════════════════
# DATASET DISCOVERY
# ═══════════════════════════════════════════════════════════════

SKIN_DATASETS = [
    'pacificrm_skindiseasedataset',
    'subirbiswas19_skin-disease-dataset',
    'ismailpromus_skin-diseases-image-dataset',
    'haroonalam16_20-skin-diseases-dataset',
    'riyaelizashaju_skin-disease-classification-image-dataset',
    'trainingdatapro_skin-defects-acne-redness-and-bags-under-the-eyes',
]

EYE_DATASETS = [
    'kondwani_eye-disease-dataset',
    'andrewmvd_ocular-disease-recognition-odir5k',
    'andrewmvd_retinal-disease-classification',
    'dakshnagra_dry-eye-disease',
]

LUNG_DATASETS = [
    'fatemehmehrparvar_lung-disease',
]

IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp', '.bmp', '.tiff', '.tif'}


def find_class_folders(root_path):
    """Recursively find class folders containing images."""
    root = Path(root_path)
    classes = {}

    def _scan(path, depth=0):
        if depth > 5:
            return False
        subdirs = [d for d in path.iterdir() if d.is_dir() and not d.name.startswith('.')]
        if not subdirs:
            images = [f for f in path.iterdir()
                      if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS]
            if len(images) >= 5:
                classes[path.name] = [str(f) for f in images]
                return True
            return False
        found_any = False
        for sd in subdirs:
            if _scan(sd, depth + 1):
                found_any = True
        if not found_any:
            images = [f for f in path.iterdir()
                      if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS]
            if len(images) >= 5:
                classes[path.name] = [str(f) for f in images]
                return True
        return found_any

    _scan(root)
    return classes


def collect_images_for_category(data_dir, dataset_names, label):
    """Collect class folders across multiple datasets."""
    all_classes = {}
    for ds_name in dataset_names:
        ds_path = data_dir / ds_name
        if not ds_path.exists():
            continue
        classes = find_class_folders(ds_path)
        if classes:
            for cls_name, paths in classes.items():
                normalized = cls_name.strip().title().replace('_', ' ')
                all_classes[normalized] = all_classes.get(normalized, []) + paths
            print(f"    ✅ {ds_name}: {sum(len(v) for v in classes.values())} images in {len(classes)} classes")
        else:
            print(f"    ⚠️  {ds_name}: no class folders found")
    return all_classes


# ═══════════════════════════════════════════════════════════════
# PARALLEL IMAGE LOADING (uses all CPU cores)
# ═══════════════════════════════════════════════════════════════

def load_single_image(path):
    """Load and preprocess one image.

    Uses a context manager so the underlying file handle is closed even when
    the conversion or resize fails. Without this, an unbounded number of
    per-class loads (max_per_class can be 1500+ on M2-optimized runs) could
    exhaust file descriptors on the default macOS 256-FD soft limit.
    """
    try:
        with Image.open(path) as raw:
            img = raw.convert('RGB').resize(
                (IMG_SIZE, IMG_SIZE), Image.LANCZOS,
            )
            return np.array(img, dtype=np.float32) / 255.0
    except Exception:
        return None


def prepare_dataset(class_dict, max_per_class=1000):
    """Load images into arrays using parallel threads."""
    valid_classes = {k: v for k, v in class_dict.items() if len(v) >= 10}
    if not valid_classes:
        return None, None, None

    class_names = sorted(valid_classes.keys())
    print(f"\n    Classes ({len(class_names)}):")

    all_paths = []
    all_labels = []
    np.random.seed(RANDOM_STATE)

    for cls_idx, cls_name in enumerate(class_names):
        paths = valid_classes[cls_name]
        capped = min(len(paths), max_per_class)
        if len(paths) > max_per_class:
            paths = list(np.random.choice(paths, max_per_class, replace=False))
        print(f"      {cls_name}: {len(valid_classes[cls_name])} images (using {capped})")
        all_paths.extend(paths)
        all_labels.extend([cls_idx] * len(paths))

    # ── Parallel loading with all CPU cores ──
    num_workers = min(os.cpu_count() or 4, 8)
    print(f"\n    Loading images with {num_workers} threads...")

    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        results = list(executor.map(load_single_image, all_paths))

    # Filter out failed loads
    X_list = []
    y_list = []
    for img, label in zip(results, all_labels):
        if img is not None:
            X_list.append(img)
            y_list.append(label)

    if not X_list:
        return None, None, None

    X = np.array(X_list)
    y = np.array(y_list)
    print(f"    ✅ Loaded: {len(X)} images total")
    return X, y, class_names


# ═══════════════════════════════════════════════════════════════
# MODEL BUILDING + TRAINING
# ═══════════════════════════════════════════════════════════════

def build_model(num_classes, use_mixed_precision=False):
    """MobileNetV2 transfer learning, optimized for M2 GPU."""
    base = keras.applications.MobileNetV2(
        input_shape=(IMG_SIZE, IMG_SIZE, 3),
        include_top=False,
        weights='imagenet'
    )
    base.trainable = False

    model = keras.Sequential([
        base,
        layers.GlobalAveragePooling2D(),
        layers.Dropout(0.3),
        layers.Dense(128, activation='relu'),
        layers.Dropout(0.2),
        # For mixed precision: final Dense must output float32 for stable softmax
        layers.Dense(num_classes, activation='softmax', dtype='float32'),
    ])

    model.compile(
        optimizer=keras.optimizers.Adam(learning_rate=0.001),
        loss='sparse_categorical_crossentropy',
        metrics=['accuracy']
    )
    return model


def make_tf_dataset(X, y, batch_size, shuffle=True, augment=False):
    """Create a tf.data pipeline with prefetch for GPU overlap."""
    dataset = tf.data.Dataset.from_tensor_slices((X, y))

    if shuffle:
        dataset = dataset.shuffle(buffer_size=len(X), seed=RANDOM_STATE)

    if augment:
        # On-GPU augmentation
        augmentation = keras.Sequential([
            layers.RandomFlip("horizontal"),
            layers.RandomRotation(0.1),
            layers.RandomZoom(0.1),
            layers.RandomBrightness(0.1),
        ])

        def apply_augment(image, label):
            image = augmentation(tf.expand_dims(image, 0))[0]
            return image, label

        dataset = dataset.map(apply_augment,
                              num_parallel_calls=tf.data.AUTOTUNE)

    dataset = dataset.batch(batch_size)
    dataset = dataset.prefetch(tf.data.AUTOTUNE)  # Overlap CPU prep with GPU training
    return dataset


def train_and_export(X, y, class_names, model_name, category_label, config):
    """Train model with M2 optimizations, evaluate, export to TFLite."""
    if X is None or len(X) < 20:
        print(f"\n  ⏭️  Skipping {category_label}: not enough images")
        return None

    num_classes = len(class_names)
    batch_size = config['batch_size']
    epochs = config['epochs']

    print(f"\n{'─'*60}")
    print(f"  Training {category_label} classifier")
    print(f"  {len(X)} images, {num_classes} classes, {IMG_SIZE}x{IMG_SIZE}px")
    print(f"  Batch size: {batch_size}, Epochs: {epochs}")
    print(f"{'─'*60}")

    # Split
    from sklearn.model_selection import train_test_split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=y
    )
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")

    # Build model
    model = build_model(num_classes, config['use_mixed_precision'])

    callbacks = [
        keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=3),
    ]

    # Train directly with numpy — GPU handles one batch at a time
    history = model.fit(
        X_train, y_train,
        validation_data=(X_test, y_test),
        epochs=epochs,
        batch_size=batch_size,
        callbacks=callbacks,
        shuffle=True,
        verbose=1
    )

    # Evaluate
    loss, acc = model.evaluate(X_test, y_test, verbose=0)
    print(f"\n  ✅ {category_label} accuracy: {acc:.2%}")

    # Export TFLite (quantized for small size)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite_model = converter.convert()

    tflite_path = OUTPUT_DIR / f"{model_name}.tflite"
    with open(tflite_path, 'wb') as f:
        f.write(tflite_model)
    size_mb = os.path.getsize(tflite_path) / (1024 * 1024)
    print(f"  ✅ Saved {tflite_path.name} ({size_mb:.1f} MB)")

    # Save class names
    classes_path = OUTPUT_DIR / f"{model_name}_classes.json"
    with open(classes_path, 'w') as f:
        json.dump(class_names, f, indent=2)
    print(f"  ✅ Saved {classes_path.name} ({len(class_names)} classes)")

    # Metadata
    meta = {
        "model_name": model_name,
        "category": category_label,
        "num_classes": num_classes,
        "accuracy": round(float(acc), 4),
        "image_size": IMG_SIZE,
        "total_images": len(X),
        "tflite_size_mb": round(size_mb, 2),
        "classes": class_names,
        "m2_optimized": config.get('use_mixed_precision', False),
    }
    with open(OUTPUT_DIR / f"{model_name}_metadata.json", 'w') as f:
        json.dump(meta, f, indent=2)

    return acc


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data_dir', type=str, default=None)
    parser.add_argument('--m2_optimize', action='store_true',
                        help='Enable M2 GPU acceleration with mixed precision')
    args = parser.parse_args()

    if args.data_dir:
        data_dir = Path(args.data_dir)
    elif Path('kaggle_datasets').exists():
        data_dir = Path('kaggle_datasets')
    elif Path('../kaggle_datasets').exists():
        data_dir = Path('../kaggle_datasets')
    else:
        print("❌ Cannot find kaggle_datasets/")
        sys.exit(1)

    print("=" * 70)
    print("  Rural Health AI — Image Model Training")
    print("  MobileNetV2 Transfer Learning (M2 Optimized)")
    print("=" * 70)
    print()

    config = setup_m2(optimize=args.m2_optimize)

    results = {}

    # ── SKIN DISEASES ──
    print("\n\n🩹 Collecting SKIN disease images...")
    skin_classes = collect_images_for_category(data_dir, SKIN_DATASETS, "Skin")
    if skin_classes:
        X, y, names = prepare_dataset(skin_classes, config['max_per_class'])
        acc = train_and_export(X, y, names, "skin_disease_model", "Skin Disease", config)
        if acc: results['skin'] = acc

    # ── EYE DISEASES ──
    print("\n\n👁️  Collecting EYE disease images...")
    eye_classes = collect_images_for_category(data_dir, EYE_DATASETS, "Eye")
    if eye_classes:
        X, y, names = prepare_dataset(eye_classes, config['max_per_class'])
        acc = train_and_export(X, y, names, "eye_disease_model", "Eye Disease", config)
        if acc: results['eye'] = acc

    # ── LUNG DISEASES ──
    print("\n\n🫁 Collecting LUNG disease images...")
    lung_classes = collect_images_for_category(data_dir, LUNG_DATASETS, "Lung")
    if lung_classes:
        X, y, names = prepare_dataset(lung_classes, config['max_per_class'])
        acc = train_and_export(X, y, names, "lung_disease_model", "Lung Disease", config)
        if acc: results['lung'] = acc

    # Summary
    print(f"\n{'='*70}")
    print(f"  Image training complete!")
    for cat, acc in results.items():
        print(f"    {cat.title()}: {acc:.2%}")
    if not results:
        print("    ⚠️  No image models trained (datasets may not have class folders)")
    print(f"{'='*70}")


if __name__ == "__main__":
    main()
