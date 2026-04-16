# 🏥 Rural Health AI Assistant

**Offline Multimodal AI Assistant for Rural Health Workers**

An offline-capable, multilingual Android app that helps ASHA workers and rural health staff perform preliminary health assessments using text, voice, and image inputs.

---

## 📁 Project Structure

```
rural_health_ai/
├── model_training/          # Python ML pipeline (run on your Mac M2)
│   ├── train_model.py       # Main training script
│   ├── export_tflite.py     # Convert trained model → TFLite
│   ├── risk_mapping.json    # Disease → risk level mapping
│   ├── requirements.txt     # Python dependencies
│   └── data/                # Place Kaggle datasets here
│       └── .gitkeep
├── android_app/             # Flutter Android app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app.dart
│   │   ├── screens/
│   │   ├── services/
│   │   ├── models/
│   │   ├── widgets/
│   │   └── l10n/            # Translations (12 Indian languages)
│   ├── assets/
│   │   └── models/          # Place exported .tflite + .json here
│   ├── pubspec.yaml
│   └── android/
└── README.md                # This file
```

---

## 🚀 Step 1: Train the Model (MacBook Air M2)

### 1.1 Setup Conda Environment
```bash
conda create -n rural_health python=3.11 -y
conda activate rural_health
cd model_training
pip install -r requirements.txt
```

### 1.2 Download Datasets from Kaggle
Download these datasets and place CSVs in `model_training/data/`:

1. **Disease-Symptom** → https://www.kaggle.com/datasets/itachi9604/disease-symptom-description-dataset
   - Place `dataset.csv` as `data/disease_symptom.csv`

2. **Heart Disease** → https://www.kaggle.com/datasets/johnsmith88/heart-disease-dataset
   - Place as `data/heart_disease.csv`

3. **Diabetes** → https://www.kaggle.com/datasets/akshaydattatraykhare/diabetes-dataset
   - Place as `data/diabetes.csv`

4. **Disease-Symptom-Profile** → https://www.kaggle.com/datasets/uom190346a/disease-symptoms-and-patient-profile-dataset
   - Place as `data/disease_profile.csv`

### 1.3 Train & Export
```bash
python train_model.py
python export_tflite.py
```

This produces:
- `output/disease_model.tflite` (< 2MB)
- `output/symptom_list.json`
- `output/disease_list.json`
- `output/risk_mapping.json`
- `output/model_metadata.json`

### 1.4 Copy to Android App
```bash
cp output/*.tflite ../android_app/assets/models/
cp output/*.json ../android_app/assets/models/
```

---

## 📱 Step 2: Build the Android App

### 2.1 Prerequisites
- Flutter SDK 3.19+ → https://docs.flutter.dev/get-started/install/macos
- Android Studio with Android SDK
- A physical Android device or emulator

### 2.2 Setup
```bash
cd android_app
flutter pub get
```

### 2.3 Build APK
```bash
# Debug build (for testing)
flutter run

# Release APK (for distribution)
flutter build apk --release --target-platform android-arm64
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

---

## 🌐 Supported Languages
English, हिन्दी (Hindi), தமிழ் (Tamil), తెలుగు (Telugu),
മലയാളം (Malayalam), ಕನ್ನಡ (Kannada), বাংলা (Bengali),
मराठी (Marathi), ગુજરાતી (Gujarati), ଓଡ଼ିଆ (Odia),
ਪੰਜਾਬੀ (Punjabi), অসমীয়া (Assamese)

---

## 📋 Features
- ✅ Fully offline — no internet required after install
- ✅ Text symptom input with autocomplete
- ✅ Voice input in local languages (Android STT)
- ✅ Camera image capture for visible conditions
- ✅ Top 3 possible conditions with confidence scores
- ✅ Risk triage: 🔴 Emergency / 🟡 Urgent / 🟢 Normal
- ✅ Suggested next steps and care guidance
- ✅ Patient summary PDF export
- ✅ Works on Android 6.0+ (low-spec phones, ~50MB)
