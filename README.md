# Rural Health AI

**An offline AI triage assistant for India's 1.05 M ASHA (community health) workers.**

[![Build APK](https://github.com/MridulHarsh/rural-health-ai/actions/workflows/build-apk.yml/badge.svg?branch=main)](https://github.com/MridulHarsh/rural-health-ai/actions/workflows/build-apk.yml)

A Flutter Android app that runs fully offline after install, in 12 Indian languages, on phones as low-spec as Android 6.0 + 2 GB RAM. Submission for the CureBay Hackathon 2026.

📦 **Install the latest APK** — every push to `main` and every PR build produces a downloadable APK on the [Actions tab](https://github.com/MridulHarsh/rural-health-ai/actions). Pick the latest green run, scroll to **Artifacts**, download `rural-health-ai-<sha>`, `adb install` or side-load on any Android 6.0+ device.
📊 **Pitch deck** — `presentation/CUREBAY_PITCH_BRIEF.md` + `presentation/CLAUDE_DESIGN_PROMPT.md`
🧠 **Contributor guide** — [CLAUDE.md](CLAUDE.md) at the repo root documents every architectural invariant
🔐 **Release signing** — [KEYSTORE_SETUP.md](KEYSTORE_SETUP.md) (one-time, 5 min)

---

## What it does

An ASHA worker with a patient in front of her can:

1. **Tap symptom chips** (or speak them in her language — offline STT)
2. **Enter vitals** (temp, BP, HR, SpO₂ — any subset; missing vitals are flagged, not zero-filled)
3. **Capture an image** for skin / eye / chest-X-ray / blood-smear analysis, or OCR a paper prescription
4. **See a ranked triage result** within seconds — red/yellow/green risk tier, top diseases with confidence scores, recommended next steps, and an auditable reasoning trace
5. **Send a pre-filled summary to a PHC doctor** via WhatsApp, SMS, or the dialer — queued and auto-sent when signal returns

All of this happens on-device. No cloud calls. No API keys. No subscription. Ever.

Additional modules in the same app:

- **Maternal & Child Health** tracker — Naegele's EDD, 4-visit ANC schedule, full UIP immunization tracker, batch-commit workflow
- **Dosage calculator** — weight/age-adjusted pediatric dosing with both per-dose and daily safety caps
- **Medicine inventory** — pre-seeded with the WHO essential list, expiry alerts, stock-out detection
- **Outbreak detector** — 7-day cluster scan across household IDs, flags anomalies before they spread
- **Emergency dialer** — one-tap for India's 108 ambulance and other emergency short codes

---

## Key facts

| Fact | Value |
|---|---|
| **APK size** | **~60 MB** (CI release build, universal APK) |
| **Target** | Android 6.0 (API 23) + 2 GB RAM |
| **Languages** | 12, at **100 % translation coverage** (296/296 keys per language) |
| **On-device ML models** | **10** (1 general + 6 specialist tabular + 4 imaging) |
| **Curated disease profiles** | **162**, with **11 red-flag rules** and **642 symptom aliases** |
| **Internet required after install** | **Zero** |
| **Data that leaves the phone** | **Zero** (PII is AES-256-GCM encrypted at rest; keys live in Android Keystore) |
| **Cost per diagnosis** | **₹0**, forever |
| **Code audits** | **2 parallel-subagent audit rounds**, 32 issues found, all fixed |

---

## Language coverage (100 %)

All 12 languages ship with all 296 canonical UI strings fully translated — no silent English fallbacks on any screen.

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

Translations use community-spoken terms, not Sanskritic / academic medical vocabulary. An ASHA in rural Odisha or a patient in Tamil Nadu sees the words a villager would actually say — `ताप` / `காய்ச்சல்` / `ജ്വരം`, not `ज्वर` / `ஜ்வரம்`.

---

## Feature set

### Diagnostic pipeline

- **Clinical-reasoning-first engine** — 162 curated disease profiles, scored by cardinal / common / occasional symptoms + prevalence + explanatory power. Not an LLM. Every decision is auditable — tap a prediction to see which symptoms explained it.
- **11 red-flag rules** that override everything — shock, respiratory distress, severe dehydration, stroke FAST, meningitis signs, eclampsia, snake bite, etc.
- **Age-based risk escalation** for vulnerable populations (<5 yr and >65 yr) with a permissive cardinal-coverage threshold so decompensating children don't slip through the cracks when no single red-flag symptom triad fires.
- **ML boost layer** — a general 754-class tabular classifier plus six specialist screenings (heart, diabetes, kidney, liver, stroke, maternal risk) that upweight existing candidates. Feature coverage is reported as a signal so partial-data predictions can be surfaced to the UI.
- **4 image classifiers** with EXIF-orientation baking so rotated phone photos don't garble the model input:
  - **Skin** — 8 clinical supergroups (triage-level, gated behind a confidence floor — see caveats below)
  - **Eye** — cataract / diabetic retinopathy / glaucoma
  - **Lung** — pneumonia / TB / COVID-19 (on uploaded X-ray photos)
  - **Malaria** — parasitized / uninfected blood smear

### Workflow

- **12 Indian languages** (see table above), including offline voice input in the selected language
- **OCR** for prescription / report photos (Google ML Kit, fully offline)
- **Maternal & Child Health** — Naegele's EDD, 4-visit ANC schedule, full UIP immunization tracker
- **Dosage calculator** — weight-and-age-adjusted pediatric dosing with per-dose AND daily caps. Paracetamol clamps at the WHO/NICE 75 mg/kg or 3000 mg/day pediatric ceiling to prevent hepatotoxicity on 3-day courses; amoxicillin at 1500 mg/day pediatric
- **Medicine inventory** — pre-seeded with the WHO essential list, expiry alerts, stock-out detection
- **Outbreak detection** — 7-day cluster scan across household IDs
- **PDF export + PHC handoff** — patient summary as a one-page PDF, plus one-tap share via WhatsApp / SMS / dialer; emergency short codes (108, 112, 102, etc.) bypass the phone-format validation so ambulance dispatch always works
- **Emergency alarm** — vibration pattern on red-flag trigger

### Privacy & security

- **AES-256-GCM** encryption on every PII column (patient name, voice transcripts, notes). Keys stored in Android Keystore via `flutter_secure_storage`
- `allowBackup=false` + explicit `dataExtractionRules` XML that blocks all domains from cloud backup and D2D transfer (encrypted ciphertext is non-portable, so a backup would be useless to the legitimate user and a static target for offline attack)
- Zero telemetry. Zero ads. Zero trackers. The only network permission is for the optional PHC handoff (WhatsApp deep-link)
- Legacy storage permissions capped at `android:maxSdkVersion="28"` / `"32"` — no dead permissions in Play Store disclosure on modern Android
- R8 release build hardened with **`-keep`** rules for every plugin that uses reflection (TFLite JNI, `encrypt` + `pointycastle`, `flutter_secure_storage`, ML Kit TextRecognizer, sqflite, pdf/printing, speech_to_text) — prevents the "works on debug, silent-crashes on release" class of bug

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
│   └── android/
│       ├── app/build.gradle.kts     # Release signing + R8 config
│       ├── app/proguard-rules.pro   # R8 keep rules for reflection plugins
│       └── app/src/main/res/xml/data_extraction_rules.xml  # Block OS backup
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
# Flutter SDK 3.41+ required (matches CI pin; JDK 17 is pulled transitively)
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
# Single ABI — smaller, ~50 MB
flutter build apk --release --target-platform android-arm64

# Universal APK — all ABIs, larger, matches CI artifact
flutter build apk --release

# Output (either way):
# build/app/outputs/flutter-apk/app-release.apk
```

The app auto-signs with the debug keystore out of the box. For a Play-Store-grade signed build, follow [KEYSTORE_SETUP.md](KEYSTORE_SETUP.md) — it takes 5 minutes and a one-line `keytool` command.

### 3. Try a quick triage

Open **New Patient Assessment** → tap 3–4 symptoms (fever, cough, fatigue) → enter a temperature above 100 °F → on step 4, note that skin triage is the default image-capture option (most common ASHA use case) → hit Analyze. You should see a ranked list of conditions with confidence scores and a risk tier. Try the same flow in Marathi or Tamil from **Settings → Language** to verify the 100 % translation coverage.

---

## Re-training models

### Tabular + specialist models (runs locally)

```bash
conda activate rural_health     # python 3.11
cd model_training
python train_all.py             # retrains every tabular + specialist model
python export_tflite.py         # converts → tflite, copies into android_app/assets/models/
```

### Skin classifier (runs on Kaggle with free GPU)

See [model_training/KAGGLE_SKIN_TRAINING.md](model_training/KAGGLE_SKIN_TRAINING.md) for the end-to-end walkthrough. The training script auto-detects any attached skin dataset under `/kaggle/input/`, applies a 23 → 8 clinical-supergroup collapse for DermNet, runs two-stage transfer learning with a safety guard that reverts a regressing Stage 2, and exports a float16-quantized TFLite + JSON classes file + metadata you copy into `assets/models/`. Two backbone options via a top-of-file `BACKBONE` constant: MobileNetV2 @ 128×128 (matches eye/lung/malaria siblings) or EfficientNetB0 @ 224×224 (heavier but clears the ship gate more reliably).

---

## CI / CD

Every push to `main` and every PR triggers [`.github/workflows/build-apk.yml`](.github/workflows/build-apk.yml):

1. JDK 17 + Flutter **3.41.6** stable (matches dev SDK; earlier pins failed the `intl ^0.20.2` solver)
2. `flutter pub get`
3. `flutter analyze --no-fatal-infos` (0 errors / 0 warnings gate; `prefer_const_constructors` info hints are tolerated per [CLAUDE.md](CLAUDE.md) policy)
4. Conditional release-keystore setup — only when the four GitHub Secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) are configured; otherwise falls back to debug signing
5. `flutter build apk --release` with R8 minification + resource shrinking
6. APK-produced verification step — `::error::`s out early with a directory listing if the expected path doesn't exist, instead of a cryptic "no files found" at upload time
7. Artifact uploaded as `rural-health-ai-<sha>`, retained 30 days

Both signing paths produce an installable APK, so the pipeline stays green on fork builds and fresh clones even before keystore secrets are configured. See [KEYSTORE_SETUP.md](KEYSTORE_SETUP.md) for the one-time setup.

---

## Quality bar

This hackathon submission has been through **two rounds of parallel-subagent code audits** covering security + privacy, clinical correctness, Dart correctness, ML integration, UI/a11y/i18n, and CI/build config. **32 real issues were identified and all fixed:**

| Round | Agents | Bugs found | Highlight |
|---|---|---|---|
| 1 | 6 parallel scopes | 20 | Paracetamol daily-dose cap, `allowBackup=false`, EXIF rotation, database decrypt crash resilience, PII-safe phone sanitization |
| 2 | 5 parallel scopes | 12 | 108 emergency-dial regression, age-escalation threshold for <5yo & >65yo, R8 release `-keep` rules for 8 plugins, stale image results on type change |

Every commit includes a "Verified: flutter analyze 0 errors / 0 warnings, debug + release APK builds" footer. The `flutter analyze --no-fatal-infos` output stays at **182 pre-existing info hints, 0 errors, 0 warnings** — no new issues introduced by any audit fix.

### Known caveats (honest)

- **Skin classifier is below the 70 % ship gate** (val_acc **0.407** on DermNet 8-supergroup). Re-added as a product decision for the hackathon build, gated behind a stiff confidence floor (**0.55**) that degrades low-confidence predictions to a PHC-referral sentinel. The UI displays an amber "Preliminary — confirm at PHC" banner when the model isn't confident. Upgrade path documented in [CLAUDE.md](CLAUDE.md) (EfficientNetB0 @ 224×224, drop the broken Bacterial class — val_acc lift of 0.10–0.20 per lever).
- **Voice input quality** depends on the device's native Speech-to-Text engine. Tested on Samsung and Pixel; lower-end phones may transcribe noisily, which the fuzzy symptom matcher partially recovers.
- **Specialist model feature coverage** is reported as a `featureCoverage` signal on `SpecialistScreening` — when the ASHA enters only a few vitals, the biased-toward-"normal" output gets flagged. UI wiring to display that indicator on partial inputs is prepared but not yet rendered on the Results screen.
- **Dedicated sepsis red-flag rule** — no curated profile for pediatric sepsis exists, so the <5yo safety net relies on the age-based escalation threshold. A future pass should add an explicit `RedFlagRule` keyed on fever + tachycardia + poor-perfusion signs.

---

## Team

- **Mridul Harsh** — Product & ML. Clinical engine, label-aware scoring, symptom-resolution graph, dual-round audit orchestration.
- **Dhaval Gupta** — Android & Systems. Flutter architecture, offline inference pipeline, SQLite + encryption.
- **Ahan Bansal** — Clinical data & UX. Curated the 162 disease profiles with ICMR references, 642-alias dictionary, coordinated the 12-language translation pass.

---

## Contributing

1. Read [CLAUDE.md](CLAUDE.md) first — it documents invariants like the 4-stage symptom resolution chain, the tflite_flutter shallow-copy gotcha, and the label-aware risk scoring pattern that are easy to accidentally break.
2. Before opening a PR:
   ```bash
   cd android_app
   ~/development/flutter/bin/flutter analyze --no-fatal-infos   # must be 0 errors, 0 warnings
   ~/development/flutter/bin/flutter build apk --debug          # must succeed
   ```
3. Symptom keys and disease-profile IDs must match `clinical_knowledge.dart`'s `symptomSystemMap` / profile canonicals — see the "4-stage symptom resolution chain" section of CLAUDE.md for how to add a new symptom correctly.
4. CI will auto-run analyze + release build on every PR.

## License

See [LICENSE](LICENSE) if present, otherwise all rights reserved (hackathon submission, pre-license).
