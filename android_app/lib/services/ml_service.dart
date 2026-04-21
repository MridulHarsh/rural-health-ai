// ml_service.dart (updated with specialist models + malaria)
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';

import 'clinical_engine.dart';
import 'clinical_knowledge.dart';
import 'specialist_models.dart';

class MLService {
  // ── Clinical engine (PRIMARY for symptom-based diagnosis) ──
  final ClinicalEngine _clinicalEngine = ClinicalEngine();

  // ── Specialist tabular models (NEW: heart, diabetes, kidney, etc.) ──
  final SpecialistModelsService _specialistModels = SpecialistModelsService();

  // ── Image models ──
  // Skin model re-added 2026-04-19 after DermNet → 8-clinical-supergroup
  // retraining. KNOWN TO BE BELOW THE 70% SHIP GATE — see training metadata
  // in assets/models/skin_disease_model_metadata.json for exact val_acc.
  // Callers MUST check SKIN_CONFIDENCE_FLOOR before surfacing top-1 as a
  // diagnosis; low-confidence predictions are returned with the sentinel
  // label "Low confidence — confirm at PHC".
  Interpreter? _skinModel;
  Interpreter? _eyeModel;
  Interpreter? _lungModel;
  Interpreter? _malariaModel;
  List<String>? _skinClasses;
  List<String>? _eyeClasses;
  List<String>? _lungClasses;
  List<String>? _malariaClasses;

  /// Minimum top-1 softmax probability below which we refuse to surface
  /// the skin classifier's label. The current bundled model lands at
  /// val_acc 0.407 with 6 of 8 supergroups below 50% recall (Bacterial
  /// Infection at 9% is effectively broken). With that profile, we need
  /// a stiff confidence floor to keep the UI from confidently confusing
  /// bacterial cellulitis with an autoimmune rash. Raise toward 0.70
  /// once a retrained model clears the ship gate.
  static const double skinConfidenceFloor = 0.55;
  static const String skinLowConfidenceLabel =
      'Low confidence — confirm at PHC';

  /// Per-class floor for the skin model, keyed by the exact class name from
  /// skin_disease_model_classes.json. Driven by per-class recall in the
  /// bundled model metadata: classes with recall < 0.30 are effectively
  /// pinned at 1.1 (impossible) so they can NEVER be surfaced as a
  /// confident prediction — the sentinel "confirm at PHC" label is always
  /// shown instead. Higher-recall classes use tighter-than-uniform floors
  /// scaled to their clinical-harm-on-miss (Neoplastic and Autoimmune miss
  /// a cancer / systemic disease, so they get a stiffer bar). Any class
  /// not in this map falls back to [skinConfidenceFloor].
  static const Map<String, double> skinPerClassFloor = {
    'Bacterial Infection': 1.1,      // recall 0.09 → never trust
    'Fungal Infection': 0.55,        // recall 0.60 → standard floor
    'Viral Infection': 0.70,         // recall 0.34 → stiff
    'Parasitic and Contact': 0.75,   // recall 0.24
    'Inflammatory and Eczema': 0.55, // recall 0.52 → standard
    'Allergic and Drug Reaction': 0.70, // recall 0.28
    'Neoplastic or Tumor': 0.75,     // biopsy-referral stakes on miss
    'Autoimmune or Systemic': 0.80,  // recall 0.22 + systemic miss cost
  };

  /// `true` once loaded metadata indicates the skin model bakes
  /// `mobilenet_v2.preprocess_input` into its graph, which expects raw
  /// [0, 255] pixels. In that case the Dart preprocessor's [0, 1] output
  /// must be rescaled before inference. The next-generation skin model
  /// (trained by the fixed `kaggle_skin_model.py`) will NOT bake this in
  /// and will expect [0, 1] — gating on this flag rather than `type == 'skin'`
  /// means dropping the new model into assets/ will not silently produce
  /// saturated inputs.
  bool _skinNeedsLegacyPreprocess = false;

  // ── Tabular TFLite (optional ML signal) ──
  Interpreter? _tabularModel;
  List<String>? _symptomList;
  List<String>? _diseaseList;

  bool _initialized = false;
  Future<void>? _initFuture;
  bool get isInitialized => _initialized;

  /// Idempotent + concurrency-safe init. Two parallel callers share the same
  /// Future instead of each running a full load. `_initialized` is only set
  /// to true if the primary work succeeded; image/tabular model failures
  /// are tolerated (clinical engine still works without them).
  Future<void> initialize() async {
    if (_initialized) return;
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    try {
      await _loadImageModels();

      // Load tabular model (optional — may not exist)
      try {
        _tabularModel = await Interpreter.fromAsset('assets/models/disease_model.tflite');
        // Feature / class JSON files store the raw training names (spaces,
        // mixed case). Normalize to the same canonical form the lookup path
        // uses so `indexOf(normalized)` can actually find them; without
        // this, any feature with a space in its name (283 of 328 entries in
        // disease_model_features.json) was silently unreachable — the model
        // saw all zeros for 86% of possible inputs.
        String canon(String s) =>
            s.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
        // Try old naming first
        try {
          final sj = await rootBundle.loadString('assets/models/symptom_list.json');
          _symptomList = List<String>.from(jsonDecode(sj)).map(canon).toList();
          final dj = await rootBundle.loadString('assets/models/disease_list.json');
          _diseaseList = List<String>.from(jsonDecode(dj)).map(canon).toList();
        } catch (_) {
          // Try new naming
          final sj = await rootBundle.loadString('assets/models/disease_model_features.json');
          _symptomList = List<String>.from(jsonDecode(sj)).map(canon).toList();
          final dj = await rootBundle.loadString('assets/models/disease_model_classes.json');
          _diseaseList = List<String>.from(jsonDecode(dj)).map(canon).toList();
        }
      } catch (e) {
        debugPrint('[MLService] Tabular TFLite not loaded (optional): $e');
      }

      // Load specialist tabular models
      await _specialistModels.initialize();
      debugPrint('[MLService] Specialist models: ${_specialistModels.availableModels}');

      _initialized = true;
    } catch (e) {
      debugPrint('[MLService] initialization error: $e');
      // Leave _initialized = false so callers can retry. A later call to
      // initialize() will create a fresh Future.
      _initFuture = null;
      rethrow;
    }
  }

  // ================================================================
  // PRIMARY PREDICTION — uses ClinicalEngine (UNCHANGED)
  // ================================================================

  DiagnosticResult diagnosePatient({
    required List<String> symptoms,
    int? age,
    String? sex,
    Map<String, double>? vitals,
  }) {
    Map<String, double>? mlConfidences;
    if (_tabularModel != null && _symptomList != null && _diseaseList != null) {
      mlConfidences = _getMLConfidences(symptoms);
    }

    return _clinicalEngine.diagnose(
      rawSymptoms: symptoms,
      patientAge: age,
      patientSex: sex,
      vitals: vitals,
      mlConfidences: mlConfidences,
    );
  }

  /// Minimum per-class softmax probability below which we discard the ML
  /// signal. The underlying general-disease TFLite is a 754-way MLP distilled
  /// from a 0.80-accuracy RF with MLP↔RF agreement of only 0.55 — which means
  /// the per-class tails are noisy. At a 0.05 gate (~40× the uniform prior),
  /// we were admitting dozens of low-quality "hits" that downstream boosting
  /// applied as tiebreakers. 0.20 keeps only the confident tail.
  static const double _mlConfidenceThreshold = 0.20;

  /// ML class label (post-canonicalization) → DiseaseProfile id to also boost.
  /// The general 754-class model uses verbose Kaggle labels ("dengue_fever",
  /// "chronic_obstructive_pulmonary_disease_(copd)"), while curated profile
  /// IDs are short ("dengue", "copd"). Direct-ID overlap is ~99/161; this
  /// table raises overlap to ~130/161 by aliasing the obvious pairs.
  ///
  /// Keys MUST be in canonicalized form (lowercase, whitespace→underscore,
  /// parens preserved) because `_diseaseList` entries are already
  /// canonicalized at load time.
  ///
  /// Values MUST be existing DiseaseProfile IDs — an alias to a non-existent
  /// id silently contributes no boost (harmless but wasteful).
  static const Map<String, String> _mlClassToProfileAlias = {
    'acne': 'acne_disease',
    'acute_kidney_injury': 'aki',
    'anxiety': 'anxiety_disorders',
    'benign_prostatic_hyperplasia_(bph)': 'bph',
    'carpal_tunnel_syndrome': 'carpal_tunnel',
    'cataract': 'cataract_disease',
    'chronic_obstructive_pulmonary_disease_(copd)': 'copd',
    'dengue_fever': 'dengue',
    'deep_vein_thrombosis_(dvt)': 'dvt',
    'flu': 'seasonal_flu',
    'gastroesophageal_reflux_disease_(gerd)': 'gerd',
    'glaucoma': 'glaucoma_chronic',
    'guillain_barre_syndrome': 'guillain_barre',
    'heart_attack': 'heart_attack_acute',
    'human_immunodeficiency_virus_infection_(hiv)': 'hiv',
    'hypothyroidism': 'hypothyroid',
    'infectious_gastroenteritis': 'gastroenteritis',
    'irritable_bowel_syndrome': 'ibs',
    'kidney_stone': 'kidney_stones',
    'breast_infection_(mastitis)': 'mastitis',
    'obsessive_compulsive_disorder_(ocd)': 'ocd',
    "otitis_externa_(swimmer's_ear)": 'otitis_externa',
    'acute_pancreatitis': 'pancreatitis',
    'polycystic_ovarian_syndrome_(pcos)': 'pcos',
    'peripheral_arterial_disease': 'pad',
    'pinworm_infection': 'pinworm',
    'post-traumatic_stress_disorder_(ptsd)': 'ptsd',
    'shingles_(herpes_zoster)': 'shingles',
    'obstructive_sleep_apnea_(osa)': 'sleep_apnea',
    'vaginal_yeast_infection': 'vaginal_yeast',
    'viral_warts': 'warts',
    'hypercholesterolemia': 'high_cholesterol',
    // ── Extensions (2026-04-21 accuracy pass) ─────────────────────────
    // Apostrophe-mismatch normalization — Kaggle labels use possessive
    // punctuation ("parkinson_disease"), our terse IDs use plain
    // ("parkinsons_disease"). Each extra alias reclaims ~1 DiseaseProfile
    // of ML-boost coverage.
    'parkinson_disease': 'parkinsons_disease',
    'crohn_disease': 'crohns_disease',
    // Condition-family umbrellas — multiple verbose ML classes collapse to
    // one curated profile. Preserves the strongest fused score via the
    // existing max-merge logic in `_getMLConfidences`.
    'acute_bronchitis': 'bronchitis',
    'hypertension_of_pregnancy': 'hypertension',
    'malignant_hypertension': 'hypertension',
    'gestational_diabetes': 'diabetes',
    'acute_otitis_media': 'otitis_media',
    'chronic_otitis_media': 'otitis_media',
    // Naming-convention normalization (terse profile IDs are plural/generic)
    'fungal_infection_of_the_skin': 'fungal_skin',
    'urinary_tract_infection': 'uti',
    'hyperthyroidism': 'hyperthyroid',
    'premenstrual_tension_syndrome': 'pms',
    'coronary_atherosclerosis': 'coronary_artery_disease',
  };

  /// Minimum number of recognized features in the 328-dim input vector below
  /// which we skip ML inference entirely. At 1–2 features set the model's
  /// argmax is basically the class popularity prior (1/754 ≈ 0.0013 uniform),
  /// which gets amplified by the downstream boost and introduces noise
  /// without adding signal. Three features gives enough disambiguation
  /// content for the trained classifier to produce meaningful logits.
  static const int _minMLFeatures = 3;

  /// Top-1 confidence floor — if the strongest *fused* class falls under this,
  /// the model has nothing to say and we return null (no boosts applied to any
  /// profile). Prevents garbage-in-garbage-out from e.g. an adversarial single
  /// symptom input.
  static const double _minTop1Confidence = 0.20;

  Map<String, double>? _getMLConfidences(List<String> symptoms) {
    if (_tabularModel == null || _symptomList == null || _diseaseList == null) return null;
    try {
      final input = List<double>.filled(_symptomList!.length, 0.0);
      int setCount = 0;
      for (final symptom in symptoms) {
        final normalized = symptom.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
        final idx = _symptomList!.indexOf(normalized);
        if (idx >= 0 && input[idx] == 0.0) {
          input[idx] = 1.0;
          setCount++;
        }
      }
      if (setCount < _minMLFeatures) return null;

      // Model may have batch_size > 1; allocate matching shape. For the
      // bundled 754-class model the shape is [2, 754] — the export packs the
      // MLP logits in row 0 and the RF probability estimates in row 1.
      final outputShape = _tabularModel!.getOutputTensor(0).shape;
      final batchSize = outputShape[0];
      final numClasses = outputShape[1];
      final output = List.generate(batchSize, (_) => List<double>.filled(numClasses, 0.0));
      // tflite_flutter accepts nested List<List<double>> for float32 input
      // tensors and does the cast internally. The previous implementation
      // used `Float64List.fromList(input).buffer.asFloat32List()`, which
      // reinterprets the raw 8-byte doubles as pairs of 4-byte floats —
      // producing a tensor TWICE the expected length filled with garbage
      // bit-patterns. The model saw random input on every inference.
      _tabularModel!.run([input], output);

      // Fuse MLP (row 0) and RF (row 1) when both are present. The geometric
      // mean rewards agreement (high only when BOTH rows are high) and zeros
      // out when either row is zero — this is precisely what we want given
      // the 0.55 published MLP↔RF agreement: most disagreements indicate
      // model uncertainty and should be discarded. An agreement scalar then
      // reweights the fused probability based on row similarity (1.0 when
      // mlp==rf, 0.5 when maximally split).
      final useFusion = output.length >= 2;
      final mlpProbs = output[0];
      final rfProbs = useFusion ? output[1] : null;
      final len = mlpProbs.length < _diseaseList!.length
          ? mlpProbs.length
          : _diseaseList!.length;

      // First pass: compute fused per-class scores, then find the top-1 so we
      // can apply the all-or-nothing sanity gate before emitting anything.
      final fused = List<double>.filled(len, 0.0);
      double topFused = 0.0;
      for (int i = 0; i < len; i++) {
        final mlp = mlpProbs[i].clamp(0.0, 1.0).toDouble();
        if (useFusion) {
          final rf = rfProbs![i].clamp(0.0, 1.0).toDouble();
          final geo = math.sqrt(mlp * rf);
          if (geo <= 0.0) continue;
          final mx = math.max(mlp, rf);
          final agree = mx > 0 ? math.min(mlp, rf) / mx : 0.0;
          // Agreement scalar lives in [0.5, 1.0]: 0.5 when a row is zero,
          // 1.0 when rows match exactly. Pure fused * (0.5 + 0.5*agree)
          // keeps the geometric mean as the floor and only bumps it up to
          // the fused value when both rows agree.
          fused[i] = geo * (0.5 + 0.5 * agree);
        } else {
          fused[i] = mlp;
        }
        if (fused[i] > topFused) topFused = fused[i];
      }

      // If the strongest fused class is below the sanity floor, the model has
      // nothing confident to contribute — skip boosting all profiles. This
      // prevents a low-quality prediction from applying 1.02× boosts across
      // the board, which is noise dressed as signal.
      if (topFused < _minTop1Confidence) return null;

      final confidences = <String, double>{};
      for (int i = 0; i < len; i++) {
        final prob = fused[i];
        if (prob < _mlConfidenceThreshold) continue;
        // _diseaseList is already canonicalized at load time.
        final mlKey = _diseaseList![i];
        confidences[mlKey] = prob;
        // Also record under the aliased profile id, preserving the max if
        // multiple ML classes map to the same profile (e.g. malignant_
        // hypertension + hypertension_of_pregnancy both alias to
        // `hypertension`).
        final profileId = _mlClassToProfileAlias[mlKey];
        if (profileId != null) {
          final existing = confidences[profileId];
          if (existing == null || prob > existing) {
            confidences[profileId] = prob;
          }
        }
      }
      return confidences;
    } catch (e) {
      debugPrint('[MLService] ML confidence extraction failed: $e');
      return null;
    }
  }

  // ================================================================
  // SPECIALIST SCREENINGS (NEW)
  // ================================================================

  /// Run specialist screenings using patient vitals/demographics.
  List<SpecialistScreening> runSpecialistScreenings({
    int? age,
    String? sex,
    String? bloodPressure,
    double? temperature,
    int? heartRate,
    int? spo2,
    double? weight,
    double? height,
  }) {
    if (!_specialistModels.isInitialized) return [];
    final data = SpecialistModelsService.buildFromVitals(
      age: age, sex: sex, bp: bloodPressure,
      temperature: temperature, heartRate: heartRate,
      spo2: spo2, weight: weight, height: height,
    );
    return _specialistModels.screenAll(data);
  }

  // ================================================================
  // IMAGE CLASSIFICATION (updated + malaria)
  // ================================================================

  Future<void> _loadImageModels() async {
    try {
      _skinModel = await Interpreter.fromAsset(
        'assets/models/skin_disease_model.tflite',
      );
      final sj = await rootBundle.loadString(
        'assets/models/skin_disease_model_classes.json',
      );
      _skinClasses = List<String>.from(jsonDecode(sj));

      // Read input normalization convention from metadata. The current
      // bundled model has `preprocess_input` baked into the graph, so the
      // Dart side must rescale [0, 1] → [0, 255]. A retrained model that
      // drops preprocess_input will report a different convention (e.g.
      // "img/255.0 normalized [0,1]") and this flag will flip to false
      // — no code change required on upgrade. Tolerates a missing
      // metadata file to stay backwards-compatible.
      try {
        final metaJson = await rootBundle.loadString(
          'assets/models/skin_disease_model_metadata.json',
        );
        final meta = jsonDecode(metaJson) as Map<String, dynamic>;
        final norm = (meta['input_normalization'] as String? ?? '')
            .toLowerCase();
        _skinNeedsLegacyPreprocess =
            norm.contains('preprocess_input') || norm.contains('[-1, 1]');
      } catch (e) {
        // If metadata is missing, assume the legacy convention — the
        // current bundled model does bake preprocess_input, so the
        // safer default is to keep the stopgap enabled.
        _skinNeedsLegacyPreprocess = true;
        debugPrint('[MLService] Skin metadata missing, keeping legacy preprocess: $e');
      }

      debugPrint(
        '[MLService] Skin model loaded: ${_skinClasses!.length} classes '
        '(below-gate model — confidence floor $skinConfidenceFloor, '
        'legacyPreprocess=$_skinNeedsLegacyPreprocess)',
      );
    } catch (e) {
      debugPrint('[MLService] Skin model load error: $e');
    }

    try {
      _eyeModel = await Interpreter.fromAsset('assets/models/eye_disease_model.tflite');
      final eyeJson = await rootBundle.loadString('assets/models/eye_disease_model_classes.json');
      _eyeClasses = List<String>.from(jsonDecode(eyeJson));
      debugPrint('[MLService] Eye model loaded: ${_eyeClasses!.length} classes');
    } catch (e) {
      debugPrint('[MLService] Eye model load error: $e');
    }

    try {
      _lungModel = await Interpreter.fromAsset('assets/models/lung_disease_model.tflite');
      final lungJson = await rootBundle.loadString('assets/models/lung_disease_model_classes.json');
      _lungClasses = List<String>.from(jsonDecode(lungJson));
      debugPrint('[MLService] Lung model loaded: ${_lungClasses!.length} classes');
    } catch (e) {
      debugPrint('[MLService] Lung model load error: $e');
    }

    try {
      _malariaModel = await Interpreter.fromAsset('assets/models/malaria_model.tflite');
      final mj = await rootBundle.loadString('assets/models/malaria_model_classes.json');
      _malariaClasses = List<String>.from(jsonDecode(mj));
      debugPrint('[MLService] Malaria model loaded: ${_malariaClasses!.length} classes');
    } catch (e) {
      debugPrint('[MLService] Malaria model load error: $e');
    }
  }

  /// Classify an image. [type]: 'skin', 'eye', 'lung', 'malaria'.
  ///
  /// For [type] == 'skin', the model is known to be below the 70% ship gate.
  /// If the top-1 softmax probability is below [skinConfidenceFloor], the
  /// returned list starts with [skinLowConfidenceLabel] (prob = top-1) so
  /// the UI can show a "preliminary — confirm at PHC" warning instead of
  /// treating the label as a diagnosis. The original top-3 still follows.
  Future<List<MapEntry<String, double>>> classifyImage({
    required List<List<List<double>>> imageData,
    required String type,
  }) async {
    Interpreter? model;
    List<String>? classes;

    switch (type) {
      case 'skin':
        model = _skinModel;
        classes = _skinClasses;
        break;
      case 'eye':
        model = _eyeModel;
        classes = _eyeClasses;
        break;
      case 'lung':
        model = _lungModel;
        classes = _lungClasses;
        break;
      case 'malaria':
        model = _malariaModel;
        classes = _malariaClasses;
        break;
    }

    if (model == null || classes == null) {
      return [MapEntry('Model not available', 0.0)];
    }

    try {
      // IMPORTANT: tflite_flutter's copyTo() does a SHALLOW replacement
      // (dst[i] = obj[i]), so the outer list must be held in a named variable.
      // If we write `model.run(..., [output])` inline, the replaced inner list
      // is written into a temporary that's discarded — and `output` stays 0.0.
      // The pattern below mirrors specialist_models.dart which works correctly.
      final output = List.generate(
        1,
        (_) => List<double>.filled(classes!.length, 0.0),
      );

      // Skin model preprocessing-range stopgap — gated on model metadata,
      // not on `type == 'skin'`. See `_skinNeedsLegacyPreprocess` load path.
      final needsLegacy = type == 'skin' && _skinNeedsLegacyPreprocess;
      final input = needsLegacy
          ? imageData
              .map((row) => row
                  .map((px) => px.map((c) => c * 255.0).toList())
                  .toList())
              .toList()
          : imageData;

      model.run([input], output);
      final probs = output[0];

      // Merge duplicate/variant class labels coming from noisy training data.
      // The lung model was trained on a dataset where "NORMAL"/"Normal" and
      // "TURBERCULOSIS"/"Tuberculosis" ended up as separate label folders —
      // which splits their probability mass. We sum the mass under a canonical
      // display name before ranking. "TURBERCULOSIS" is also a misspelling
      // of Tuberculosis; we canonicalize here so users don't see the typo.
      final merged = <String, double>{};
      for (int i = 0; i < classes.length; i++) {
        final canonical = _canonicalizeImageClass(classes[i]);
        merged[canonical] = (merged[canonical] ?? 0.0) + probs[i];
      }

      final results = merged.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      // Below-gate mitigation: prepend a low-confidence marker for skin
      // predictions that fall under the floor. Per-class floor table
      // (skinPerClassFloor) is consulted first so clinically-catastrophic
      // misses (Bacterial recall 0.09, Autoimmune recall 0.22) pin the
      // floor at a value the model can never clear — guaranteeing the
      // PHC-referral sentinel on those classes regardless of top-1 prob.
      if (type == 'skin' && results.isNotEmpty) {
        final topLabel = results.first.key;
        final topProb = results.first.value;
        final floor = skinPerClassFloor[topLabel] ?? skinConfidenceFloor;
        if (topProb < floor) {
          return [
            MapEntry(skinLowConfidenceLabel, topProb),
            ...results.take(3),
          ];
        }
      }

      return results.take(3).toList();
    } catch (e) {
      debugPrint('[MLService] classifyImage error: $e');
      return [MapEntry('Classification error: $e', 0.0)];
    }
  }

  /// Canonicalize image-model class labels so downstream display and disease
  /// lookup see a single name per condition. Fixes training-data artifacts
  /// like case-duplicates (NORMAL vs Normal) and the "TURBERCULOSIS" typo.
  String _canonicalizeImageClass(String raw) {
    final lower = raw.toLowerCase().trim();
    // Lung model
    if (lower == 'normal') return 'Normal';
    if (lower == 'pneumonia') return 'Pneumonia';
    if (lower == 'tuberculosis' || lower == 'turberculosis') return 'Tuberculosis';
    if (lower == 'covid19' || lower == 'covid-19' || lower == 'covid_19') return 'COVID-19';
    // Eye model
    if (lower == 'cataract') return 'Cataract';
    if (lower == 'diabetic_retinopathy') return 'Diabetic Retinopathy';
    if (lower == 'glaucoma') return 'Glaucoma';
    // Malaria model
    if (lower == 'parasitized') return 'Parasitized (malaria detected)';
    if (lower == 'uninfected') return 'Uninfected';
    return raw;
  }

  // ================================================================
  // VOICE SYMPTOM EXTRACTION (UNCHANGED)
  // ================================================================

  List<String> extractSymptomsFromVoice(String transcript) {
    final words = transcript
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'));

    final found = <String>{};

    void tryAdd(String key) {
      if (symptomAliases.containsKey(key)) {
        found.add(_resolveAliasChain(key));
      } else if (symptomSystemMap.containsKey(key)) {
        found.add(key);
      }
    }

    for (final word in words) {
      tryAdd(word);
    }
    for (int i = 0; i < words.length - 1; i++) {
      tryAdd('${words[i]}_${words[i + 1]}');
    }
    for (int i = 0; i < words.length - 2; i++) {
      tryAdd('${words[i]}_${words[i + 1]}_${words[i + 2]}');
    }

    return found.toList();
  }

  /// Follow an alias chain until terminal. Cycle-safe.
  String _resolveAliasChain(String key) {
    String current = key;
    final seen = <String>{};
    while (symptomAliases.containsKey(current) && !seen.contains(current)) {
      seen.add(current);
      final next = symptomAliases[current]!;
      if (next == current) break;
      current = next;
    }
    return current;
  }

  void dispose() {
    _tabularModel?.close();
    _skinModel?.close();
    _eyeModel?.close();
    _lungModel?.close();
    _malariaModel?.close();
    _tabularModel = null;
    _skinModel = null;
    _eyeModel = null;
    _lungModel = null;
    _malariaModel = null;
    _specialistModels.dispose();
  }
}
