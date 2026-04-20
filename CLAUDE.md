# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Rural Health AI** — an offline-capable Android assistant for ASHA (rural health) workers in India. Submission for the CureBay Hackathon 2026. Built with Flutter (Dart) on the client and Python for ML training. Runs fully offline after install; supports 12 Indian languages; targets low-spec phones (Android 6.0+, ~2 GB RAM).

## Repo layout

```
rural_health_ai/
├── android_app/                          # Flutter app (the uploaded artifact)
│   ├── lib/
│   │   ├── app.dart, main.dart           # GoogleFonts.allowRuntimeFetching=false
│   │   ├── models/patient.dart           # Patient, Vitals, AssessmentResult, RiskLevel
│   │   ├── services/                     # See "Service layer" below
│   │   ├── screens/                      # Home, Assessment (4-step), Results, History,
│   │   │                                 # Settings, Inventory, MCH, Dosage
│   │   └── l10n/translations.dart        # 12 languages, 296 keys each (100% coverage)
│   ├── assets/models/                    # Bundled TFLite + JSON class/feature files
│   └── android/
│       ├── app/build.gradle.kts          # Release signing + R8/ProGuard config
│       ├── app/proguard-rules.pro        # -keep rules for reflection plugins
│       └── app/src/main/
│           ├── AndroidManifest.xml       # <queries> block + allowBackup=false
│           └── res/xml/data_extraction_rules.xml   # Blocks cloud-backup + D2D
├── model_training/                       # Python training pipelines (run locally; outputs
│   │                                     # go to android_app/assets/models/)
│   ├── train_all.py, train_tabular.py,
│   │   train_images.py, export_tflite.py
│   ├── kaggle_skin_model.py              # Paste-into-Kaggle cell for the skin retrain
│   ├── KAGGLE_SKIN_TRAINING.md           # Walk-through for the Kaggle run
│   └── output_v2/                        # GITIGNORED — multi-GB joblib pickles
├── presentation/                         # Hackathon deck brief + Claude Design prompt
├── .github/workflows/build-apk.yml       # CI: builds signed APK on every push/PR
├── CLAUDE.md                             # You are here
├── KEYSTORE_SETUP.md                     # 5-min release-signing walkthrough
└── README.md, setup.sh
```

Both `android_app/` and `model_training/` are independently buildable. The Flutter app doesn't call Python at runtime; it just consumes the `.tflite` / `.json` artifacts that training produces.

## Environment

| Piece | Location | Notes |
|---|---|---|
| Flutter SDK | `~/development/flutter/` (3.41.6 stable) | **NOT on PATH.** Invoke as `~/development/flutter/bin/flutter ...`. CI pins the same version — earlier pins failed the `intl ^0.20.2` pubspec solver. |
| Conda env | `rural_health` (Python 3.11) | **Always** `conda activate rural_health` before training. The base env has a broken tensorflow-metal that segfaults. |
| Android SDK | `~/Library/Android/sdk` | |
| Dev machine | MacBook Air M2 (8 GB) | |
| Test device | Samsung S24 FE (physical, USB debug) or Pixel 4a API 34 emulator | |

## Common commands

```bash
# From android_app/
~/development/flutter/bin/flutter analyze              # Must show 0 errors, 0 warnings
~/development/flutter/bin/flutter pub get              # Resolve deps after pubspec.yaml edit
~/development/flutter/bin/flutter run                  # Debug on connected device
~/development/flutter/bin/flutter build apk --debug --target-platform android-arm64
~/development/flutter/bin/flutter build apk --release  # Release APK

# Python (from model_training/, inside conda env)
source ~/anaconda3/etc/profile.d/conda.sh && conda activate rural_health
python3 train_all.py          # Train everything
python3 export_tflite.py      # Convert .joblib → .tflite; copies into android_app/assets/models/

# Reachability/data audit (run from android_app/)
python3 -c "$(cat << 'EOF'
# Quick version — full template in git history under audit scripts.
# Parses clinical_knowledge.dart + assessment_screen.dart to verify:
#  - Every UI chip resolves via alias to a symptomSystemMap key
#  - Every DiseaseProfile cardinal is reachable from UI chips
#  - 0 orphan symptoms, 0 dead chips, 0 alias cycles
import re; from pathlib import Path
# ... (see session history for full script)
EOF
)"
```

After any change, run `flutter analyze` from `android_app/` and confirm 0 errors + 0 warnings. Only `prefer_const_constructors` info messages are acceptable.

## Architecture: the prediction pipeline

The diagnostic pipeline is **clinical-reasoning-first**, not ML-first. This is deliberate and should not be inverted.

```
symptoms (chips + voice + OCR) ──┐
vitals (temp, BP, HR, SpO2) ─────┼──► ClinicalEngine.diagnose()  ──► DiagnosticResult
demographics (age, sex) ─────────┘        ▲                         (red flag, ranked conditions,
                                          │                          risk level, body systems)
                                          │
                                          └─ ML boost (optional): mlConfidences from the
                                             general 754-class TFLite classifier, used ONLY
                                             to upweight existing DiseaseProfile candidates
                                             by matching ID. Never adds new candidates.

Separately: SpecialistModelsService.screenAll()   → 6 tabular TFLite models (heart, diabetes,
                                                    kidney, liver, stroke, maternal)
            MLService.classifyImage()             → 3 image TFLite models (eye, lung, malaria)
```

### 4-stage symptom resolution chain

This is the most important architectural invariant in the app. A symptom selected by the user goes through:

1. **UI chip** (`_symptomsByCategory` in `assessment_screen.dart`)
2. **`symptomAliases`** (clinical_knowledge.dart) — maps chip names, voice transcripts, native-script phrases to canonicals. Aliases are transitively resolved by `_resolveAliasChain` in `clinical_engine.dart` and `fuzzy_symptom_matcher.dart`.
3. **`symptomSystemMap`** (clinical_knowledge.dart) — canonical symptom → BodySystem weights. Drives `_classifySystems()` which decides which disease candidates to score.
4. **`DiseaseProfile.symptomProfile`** (clinical_knowledge.dart) — `{canonicalKey: SymptomRole.cardinal|common|occasional}`.

**When you add a new symptom, add it at EVERY relevant layer.** A common bug is adding a UI chip without an alias or ssm entry, leaving it dead. Use the reachability audit to verify.

### Clinical engine rules (do not relax)

- **Cardinal elimination**: if a disease has cardinal symptoms but NONE match the patient's, score = 0. Implemented in `clinical_engine.dart` around the `_scoreCandidate` method. This is why every `DiseaseProfile` must have ≥1 cardinal.
- **Scoring weights** (tuned empirically): Cardinal 50%, Common 20%, Prevalence 15%, Explanation 10%, Occasional 5%.
- **Risk calibration**: 2 mild symptoms (e.g. fever + cough) should never produce `ClinicalRisk.emergency`. Red flags produce emergency — disease scoring alone does not.
- **Age-based escalation** (`clinical_engine.dart` ~L590): patients with `age < 5 || age > 65` get `normal → moderate` unconditionally and `moderate → urgent` when `cardinalCoverage > 0.3`. The threshold is deliberately permissive (was 0.6, lowered to 0.3 in the round-2 audit) to catch septic young children who score low on curated profiles — there's no dedicated sepsis profile, so the age-based escalation is the safety net. A future pass should add a `RedFlagRule` keyed on `fever + tachycardia + poor_perfusion` to close this properly.
- **Fever expansion**: the engine auto-adds `fever`/`mild_fever` when any fever variant is present. Also injects `fever`/`high_fever` from vitals when temperature ≥ 100.4°F / ≥ 104°F. If the user wants to report fever without a thermometer reading, there ARE chips (`fever`, `high_fever`, `mild_fever`) in the General category — do not "fix" this by removing them. **All temperature thresholds in this codebase are Fahrenheit** — if a Celsius input path is ever added, auto-convert before the fever check.
- **Pediatric dosing daily cap** (`dosage_screen.dart` `_DrugRule.dose()`): every rule has both `maxMgPerDose` AND `maxMgPerDay`. The compute path clamps by per-dose first, then reduces the dose if `mg * dosesPerDay > maxMgPerDay`. Paracetamol is set to 3000 mg/day (WHO/NICE pediatric cap — prevents hepatotoxicity on the 4-dose 3-day course for 35+ kg children). Never add a new drug rule without setting both caps.

### Service layer (lib/services/)

| File | Role |
|---|---|
| `clinical_knowledge.dart` | Data: 162 `DiseaseProfile`s, 11 `RedFlagRule`s, 295 `symptomSystemMap` keys, 642 `symptomAliases` pairs |
| `clinical_engine.dart` | 5-step diagnostic pipeline. `_normalizeSymptoms` does alias-chain resolution + fuzzy match |
| `ml_service.dart` | Orchestrates ClinicalEngine + tabular ML + image classification. Class is `MLService` (uppercase). |
| `specialist_models.dart` | Singleton loading 6 tabular TFLite models. `buildFromVitals()` maps patient vitals into each model's feature space. Risk scoring is **label-aware** (see note below). `SpecialistScreening` has a required `featureCoverage` field (0.0–1.0) reporting how many of the model's expected features were actually present — UI should de-weight risk when < 0.7, since missing features silently zero-fill and bias predictions toward "normal". |
| `fuzzy_symptom_matcher.dart` | Voice-input matcher: substring + Levenshtein (30% threshold, max edit distance 3), flattens alias chains at lookup-table build time |
| `database_service.dart` | SQLite (schema v2). PII columns (`patient_name`, `voice_transcript`, `notes`) are AES-GCM encrypted via `EncryptionService`. `household_id` groups family members for contagion view. **All PII reads go through `_safeDecrypt`** (try/catch wrapper) — a single corrupt envelope must not crash the entire history retrieval; same resilience pattern as `_safeDecode` for JSON columns. |
| `encryption_service.dart` | AES-256-GCM. Key stored in `flutter_secure_storage` (Android Keystore / iOS Keychain). `encryptString` / `decryptString` produce/consume `iv_b64|ct_b64` envelopes |
| `handoff_service.dart` | WhatsApp (native scheme then wa.me fallback), SMS draft, tel dialer. **Do NOT use `canLaunchUrl` pre-check** — Android 11+ returns false for undeclared packages even when installed. `_sanitizePhone` rejects garbage input outside 7–15 digits, but `_emergencyShortCodes` (100/101/102/104/108/112/1098) bypass the length minimum — never remove that allowlist or `dial('108')` silently returns false. |
| `emergency_service.dart` | Vibration-pattern alarm on red-flag triage |
| `outbreak_detector.dart` | 7-day cluster scan over saved assessments; flags repeated top-condition or high-signal symptoms |
| `ocr_service.dart` | Google ML Kit offline text recognition for scanning prescriptions |
| `inventory_service.dart` | ASHA medicine-kit SQLite table, seeded with WHO essential list on first launch |
| `mch_service.dart` | Maternal & Child Health: Naegele EDD, 4-visit ANC schedule, full UIP immunization schedule |
| `pdf_service.dart` | Patient-summary PDF via `pdf` + `printing`. Class `PdfExportService`, method `printSummary` |

### Bundled ML models (`android_app/assets/models/`)

| File | Input | Output | Size | Notes |
|---|---|---|---|---|
| `disease_model.tflite` | 328-dim symptom vector | [2, 754] probs | 410 KB | General classifier (80.3% RF acc). Only 25 of its 754 classes overlap with curated `DiseaseProfile` IDs — the others are dead weight unless a profile is added |
| `heart_disease.tflite`, `diabetes.tflite`, `kidney_disease.tflite`, `liver_disease.tflite`, `stroke_risk.tflite`, `maternal_risk.tflite` | Per-model feature vector | Binary or 3-class probs | 17-18 KB each | Run through `SpecialistModelsService`. |
| `skin_disease_model.tflite` | 128×128×3 | [1, 8] | 4.28 MB | **BELOW 70% GATE (val_acc 0.407)** — re-added 2026-04-19 despite gate failure, product decision. 8 clinical supergroups (Bacterial / Fungal / Viral / Parasitic / Inflammatory / Allergic / Neoplastic / Autoimmune). Trained from DermNet-23 via `model_training/kaggle_skin_model.py` with clinical merging. Only 2 of 8 supergroups pass per-class recall ≥0.50 (Fungal 0.60, Inflammatory 0.52); **Bacterial at 0.09 recall is effectively broken**. Stage-2 train_acc 0.92 vs val_acc 0.41 → severe overfit. `MLService.classifyImage(type: 'skin', ...)` returns the `Low confidence — confirm at PHC` sentinel when top-1 < `skinConfidenceFloor` (currently 0.55); `assessment_screen.dart` + `results_screen.dart` detect this sentinel and render an amber "Preliminary — confirm at PHC" banner above the ranked list. **Preprocessing-range gotcha**: this model was trained with `mobilenet_v2.preprocess_input` baked into the graph (expects [0, 255] raw), while the Dart preprocessor produces [0, 1] to match eye/lung/malaria. `ml_service.dart` compensates with a scale-by-255 stopgap guarded by `type == 'skin'`; the Kaggle training script has now been fixed (`BACKBONE` constant, no preprocess_input, [0, 1] input) so the next retrain will drop this stopgap naturally. **Upgrade levers** (in `kaggle_skin_model.py`): set `BACKBONE = "efficientnetb0"` (auto-bumps IMG_SIZE to 224) and/or `DROP_SUPERGROUPS = {"Bacterial Infection"}`; expected val_acc lift 0.10–0.20 per lever, combine to target the 70% ship gate. |
| `eye_disease_model.tflite` | 128×128×3 | [1, 4] | 2.6 MB | cataract / diabetic_retinopathy / glaucoma / normal |
| `lung_disease_model.tflite` | 128×128×3 | [1, 6] | 2.6 MB | Labels contain **case-duplicates** (`NORMAL` vs `Normal`, `TURBERCULOSIS` vs `Tuberculosis`). `MLService._canonicalizeImageClass` collapses them before display |
| `malaria_model.tflite` | 128×128×3 | [1, 2] | 2.5 MB | Parasitized / Uninfected blood smear |

## tflite_flutter gotcha (MUST-READ)

`Tensor.copyTo()` → `_duplicateList()` does a **shallow replacement**: `dst[i] = obj[i]`. It does NOT write into the passed list — it replaces its elements with freshly decoded inner lists.

**Wrong** (silently returns all zeros):
```dart
final output = List<double>.filled(classes.length, 0.0);
model.run([imageData], [output]);              // [output] is an inline temp!
// _duplicateList replaces [output][0], but `output` variable still points
// to the original zero-filled list. `output[i]` reads 0.0 forever.
```

**Right** (specialist_models.dart + classifyImage() pattern):
```dart
final output = List.generate(1, (_) => List<double>.filled(classes.length, 0.0));
model.run([imageData], output);
final probs = output[0];                       // contains real probs
```

This is the single most expensive-to-debug bug in the codebase's history. If any new inference call returns suspicious zeros, check this pattern first.

## Specialist model risk scoring

Naive `risk = probs[argmax]` is wrong for multi-class severity models. For maternal_risk (classes `["high risk", "low risk", "mid risk"]`), the top prediction could be "low risk" at 0.9 probability — naive scoring labels that "High Risk". Kidney has a 3-class variant (`["ckd", "ckd\t", "notckd"]` — the `\t` is a training-data whitespace bug).

Use **label-aware mass scoring** in `specialist_models.dart` `_run()`:
```
risk = P(high-risk-labels) + 0.5 · P(mid-risk-labels)
```
with helpers `_isHighRiskLabel` / `_isMidRiskLabel` / `_isLowRiskLabel` that check `_isLowRiskLabel` FIRST (so "notckd" doesn't match the `contains('ckd')` branch for high risk).

## Image preprocessing

`_preprocessImage` in `assessment_screen.dart` is the only place that produces the `List<List<List<double>>>` tensor fed to `MLService.classifyImage`. It:

1. Decodes the file to an `Image` via `package:image`.
2. **`img.bakeOrientation(decoded)`** — mandatory. Phone cameras often save landscape-oriented pixels with EXIF rotation metadata (rotation=6 is common on Android portrait shots); the resize step below does NOT honor EXIF, so without baking, the model receives a 90°-rotated tensor and silently returns garbage.
3. Resizes to 128×128 and emits `/255.0` normalized floats — matches `model_training/train_images.py`'s `img / 255.0` convention for eye/lung/malaria.

**Per-model input-range quirk** — the current `skin_disease_model.tflite` was trained with `mobilenet_v2.preprocess_input` baked into the graph (expects [0, 255] raw), so `ml_service.dart` scales by 255 inside `classifyImage` for `type == 'skin'` only. That stopgap goes away on the next retrain — `kaggle_skin_model.py` now drops `preprocess_input` to match the [0, 1] convention.

## Android manifest requirements

`android/app/src/main/AndroidManifest.xml` must declare:

1. **`<queries>` entries** for `https`, `http`, `sms`, `smsto`, `tel` schemes (so `canLaunchUrl` can see handlers), plus explicit `<package android:name="com.whatsapp" />` and `com.whatsapp.w4b`. Without the queries block, the "Send summary to PHC" button reports "WhatsApp not available" even when installed.
2. **`android:allowBackup="false"`** on `<application>` plus `android:dataExtractionRules="@xml/data_extraction_rules"`. Default `allowBackup=true` would let `adb backup` and Android 12+ D2D transfer copy the encrypted SQLite — ciphertext is non-portable (keys live in Android Keystore on the source device), so a backup copy is both useless to the user AND a static target. The `xml/data_extraction_rules.xml` excludes root / file / database / sharedpref / external from both cloud-backup and device-transfer.
3. **Permissions**: `CAMERA`, `RECORD_AUDIO`, `VIBRATE`, `INTERNET`, plus `WRITE_EXTERNAL_STORAGE` capped at `maxSdkVersion="28"` and `READ_EXTERNAL_STORAGE` at `"32"` — legacy storage perms are no-ops on API 29+ so capping them prevents Play Store warnings and keeps permission disclosure honest.

## Release build — R8 and ProGuard

Release builds run R8 minification + resource shrinking (`isMinifyEnabled = true` / `isShrinkResources = true` in `android/app/build.gradle.kts`). Debug builds skip R8, which means "works on debug" does NOT imply "works in release" — this has bitten CI twice.

`android/app/proguard-rules.pro` has two kinds of rules:

- **`-dontwarn`** for optional classes we intentionally don't bundle (ML Kit Chinese/Japanese/Korean/Devanagari script recognizers, TFLite GPU delegate, Play Core split-install). Without these, R8 aborts with "Missing classes detected" during `minifyReleaseWithR8`.
- **`-keep`** for every plugin that uses reflection (`tflite_flutter` + native JNI, `flutter_secure_storage`, `encrypt` + `pointycastle`, `google_mlkit_text_recognition`, `sqflite`, `pdf` + `printing`, `speech_to_text`). Without these, R8 obfuscates method names that native code or provider lookups expect by string — producing release-only silent failures (AES-GCM decryption returns the raw envelope, TFLite inference crashes, PDF generation fails).

Whenever adding a new plugin dependency, check its README for ProGuard rules and add them here. When in doubt, `flutter build apk --release` is the fastest way to catch R8-introduced breakage — it takes ~80s on a warm machine and the `Missing class` error messages are specific enough to be actionable.

## Release signing (CI + local)

`android/app/build.gradle.kts` reads `android/keystore.properties` if present and signs with the real upload key; otherwise it falls back to the debug keystore so `flutter run --release` works on a fresh clone. The CI workflow at [.github/workflows/build-apk.yml](.github/workflows/build-apk.yml) creates `keystore.properties` from four GitHub Secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) when they're configured, then falls through when they're not. The `if:` guard on the "Configure release signing" step reads a job-level env var (`env.HAS_KEYSTORE`), not a step-level one — a step-level env var is invisible to its own `if:` and was the source of a CI bug.

`keystore.properties` and any `*.jks` under `android_app/android/` are gitignored — these files contain private keys and must never be committed.

See [KEYSTORE_SETUP.md](KEYSTORE_SETUP.md) at the repo root for the one-time secret-generation recipe (5 minutes).

## Internationalization (12 languages at 100%)

All 12 locales (`en`, `hi`, `ta`, `te`, `ml`, `kn`, `bn`, `mr`, `gu`, `or`, `pa`, `as`) ship with all 296 canonical UI strings fully translated in `android_app/lib/l10n/translations.dart`. Access via `AppTranslations.t(key, langCode)` — chain: `_translations[langCode]?[key] ?? _translations['en']?[key] ?? key`. A missing key in the target language transparently falls back to English, and a missing key in English too surfaces the raw key name (which is the behavior a contributor sees when they add a `_t('new_key')` call without adding the key to the English block — a useful bug-finding signal).

**When adding a new string:**
1. Add it to the English block first — that's the source of truth.
2. All 11 other languages automatically English-fallback until they're retranslated; no crash.
3. A future translation pass can fill the non-English blocks, but don't block merging on it.

Translations use community-spoken vocabulary, not Sanskritic/academic medical terms (fever is `ताप` / `காய்ச்சல்` / `ജ്വരം`, not `ज्वर` / `ஜ்வரம்`). Image-capture emojis and proper nouns (`AI`, `SpO₂`, `WhatsApp`) stay in Latin/symbol form across all languages.

## Dart-file editing rules

1. **Never use `sed` on Dart files** — corrupts them. Use the Edit tool or write complete files.
2. **Always back up before large edits**: `cp file.dart file.dart.bak` (those `.bak` / `.bak2` / `.imgfix_bak` / `.v2_bak` / `.symptom_patch_bak` / `.fuzzy_bak` / `.imgclass_bak` files in `lib/` are from this practice — `.gitignore`d and safe to ignore).
3. **Symptom keys must match clinical_knowledge.dart's `symptomSystemMap`**. Before introducing a new key, either add it to `symptomSystemMap` or alias it from an existing canonical.
4. **Disease profiles must use canonical ssm keys** (no alias names). The engine matches against the raw key in the profile, not through the alias map.
5. **Complete corrected files preferred over partial edits** when refactoring.
6. **TFLite tensor shapes are not compile-time checked** — mismatched input shapes throw at runtime only. Always cross-reference the model's `*_metadata.json` in `assets/models/` before changing any `classifyImage` / `_run` preprocessing.

## Known-dead-end experiments (don't re-attempt without strong reason)

- **TTS voice narration (`flutter_tts`)** — was added, user found no value, removed. Don't re-introduce a "Read aloud" / "Listen" / "Speak result" button on the results screen.
- **On-device LLM (Gemma, MedGemma, Llama, InfiMed)** — considered during competitor analysis, deliberately skipped. 100-500 MB model size blows up the APK, licensing is thorny, and the curated 162-disease engine is more auditable than an LLM.
- **BLE mesh P2P sync, rPPG vitals from camera, cough-audio (YAMNet) classification** — all competitor features we chose to skip as out of scope. Don't add without explicit approval.
- ~~**Skin image model** — 32% accuracy, permanently removed.~~ **RE-ADDED 2026-04-19** as a below-gate model (see bundled-models table). DermNet-23 retrained into 8 clinical supergroups via `model_training/kaggle_skin_model.py`. Still below the 70% ship gate — kept behind a `skinConfidenceFloor` guard in `ml_service.dart` that degrades low-confidence predictions to a PHC-referral sentinel. **Raise the floor or retrain before broadening UI surface area.**

## Database schema (SQLite, version 2)

- `assessments` — primary table. Encrypted columns: `patient_name`, `voice_transcript`, `notes`. Plaintext: `patient_age`, `patient_gender`, `symptoms` (JSON), `vitals` (JSON), `conditions` (JSON), `overall_risk`, `next_steps` (JSON), `image_path`, `household_id`, `created_at`.
- `inventory` — medicine kit, seeded from `_seed` const in `inventory_service.dart` on first launch.
- `mch_records` — ANC + immunization schedules, with `completed` / `completed_on` columns.

Migrations are additive (`onUpgrade` adds columns; never drops). Corrupted JSON in any row is caught by `_safeDecode` and returns the fallback — never propagates.

## When a feature request arrives

1. First check if the feature has already been tried and discarded (see "Known-dead-end experiments" above and git log for `competitor-parity` commits).
2. Before implementing in Dart, run the reachability audit to confirm no existing piece is broken. It's embarrassing to ship a new feature on top of an invisible regression.
3. `flutter analyze --no-fatal-infos` from `android_app/` must show 0 errors + 0 warnings. The current baseline is 182 pre-existing `prefer_const_constructors` info hints; anything above that is new and must be reviewed.
4. `flutter build apk --debug` AND `flutter build apk --release` should both succeed locally — release catches R8 / ProGuard issues that debug misses.
5. Commits on `main` should be self-describing — the git log is the closest thing to a changelog.

## Audit baseline

The codebase has been through two rounds of parallel-subagent code audits (security, clinical, Dart correctness, ML integration, UI/a11y/i18n, build/CI). 32 real bugs were found and fixed across those rounds; the git log entries titled "Round-{1,2} audit ..." capture the rationale for each. When adding new code, assume you're being held to that same bar — the audit agents will flag things like missing `mounted` checks after `await`, silent decrypt-failure fallbacks, R8-unfriendly reflection calls, hardcoded English strings that should go through `_t()`, and patient-safety-adjacent issues like emergency-number validation gaps.
