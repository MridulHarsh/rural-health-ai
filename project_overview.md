# Rural Health AI: Project Overview

**Rural Health AI** is an offline-capable Android application built specifically for India's 1.05 million ASHA (community health) workers. Built as a submission for the CureBay Hackathon 2026, the application allows health workers to triage patients, track maternity and child health, and execute diagnostics—all entirely offline to accommodate areas with little to no internet connectivity. 

## Key Highlights

- **Platform:** Android (min API 23 / Android 6.0 + 2 GB RAM). Built with Flutter (Dart) and Python (ML Training).
- **Core Engine:** A clinical-reasoning-first engine backed by 162 curated disease profiles and an ML boost layer, rather than an LLM.
- **Language Support:** 100% translation coverage across 12 Indian languages (296 UI strings each) including offline voice-input capabilities in native languages.
- **Privacy First:** 0 internet requirement post-installation. No cloud calls. All patient PII is AES-256-GCM encrypted and stored locally in SQLite (`allowBackup=false`).
- **Offline ML Models:** 10 bundled TFLite models for disease detection (1 general tabular model, 6 specialist tabular models, and 3 image classifiers).

## Application Features

### 1. Diagnostic Pipeline
- **Symptom Collection:** ASHA workers can use voice (offline STT), tap symptom chips, or OCR paper prescriptions.
- **Vitals Integration:** Support for temperature, BP, HR, SpO₂.
- **Triage Result:** Produces a ranked triage list with condition confidence scores, risk level (green/yellow/red), and auditable clinical reasoning. 
- **11 Red-Flag Rules:** Overtake the standard engine to immediately flag life-threatening conditions (e.g., severe dehydration, shock).
- **Predictive ML Boost:** A general 754-classtabular classifier and six specialist tabular models (heart, diabetes, kidney, liver, stroke, maternal risk) act as a *boost factor* to the clinical-reasoning engine (max 1.25x boost).
- **Offline Image/OCR Models:** 
  - **Eye** (Cataract, Diabetic Retinopathy, Glaucoma)
  - **Lung** (Pneumonia, TB, COVID-19)
  - **Malaria** (Parasitized / Uninfected)
  - **Skin Classifier** 8 clinical supergroups. Currently gated behind an amber "Preliminary - confirm at PHC" banner because of relatively low val_acc.
  - **OCR** for prescription reading (via Google ML Kit).

### 2. Broad Health Modules
- **Maternal & Child Health (MCH) Tracker:** Manages Naegele's EDD, ANC schedule, and full UIP immunizations.
- **Dosage Calculator:** Computes age/weight-adjusted pediatric dosages, clamping tightly to daily and per-dose safety maximums to prevent toxicity (e.g. Paracetamol capped to WHO/NICE guidelines).
- **Medicine Inventory:** Seeded natively with the WHO essential list, catching expirations and stock-outs.
- **Outbreak Detector:** Monitors 7-day clustering over local assessment data based on household IDs.
- **PDF & Communication Handoff:** Can export one-page triage PDFs natively to WhatsApp, SMS, or the dialer to a Primary Health Center (PHC).

## Tech Stack & Architecture

- **Client App:** Flutter (`android_app/`). Uses Riverpod/Services for state, TFLite for local ML inference, and native SQLite for encrypted db storage.
- **Model Training:** Python (`model_training/`). Uses scikit-learn/Keras depending on the model, exporting `.tflite` files alongside JSON dictionaries that the Flutter app consumes.
- **Architecture Principle:** The prediction pipeline leverages **4-stage symptom resolution**: 
  UI chip → Alias map → System Mapping → Disease Profile Cardinal assignment. 
- **CI/CD:** GitHub Actions `.github/workflows/build-apk.yml` handles compiling and signing R8-minified APK bundles on push and PR.

## Codebase Layout
- **`android_app/`**: Contains the complete Flutter project.
  - `lib/services/`: The core brains of the app (Clinical engine, ML orchestrators, Encryption, Database wrappers).
  - `assets/models/`: Bundled TFLite outputs imported from the Python ML side.
  - `lib/l10n/`: Complete 12-language translation mappings.
- **`model_training/`**: Python scripts (`train_all.py`, `train_tabular.py`, Kaggle workflows) strictly for updating models. 
- **`CLAUDE.md` / `README.md`**: Foundational guides outlining dev invariants (tflite pointer bugs, symptom chains), setup basics, and the hackathon presentation background.

## Getting Started

To view the app, ensure Flutter 3.41+ is on your system, then:
```bash
cd android_app
flutter pub get
flutter run
```
You can generate full universal release APKs without keys via `flutter build apk --release` (which will fall back to debug signing gracefully).
