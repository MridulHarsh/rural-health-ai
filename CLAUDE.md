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

### Reachability-audit regex gotcha

A single-pass regex like `^\s*'([a-z_]+)':\s*\{BodySystem` silently misses ~295 SSM keys because `symptomSystemMap` entries span multiple lines — the `{BodySystem...}` weight map typically opens on the line *after* the key. **Always extract the `symptomSystemMap = { ... };` block first, then parse `^\s*'([a-z_]+)'\s*:` from the block body.** The same multi-line trap applies to `symptomAliases`. A broken audit will report false "orphan symptom" / "dead chip" findings and waste a review pass chasing ghosts.

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
                                             by matching ID. Never adds new candidates. Max
                                             boost is 1.25× (coefficient 0.25) because the
                                             underlying MLP↔RF agreement is 0.55 — a confident
                                             logit should tiebreak, not override clinical
                                             reasoning.

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
- **Age-based escalation** (`clinical_engine.dart` ~L590): patients with `age < 5 || age > 65` get `normal → moderate` unconditionally and `moderate → urgent` when `cardinalCoverage >= 0.25`. Lowered from 0.3 to 0.25 so that a single-cardinal match on a 4-cardinal febrile profile (coverage = 0.25 exactly) still escalates for vulnerable ages. A dedicated `rf_sepsis` rule (fever + ≥2 of altered_consciousness/palpitations/low_bp/pallor/cyanosis/lethargy/severe_sob) now backstops this — the age escalation is still kept as a belt-and-braces fallback.
- **Unknown-symptom tokens**: `_normalizeSymptoms` drops (not keeps) tokens that don't resolve via alias map, `symptomSystemMap`, or fuzzy match. Disease profiles use canonical SSM keys only, so unknowns inflate `totalMatched` counts nowhere and used to leak garbage into reasoning strings — the fallback-keep branch was removed in the accuracy-tuning pass.
- **Fuzzy matching** (both `clinical_engine._fuzzyMatchSymptom` and `fuzzy_symptom_matcher._fuzzyMatch`):
  - Substring-contains in the engine requires both sides ≥ 4 chars.
  - Voice matcher uses max edit distance 2 (was 3), minimum token length 5 for Latin scripts (was 3), 3 for Indic. This closes the "feed→fever", "dough→cough", "fewer→fever" false-positive path without breaking native-script voice input (which flows through the alias map first anyway).
- **Fever expansion**: the engine auto-adds `fever`/`mild_fever` when any fever variant is present. Also injects `fever`/`high_fever` from vitals when temperature ≥ 100.4°F / ≥ 104°F. If the user wants to report fever without a thermometer reading, there ARE chips (`fever`, `high_fever`, `mild_fever`) in the General category — do not "fix" this by removing them. **All temperature thresholds in this codebase are Fahrenheit** — if a Celsius input path is ever added, auto-convert before the fever check.
- **Pediatric dosing daily cap** (`dosage_screen.dart` `_DrugRule.dose()`): every rule has both `maxMgPerDose` AND `maxMgPerDay`. The compute path clamps by per-dose first, then reduces the dose if `mg * dosesPerDay > maxMgPerDay`. Paracetamol is set to 3000 mg/day (WHO/NICE pediatric cap — prevents hepatotoxicity on the 4-dose 3-day course for 35+ kg children). Never add a new drug rule without setting both caps.

### Prevalence calibration (India-specific sources)

`DiseaseProfile.prevalence` (0.0–1.0) contributes 15% of the scoring weight and directly shapes ranking ties. Always calibrate against an India-specific source and cite it in an inline comment on the profile:

- **NFHS-5** (National Family Health Survey, 2019–21) — anemia (57% women 15–49), childhood stunting (35.5% <5), diabetes self-reported rates, contraceptive use, immunization coverage
- **ICMR** — enteric fever (typhoid/paratyphoid) incidence studies, NCD surveillance
- **WHO / MOHFW** — TB burden (India ≈ 2.6M cases/year, ~26% of global load), malaria seasonal maps, leprosy, neglected tropical diseases
- **ClinicalTrials.gov / published cohorts** — chronic disease incidence (CAD, CKD, COPD)

Global prevalence numbers (US CDC, WHO global averages) routinely undersell conditions that are endemic in rural India — anemia and TB are the most notorious. Cite the source inline so the next editor can validate rather than second-guess.

### Service layer (lib/services/)

| File | Role |
|---|---|
| `clinical_knowledge.dart` | Data: 162 `DiseaseProfile`s, 16 `RedFlagRule`s (rf_sepsis + rf_severe_malaria + rf_postpartum_hemorrhage + rf_hypoglycemia + rf_suicidal_ideation added in accuracy pass), 295 `symptomSystemMap` keys, 642 `symptomAliases` pairs |
| `clinical_engine.dart` | 5-step diagnostic pipeline. `_normalizeSymptoms` does alias-chain resolution + fuzzy match (unknown tokens dropped, not retained). ML boost is capped at 1.25× (0.25 coefficient). |
| `ml_service.dart` | Orchestrates ClinicalEngine + tabular ML + image classification. Class is `MLService` (uppercase). The 754-class general classifier maps to 99 DiseaseProfile IDs directly + 33 via `_mlClassToProfileAlias` (dengue↔dengue_fever, copd↔…, hiv↔…, etc.) for a total ML→profile overlap of ~132/162. Raw ML input flows through `List<List<double>>` to `Interpreter.run()`; **never** `.buffer.asFloat32List()` on a Float64List — that byte-reinterprets doubles into 2× garbage floats. |
| `specialist_models.dart` | Singleton loading 6 tabular TFLite models. `buildFromVitals()` maps captured vitals into each model's feature space. Derived fields: `hypertension` (1 if systolic≥140 OR diastolic≥90), `heart_disease` (default 0 = no known history, overridable via param), `bp` = systolic (kidney feature alias). Risk scoring is **label-aware** (see note below). `SpecialistScreening.featureCoverage` (0.0–1.0) reports real-vs-zero-filled feature ratio; results screen hides <0.4, shows "Partial data X%" amber chip at 0.4–0.7. Feature key matching uses `_canonicalKey` = `toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_')` — **all whitespace including NBSP (U+00A0)**, not just ASCII space (three liver features had an invisible NBSP prefix and were silently unreachable). |
| `fuzzy_symptom_matcher.dart` | Voice-input matcher: substring + Levenshtein, max edit distance **2** (tightened from 3), min token length **5 for Latin / 3 for Indic**. Flattens alias chains at lookup-table build time. |
| `database_service.dart` | SQLite (schema v3). PII columns (`patient_name`, `voice_transcript`, `notes`, `abha_id`, `abha_address`) are AES-GCM encrypted via `EncryptionService`. `household_id` groups family members for contagion view. Schema v3 also adds the `followup_outcomes` table (outcome tracking, feature #3). **All PII reads go through `_safeDecrypt`** (try/catch wrapper) — a single corrupt envelope must not crash the entire history retrieval; same resilience pattern as `_safeDecode` for JSON columns. |
| `encryption_service.dart` | AES-256-GCM. Key stored in `flutter_secure_storage` (Android Keystore / iOS Keychain). `encryptString` / `decryptString` produce/consume `iv_b64|ct_b64` envelopes |
| `handoff_service.dart` | WhatsApp (native scheme then wa.me fallback), SMS draft, tel dialer. **Do NOT use `canLaunchUrl` pre-check** — Android 11+ returns false for undeclared packages even when installed. `_sanitizePhone` rejects garbage input outside 7–15 digits, but `_emergencyShortCodes` (100/101/102/104/108/112/1098) bypass the length minimum — never remove that allowlist or `dial('108')` silently returns false. |
| `emergency_service.dart` | Vibration-pattern alarm on red-flag triage |
| `outbreak_detector.dart` | 7-day cluster scan over saved assessments; flags repeated top-condition or high-signal symptoms |
| `ocr_service.dart` | Google ML Kit offline text recognition for scanning prescriptions |
| `inventory_service.dart` | ASHA medicine-kit SQLite table, seeded with WHO essential list on first launch |
| `mch_service.dart` | Maternal & Child Health: Naegele EDD, 4-visit ANC schedule, full UIP immunization schedule |
| `pdf_service.dart` | Patient-summary PDF via `pdf` + `printing`. Class `PdfExportService`, method `printSummary` |
| `fhir_service.dart` | Builds FHIR R4 Bundle (Composition + Patient w/ ABHA identifier + LOINC Observations + Condition + ClinicalImpression) from an `AssessmentResult`. Deterministic v5 UUIDs seeded off `patient.id`; SHA-256 of canonical JSON is the provenance hash. No FHIR SDK dependency — handwritten builder keeps APK lean. |
| `outcome_service.dart` | CRUD for `followup_outcomes`. PII columns encrypted via `EncryptionService`; enums/flags plaintext. `isFollowupDue()` drives the amber history badge (7-day ASHA cadence). |
| `analytics_exporter.dart` | Append-only JSONL of de-identified (assessment, outcome) pairs to app Documents. Gated by per-encounter `FollowupOutcome.consentToShare`. Never emits name / ABHA / free text / raw vital values — only age bucket, ISO-week, canonical condition IDs, adherence/outcome enums, and a truncated encounter hash. Bumps `schemaVersion` for non-additive shape changes. |

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

## buildFromVitals: the "observable-only" rule

`SpecialistModelsService.buildFromVitals()` synthesizes feature-space inputs ONLY from data an ASHA worker can actually observe or measure: age/sex, BP cuff reading, thermometer, pulse oximeter, weight/height, and explicit yes/no history flags (`knownHeartDisease`). Derived fields are honest when they come from real measurements — `hypertension = 1` if systolic≥140 OR diastolic≥90 is fine because the BP reading was captured.

**Never default lab values** (cholesterol, HbA1c, fasting glucose, average glucose, serum creatinine, bilirubin, urinalysis, albumin). A population-mean default silently biases every patient toward "normal" — the model sees a plausible-looking vector and emits confident low-risk predictions for people who actually have untested disease. Heart (13 features, mostly labs) and Liver (9 features, mostly labs) SHOULD silently fail the 0.4 `featureCoverage` gate on pure ASHA data; the results screen already hides sub-0.4 cards and renders a "Partial data" amber chip between 0.4–0.7. That's the honest behavior. If a future clinic-integration path feeds real labs in, extend `buildFromVitals` to accept them as optional params — don't backfill synthetic values.

## Adding a DiseaseProfile? Check `disease_list.json` for an ML twin

The 754-class general classifier uses verbose Kaggle labels (`dengue_fever`, `chronic_obstructive_pulmonary_disease_(copd)`, `obsessive_compulsive_disorder_(ocd)`) while curated `DiseaseProfile` IDs are terse (`dengue`, `copd`, `ocd`). Direct ID match is 99/162; the remaining 33 come from hand-curated entries in `_mlClassToProfileAlias` in `ml_service.dart`.

**Before adding a new `DiseaseProfile`**: grep `android_app/assets/models/disease_list.json` for near-matches by the human-disease name. If a verbose ML class exists for the same condition, add a `_mlClassToProfileAlias` entry so the general classifier can upweight your new profile. Without the alias, the ML boost silently misses — the profile is reachable only through pure clinical-engine scoring and never benefits from the 754-class model's agreement signal.

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
4. **`android:usesCleartextTraffic="false"`** + `android:networkSecurityConfig="@xml/network_security_config"` on `<application>`. The config file trusts system CAs only and blocks plaintext HTTP app-wide. If a future debug build needs an `http://` endpoint, add a per-build override (don't flip the global flag) — the whole point is to make it impossible to accidentally ship a cleartext path.

## Anti-screenshot (FLAG_SECURE)

`android/app/src/main/kotlin/com/ruralhealth/rural_health_ai/MainActivity.kt` sets `WindowManager.LayoutParams.FLAG_SECURE` in `onCreate` — blocks screenshots and the recents-thumbnail leak of patient data. The flag is gated to release builds via `(applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0` so Flutter's hot-reload developer screenshots still work. **Do NOT switch the gate to `BuildConfig.DEBUG`** — that symbol requires enabling `buildFeatures.buildConfig` in `android/app/build.gradle.kts` and was deliberately avoided.

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
7. **`uuid` package is 4.x**: `Uuid.NAMESPACE_URL` is deprecated — use `Namespace.url.value` (from `package:uuid/uuid.dart`) for v5 namespace UUIDs.
8. **The `flutter-analyze` PostToolUse hook treats warnings as blocking**, not just errors. Splitting "add import" and "first use" across two Edits fails on `unused_import` / `unused_field`. Either stage both into one Edit, or add the consumer first.

## Known-dead-end experiments (don't re-attempt without strong reason)

- **TTS voice narration (`flutter_tts`)** — was added, user found no value, removed. Don't re-introduce a "Read aloud" / "Listen" / "Speak result" button on the results screen.
- **On-device LLM (Gemma, MedGemma, Llama, InfiMed)** — considered during competitor analysis, deliberately skipped. 100-500 MB model size blows up the APK, licensing is thorny, and the curated 162-disease engine is more auditable than an LLM.
- **BLE mesh P2P sync, rPPG vitals from camera, cough-audio (YAMNet) classification** — all competitor features we chose to skip as out of scope. Don't add without explicit approval.
- ~~**Skin image model** — 32% accuracy, permanently removed.~~ **RE-ADDED 2026-04-19** as a below-gate model (see bundled-models table). DermNet-23 retrained into 8 clinical supergroups via `model_training/kaggle_skin_model.py`. Still below the 70% ship gate — kept behind a `skinConfidenceFloor` guard in `ml_service.dart` that degrades low-confidence predictions to a PHC-referral sentinel. **Raise the floor or retrain before broadening UI surface area.**

## New deps (feature #1/#3, 2026-04-21)

- `crypto ^3.0.3` — SHA-256 for FHIR provenance and encounter-hash de-identification.
- `share_plus ^10.0.0` — native share sheet for FHIR bundle and analytics JSONL attachments. Pure MethodChannel, no ProGuard rules needed.

## Database schema (SQLite, version 3)

- `assessments` — primary table. Encrypted columns: `patient_name`, `voice_transcript`, `notes`, `abha_id`, `abha_address`. Plaintext: `patient_age`, `patient_gender`, `symptoms` (JSON), `vitals` (JSON), `conditions` (JSON), `overall_risk`, `next_steps` (JSON), `image_path`, `household_id`, `created_at`.
- `followup_outcomes` — opt-in outcome tracking (feature #3). Encrypted: `actual_diagnosis`, `treatment_given`, `notes`. Plaintext (so `AnalyticsExporter` can aggregate without the AES key): `adherence`, `outcome_status`, `consent_to_share`, `followup_date`, `created_at`. FK → `assessments.id` with `ON DELETE CASCADE`.
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
