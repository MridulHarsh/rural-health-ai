// ml_service.dart (updated with specialist models + malaria)
import 'dart:typed_data';
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
        // Try old naming first
        try {
          final sj = await rootBundle.loadString('assets/models/symptom_list.json');
          _symptomList = List<String>.from(jsonDecode(sj));
          final dj = await rootBundle.loadString('assets/models/disease_list.json');
          _diseaseList = List<String>.from(jsonDecode(dj));
        } catch (_) {
          // Try new naming
          final sj = await rootBundle.loadString('assets/models/disease_model_features.json');
          _symptomList = List<String>.from(jsonDecode(sj));
          final dj = await rootBundle.loadString('assets/models/disease_model_classes.json');
          _diseaseList = List<String>.from(jsonDecode(dj));
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

  Map<String, double>? _getMLConfidences(List<String> symptoms) {
    if (_tabularModel == null || _symptomList == null || _diseaseList == null) return null;
    try {
      final input = List<double>.filled(_symptomList!.length, 0.0);
      for (final symptom in symptoms) {
        final normalized = symptom.toLowerCase().replaceAll(' ', '_');
        final idx = _symptomList!.indexOf(normalized);
        if (idx >= 0) input[idx] = 1.0;
      }
      // Model may have batch_size > 1; allocate matching shape
      final outputShape = _tabularModel!.getOutputTensor(0).shape;
      final batchSize = outputShape[0];
      final numClasses = outputShape[1];
      final output = List.generate(batchSize, (_) => List<double>.filled(numClasses, 0.0));
      _tabularModel!.run(
        [Float64List.fromList(input).buffer.asFloat32List()],
        output,
      );
      final flatOutput = output[0]; // Use first batch element
      final confidences = <String, double>{};
      // Defensive: model output width and disease-list length should match,
      // but a mismatched asset shouldn't crash inference — iterate to the
      // shorter of the two.
      final len = flatOutput.length < _diseaseList!.length
          ? flatOutput.length
          : _diseaseList!.length;
      for (int i = 0; i < len; i++) {
        if (flatOutput[i] > 0.05) {
          confidences[_diseaseList![i].toLowerCase().replaceAll(' ', '_')] =
              flatOutput[i];
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
      debugPrint(
        '[MLService] Skin model loaded: ${_skinClasses!.length} classes '
        '(below-gate model — confidence floor $skinConfidenceFloor)',
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

      // Skin model preprocessing-range stopgap.
      //
      // eye/lung/malaria models were trained by train_images.py which feeds
      // [0, 1]-normalized pixels (img/255.0). The current skin model was
      // trained with mobilenet_v2.preprocess_input baked into the graph,
      // which maps [0, 255] → [-1, 1] via true_divide(127.5)→subtract(1).
      // Feeding [0, 1] inputs to it collapses every pixel near -1 and the
      // model predicts noise.
      //
      // Stopgap: scale [0, 1] → [0, 255] before inference, so the baked-in
      // preprocess_input receives what it expects. Cost is one pass of ~49k
      // float multiplications (sub-millisecond). Next retrain should drop
      // preprocess_input from the graph to match train_images.py's
      // convention; when that lands, delete this branch.
      final input = type == 'skin'
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
      // predictions that fall under the floor. UI should display this
      // sentinel as a "preliminary — confirm at PHC" banner and still
      // allow the user to see the ranked alternatives beneath it.
      if (type == 'skin' &&
          results.isNotEmpty &&
          results.first.value < skinConfidenceFloor) {
        return [
          MapEntry(skinLowConfidenceLabel, results.first.value),
          ...results.take(3),
        ];
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
    _eyeModel?.close();
    _lungModel?.close();
    _malariaModel?.close();
    _tabularModel = null;
    _eyeModel = null;
    _lungModel = null;
    _malariaModel = null;
    _specialistModels.dispose();
  }
}
