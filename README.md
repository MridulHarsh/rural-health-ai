# Rural Health AI

**An offline AI triage assistant for India's 1.05 M ASHA (community health) workers.**

A Flutter Android app that runs fully offline after install, in 12 Indian languages, on phones as low-spec as Android 6.0 + 2 GB RAM. Submission for the CureBay Hackathon 2026.

📦 **Install the latest APK** from the [GitHub Actions artifacts](https://github.com/MridulHarsh/rural-health-ai/actions) (each push builds a signed APK you can download)
📊 **Deck** — `presentation/CUREBAY_PITCH_BRIEF.md` + `presentation/CLAUDE_DESIGN_PROMPT.md`
🧠 **Contributor guide** — [CLAUDE.md](CLAUDE.md) at the repo root documents every architectural invariant

---

## What it does

An ASHA worker with a patient in front of her can:

1. **Tap symptom chips** (or speak them in her language — offline STT)
2. **Enter vitals** (temp, BP, HR, SpO₂ — any subset)
3. **Capture an image** for skin / eye / chest-X-ray / blood-smear / prescription-OCR analysis
4. **See a ranked triage result** within seconds — red/yellow/green risk tier, top diseases with confidence, recommended next steps
5. **Send a pre-filled summary to a PHC doctor** via WhatsApp, SMS, or the dialer — queued and auto-sent when signal returns

All of this happens on-device. No cloud calls. No API keys. No subscription. Ever.

---

## Key facts

| Fact | Value |
|---|---|
| **APK size** | ~55 MB |
| **Target** | Android 6.0 (API 23) + 2 GB RAM |
| **Languages** | 12, at 100 % translation coverage (see below) |
| **On-device ML models** | 10 (1 general + 6 specialist tabular + 4 imaging) |
| **Curated disease profiles** | 162, with 11 red-flag rules and 642 symptom aliases |
| **Internet required after install** | Zero |
| **Data that leaves the phone** | Zero (PII is AES-256-GCM encrypted at rest; keys live in Android Keystore) |
| **Cost per diagnosis** | ₹0, forever |

---

## Language coverage (100 %)

All 12 languages now ship with all 296 canonical UI strings fully translated — no silent English fallbacks on any screen.

| Code | Language | Script | Status |
|---|---|---|---|
| `en` | English | Latin | ✅ 296/296 |
| `hi` | हिन्दी (Hindi) | Devanagari | ✅ 296/296 |
| `ta` | தமிழ் (Tamil) | Tamil | ✅ 296/296 |
| `te` | తెలుగు (Telugu) | Telugu | ✅ 296/296 |
| `ml` | മലയാളം (Malayalam) | Malayalam | ✅ 296/296 |
| `kn` | ಕನ್ನಡ (Kannada) | Kannada | ✅ 296/296 |
| `bn` | বাংলা (Bengali) | Bengali | ✅ 296/296 |
| `mr` | मराठी (Marathi) | Devanagari | ✅ 296/296 |
| `gu` | ગુજરાતી (Gujarati) | Gujarati | ✅ 296/296 |
| `or` | ଓଡ଼ିଆ (Odia) | Odia | ✅ 296/296 |
| `pa` | ਪੰਜਾਬੀ (Punjabi) | Gurmukhi | ✅ 296/296 |
| `as` | অসমীয়া (Assamese) | Assamese | ✅ 296/296 |

Translations use community-spoken terms, not Sanskritic / academic medical vocabulary. An ASHA in rural Odisha or a patient in Tamil Nadu sees the words a villager would actually say.

---

## Feature set

### Diagnostic pipeline
- **Clinical-reasoning-first engine** — 162 curated disease profiles, scored by cardinal/common/occasional symptoms + prevalence + explanatory power. Not an LLM. Every decision is auditable.
- **11 red-flag rules** that override everything — shock, respiratory distress, severe dehydration, stroke FAST, meningitis signs, etc.
- **ML boost layer** — a general 754-class tabular classifier plus six specialist screenings (heart, diabetes, kidney, liver, stroke, maternal risk) that upweight existing candidates. Feature-coverage is reported so partial-data predictions are flagged.
- **4 image classifiers** — eye (cataract / DR / glaucoma), lung (pneumonia / TB / COVID-19), malaria (parasitized / uninfected), and skin (8 clinical supergroups — triage-only, gated behind a confidence floor).

### Workflow
- **12 languages** (see table above), including offline voice input in the selected language.
- **OCR** for prescription / report photos (Google ML Kit, fully offline).
- **Maternal & Child Health** — Naegele's EDD, 4-visit ANC schedule, full UIP immunization tracker, batch-commit workflow.
- **Dosage calculator** — weight-and-age-adjusted pediatric dosing with both per-dose and daily caps (paracetamol, amoxicillin, zinc, ORS, vitamin A).
- **Medicine inventory** — pre-seeded with the WHO essential list, expiry alerts.
- **Outbreak detection** — 7-day cluster scan across household IDs, flags anomalies.
- **PDF export + PHC handoff** — patient summary as a one-page PDF, plus one-tap share via WhatsApp / SMS / dialer.
- **Emergency alarm** — vibration pattern on red-flag trigger.

### Privacy & security
- **AES-256-GCM** encryption on every PII column (patient name, voice transcripts, notes). Keys stored in Android Keystore via `flutter_secure_storage`.
- `allowBackup=false` + explicit `dataExtractionRules` that block all domains from cloud backup and device transfer (encrypted ciphertext is non-portable, so a backup would be useless to the legitimate user and a static target for attack).
- Zero telemetry. Zero ads. Zero trackers. The only network permission is for the optional PHC handoff (WhatsApp deep-link).
- Legacy storage permissions capped at `maxSdkVersion` 28 / 32 — no dead permissions in Play Store disclosure on modern Android.

---

## Repo layout

```
rural_health_ai/
├── android_app/             # Flutter app (the uploaded artifact)
│   ├── lib/
│   │   ├── main.dart, app.dart
│   │   ├── screens/         # Home, Assessment (4-step), Results, History,
│   │   │                    # Settings, Inventory, MCH, Dosage
│   │   ├── services/        # Clinical engine, ML service, SQLite,
│   │   │                    # encryption, OCR, handoff, outbreak detector
│   │   ├── models/          # Patient, Vitals, AssessmentResult, RiskLevel
│   │   └── l10n/            # 12-language translations (296 keys each)
│   ├── assets/models/       # Bundled TFLite + class JSON files
│   └── android/             # Android manifest, Gradle, signing config
├── model_training/          # Python training pipelines
│   ├── train_all.py, train_tabular.py, train_images.py
│   ├── kaggle_skin_model.py # paste-into-Kaggle script for the skin model
│   ├── export_tflite.py
│   └── KAGGLE_SKIN_TRAINING.md   # skin-model retrain walkthrough
├── presentation/            # Hackathon pitch deck brief + Claude Design prompt
├── .github/workflows/       # CI: builds signed APK on every push / PR
├── CLAUDE.md                # Contributor guide — architectural invariants
├── KEYSTORE_SETUP.md        # Release-signing walkthrough (5 min, one-time)
└── README.md                # This file
```

---

## Quick start — run locally

### 1. Set up the environment

```bash
# Flutter SDK 3.24+ required (JDK 17 is pulled transitively)
flutter doctor                 # verify

# Clone
git clone https://github.com/MridulHarsh/rural-health-ai
cd rural-health-ai/android_app
flutter pub get
```

### 2. Plug in an Android device or start an emulator

```bash
flutter devices                # confirm it shows up
flutter run                    # debug build, hot reload
```

Or build an installable APK:

```bash
flutter build apk --release --target-platform android-arm64
# Output: build/app/outputs/flutter-apk/app-release.apk
```

The app auto-signs with the debug keystore out of the box. For a Play-Store-grade signed build, follow [KEYSTORE_SETUP.md](KEYSTORE_SETUP.md) — it takes 5 minutes and a one-line `keytool` command.

### 3. Try a quick triage

Start a new assessment → tap 3-4 symptoms (fever, cough, fatigue) → enter a temperature above 100 °F → hit Analyze. You should see a ranked list of conditions with confidence scores and a risk tier. Try the same flow in Marathi or Tamil from Settings → Language to verify the 100 % translation coverage.

---

## Re-training models

### Tabular + specialist models
```bash
conda activate rural_health     # python 3.11
cd model_training
python train_all.py             # retrains every tabular + specialist model
python export_tflite.py         # converts → tflite, copies into android_app/assets/models/
```

### Skin classifier (runs on Kaggle, not locally)
See [model_training/KAGGLE_SKIN_TRAINING.md](model_training/KAGGLE_SKIN_TRAINING.md) for the end-to-end walkthrough. The training script auto-detects any attached skin dataset under `/kaggle/input/`, applies a 23 → 8 clinical-supergroup collapse for DermNet, runs two-stage transfer learning with a safety guard that reverts regression in stage 2, and exports a float16-quantized TFLite + JSON classes file + metadata you copy into `assets/models/`.

---

## CI / CD

Every push to `main` and every PR triggers [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml):

1. JDK 17 + Flutter 3.24.5 stable
2. `flutter pub get`
3. `flutter analyze --no-fatal-infos` (0 errors, 0 warnings gate; `prefer_const_constructors` info hints are tolerated per [CLAUDE.md](CLAUDE.md) policy)
4. `flutter build apk --release`
5. Artifact uploaded as `rural-health-ai-<sha>`, retained 30 days

When the four signing secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) are configured, the build signs with your real upload key. When they're absent (fork builds, fresh clones), it falls through to the debug keystore automatically — both paths produce an installable APK. See [KEYSTORE_SETUP.md](KEYSTORE_SETUP.md).

---

## Status & honest caveats

- **Skin classifier is below the 70 % ship gate** (currently val_acc 0.407 on DermNet 8-supergroup). We re-added it as a product decision for the hackathon build, gated behind a stiff confidence floor (0.55) that degrades low-confidence predictions to a PHC-referral sentinel. The UI displays an amber "Preliminary — confirm at PHC" banner in that case. Upgrade path documented in [CLAUDE.md](CLAUDE.md) (EfficientNetB0 @ 224×224, drop the broken Bacterial class).
- **Voice input quality** depends on the device's native Speech-to-Text engine. Tested on Samsung and Pixel; lower-end phones may transcribe noisily, which the fuzzy symptom matcher partially recovers.
- **Specialist model feature coverage** is reported as a `featureCoverage` signal — when the ASHA enters only a few vitals, the biased-toward-"normal" output gets flagged. UI should display that indicator on partial inputs (wiring in progress).

---

## Team

- **Mridul Harsh** — Product & ML. Clinical engine, label-aware scoring, symptom-resolution graph.
- **Dhaval Gupta** — Android & Systems. Flutter architecture, offline inference pipeline, SQLite + encryption.
- **Ahan Bansal** — Clinical data & UX. Curated the 162 disease profiles with ICMR references, 642-alias dictionary, and coordinated the 12-language translation pass.

---

## Contributing

1. Read [CLAUDE.md](CLAUDE.md) first — it documents invariants like the 4-stage symptom resolution chain, the tflite_flutter shallow-copy gotcha, and the label-aware risk scoring pattern that are easy to accidentally break.
2. Before opening a PR: `cd android_app && ~/development/flutter/bin/flutter analyze --no-fatal-infos` must show 0 errors / 0 warnings.
3. `flutter build apk --debug` must succeed locally.
4. Symptom keys and disease-profile IDs must match `clinical_knowledge.dart`'s `symptomSystemMap` / profile canonicals — see the "4-stage symptom resolution chain" section of CLAUDE.md for how to add a new symptom correctly.
5. CI will auto-run analyze + build on every PR.

## License

See [LICENSE](LICENSE) if present, otherwise all rights reserved (hackathon submission, pre-license).
