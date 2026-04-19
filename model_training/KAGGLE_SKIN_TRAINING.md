# Training the skin-disease classifier on Kaggle

End-to-end walkthrough for producing a `skin_disease_model.tflite` that passes our accuracy gate and bundling it into the Android app.

> **Prerequisite context:** the previous skin model shipped at 32% accuracy and was permanently removed ([CLAUDE.md:192](../CLAUDE.md)). This workflow includes a **hard gate of val_acc ≥ 70% and per-class recall ≥ 50%**. If your run fails the gate, do not bundle the artifacts — the app is better off without a skin model than with a confidently-wrong one.

---

## 1 · Create the Kaggle notebook

1. Go to [kaggle.com/code](https://www.kaggle.com/code) → **+ New Notebook**.
2. In the right-hand sidebar:
   - **Accelerator** → **GPU T4 x2** (fastest free option) or **GPU P100**
   - **Persistence** → *Files only* (so `/kaggle/working/` survives between cells)
   - **Internet** → **On** (required to download ImageNet weights for MobileNetV2)

## 2 · Attach a dataset

Click **+ Add Input** and attach **one** of these (listed in order of preference):

| Dataset | Classes | Size | Notes |
|---|---|---|---|
| [`shubhamgoel27/dermnet`](https://www.kaggle.com/datasets/shubhamgoel27/dermnet) | 23 | ~1.4 GB | Best coverage, the default in our script |
| [`ismailpromus/skin-diseases-image-dataset`](https://www.kaggle.com/datasets/ismailpromus/skin-diseases-image-dataset) | 8 | ~900 MB | Cleaner labels, easier gate |
| [`nodoubttome/skin-cancer9-classesisic`](https://www.kaggle.com/datasets/nodoubttome/skin-cancer9-classesisic) | 9 | ~500 MB | ISIC dermatoscopy — only useful if ASHA has a dermatoscope (unlikely) |

The training script auto-detects which of these is attached — you don't have to edit any paths.

## 3 · Paste and run

1. Open [`kaggle_skin_model.py`](./kaggle_skin_model.py) from this repo.
2. Copy the entire contents.
3. Paste into **one cell** in your Kaggle notebook.
4. Click **Run All**.

Expected runtime on T4 x2: **~25–40 min** for DermNet, **~15 min** for the smaller datasets.

## 4 · Read the gate output

At the end of the run you'll see one of:

```
✅ ALL GATES PASSED — val_acc=0.742, min_class_recall=0.553
```

or

```
⛔ OVERALL ACCURACY GATE FAILED: 0.584 < 0.7
⚠️  PER-CLASS GATE FAILED. Classes with recall < 0.5:
     • Melanocytic Nevi: recall=0.312
     • Vascular Lesions: recall=0.410
```

**If the gate failed:**
- Try the 8-class dataset (simpler problem, easier gate).
- Or look at `weak_classes` in `skin_disease_model_metadata.json` and consider dropping those classes (re-train with a filtered dataset).
- Do **not** proceed to step 5.

## 5 · Download the artifacts

After a successful run, the **Output** panel on the right shows `/kaggle/working/`. Download:

- `skin_disease_model.tflite` (~2.5 MB)
- `skin_disease_model_classes.json` (a few KB)
- `skin_disease_model_metadata.json` (for the record)

## 6 · Drop into the Android project

From the repo root:

```bash
# Replace the old metadata file (it was left behind when the model was removed)
cp ~/Downloads/skin_disease_model.tflite            android_app/assets/models/
cp ~/Downloads/skin_disease_model_classes.json      android_app/assets/models/
cp ~/Downloads/skin_disease_model_metadata.json     android_app/assets/models/
```

## 7 · Re-activate the Dart wiring

Three edits to [`android_app/lib/services/ml_service.dart`](../android_app/lib/services/ml_service.dart). Line numbers reference the current file.

### Edit A — fields (around line 20)

Replace:
```dart
  // Skin model permanently removed (32% accuracy, duplicate class names
  // across source datasets). Do not re-add without a reliable replacement.
  Interpreter? _eyeModel;
```

With:
```dart
  // Skin model re-added YYYY-MM-DD, val_acc=0.XX. Gate passed per
  // skin_disease_model_metadata.json. See KAGGLE_SKIN_TRAINING.md.
  Interpreter? _skinModel;
  Interpreter? _eyeModel;
```

And add `_skinClasses`:
```dart
  List<String>? _skinClasses;
  List<String>? _eyeClasses;
```

### Edit B — loader (in `_loadImageModels`, ~line 177)

Replace the `// Skin model permanently removed...` comment with:
```dart
    try {
      _skinModel = await Interpreter.fromAsset('assets/models/skin_disease_model.tflite');
      final sj = await rootBundle.loadString('assets/models/skin_disease_model_classes.json');
      _skinClasses = List<String>.from(jsonDecode(sj));
      debugPrint('[MLService] Skin model loaded: ${_skinClasses!.length} classes');
    } catch (e) {
      debugPrint('[MLService] Skin model load error: $e');
    }
```

### Edit C — dispatch (in `classifyImage()` switch, ~line 215)

Update the dartdoc line:
```dart
  /// Classify an image. [type]: 'skin', 'eye', 'lung', 'malaria'.
```

Add the case:
```dart
    switch (type) {
      case 'skin':
        model = _skinModel;
        classes = _skinClasses;
        break;
      case 'eye':
        ...
```

The rest of `classifyImage()` — including the [tflite_flutter shallow-copy gotcha](../CLAUDE.md) workaround and `_canonicalizeImageClass` — already handles any `type`. You don't touch it.

## 8 · Update CLAUDE.md

Required per project convention. In [`CLAUDE.md`](../CLAUDE.md):

**In "Known-dead-end experiments":** delete the `Skin image model` bullet (the dead-end status no longer applies).

**In the bundled-models table:** add a new row:

```markdown
| `skin_disease_model.tflite` | 128×128×3 | [1, N] | ~2.5 MB | N-class dermatology classifier. Val_acc 0.XX on DermNet. See model_training/KAGGLE_SKIN_TRAINING.md |
```

## 9 · Verify

From `android_app/`:

```bash
~/development/flutter/bin/flutter analyze --no-fatal-infos   # 0 errors, 0 warnings
~/development/flutter/bin/flutter build apk --debug
```

Install the debug APK on a device, go to the assessment flow, capture a skin image, and confirm the classifier returns a ranked list (not "Model not available").

## 10 · UI entry point

If there isn't already a "Scan skin" button on the assessment screen, add one that mirrors the existing eye/lung image-capture buttons — routing into:

```dart
final results = await mlService.classifyImage(
  imageData: preprocessedImage,
  type: 'skin',
);
```

Where `preprocessedImage` is a `List<List<List<double>>>` of shape `[128][128][3]` normalized with the same preprocessing as eye/lung (verify by reading the existing call site).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `classifyImage` returns all zero probs | [tflite_flutter shallow-copy gotcha](../CLAUDE.md) | You modified `classifyImage()` — revert; the existing `List.generate(1, ...)` pattern is correct |
| TFLite file is >4 MB | float16 quantization disabled | Re-run training; confirm `converter.target_spec.supported_types = [tf.float16]` was applied |
| Model loads but every prediction is the same class | Input normalization mismatch | The app must feed images through the same `mobilenet_v2.preprocess_input` scaling `[-1, 1]` that the Kaggle script used |
| Accuracy looks good on Kaggle but bad on-device | Class label case-mismatch | Check `_canonicalizeImageClass` in ml_service.dart; add your new labels if needed |
