import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class SpecialistScreening {
  final String modelName;
  final String modelKey;
  final double riskScore;
  final String riskLabel;
  final String predictedClass;
  /// Fraction of the model's expected features that were actually present
  /// in the input (0.0–1.0). Features that were missing got zero-filled,
  /// which biases numeric models toward "normal/low-risk" — UI callers
  /// should display a "partial data" indicator when this is below ~0.7
  /// and down-weight the reported risk in their decision flow.
  final double featureCoverage;

  SpecialistScreening({
    required this.modelName,
    required this.modelKey,
    required this.riskScore,
    required this.riskLabel,
    required this.predictedClass,
    required this.featureCoverage,
  });

  Map<String, dynamic> toJson() => {
    'modelName': modelName, 'modelKey': modelKey,
    'riskScore': riskScore, 'riskLabel': riskLabel,
    'predictedClass': predictedClass,
    'featureCoverage': featureCoverage,
  };
}

class _ModelDef {
  final String name, key;
  Interpreter? interpreter;
  List<String> classes = [];
  List<String> features = [];
  bool loaded = false;
  _ModelDef(this.name, this.key);
}

class SpecialistModelsService {
  static final SpecialistModelsService _instance = SpecialistModelsService._();
  factory SpecialistModelsService() => _instance;
  SpecialistModelsService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  final List<_ModelDef> _models = [
    _ModelDef('Heart Disease', 'heart_disease'),
    _ModelDef('Diabetes', 'diabetes'),
    _ModelDef('Kidney Disease', 'kidney_disease'),
    _ModelDef('Liver Disease', 'liver_disease'),
    _ModelDef('Stroke Risk', 'stroke_risk'),
    _ModelDef('Maternal Health Risk', 'maternal_risk'),
  ];

  Future<void> initialize() async {
    if (_initialized) return;
    for (final m in _models) {
      try {
        m.interpreter = await Interpreter.fromAsset('assets/models/${m.key}.tflite');
        final cj = await rootBundle.loadString('assets/models/${m.key}_classes.json');
        m.classes = List<String>.from(json.decode(cj));
        final fj = await rootBundle.loadString('assets/models/${m.key}_features.json');
        m.features = List<String>.from(json.decode(fj));
        m.loaded = true;
        print('[Specialist] Loaded ${m.name}');
      } catch (e) {
        print('[Specialist] ${m.name} not available: $e');
      }
    }
    _initialized = true;
  }

  List<String> get availableModels =>
      _models.where((m) => m.loaded).map((m) => m.name).toList();

  List<SpecialistScreening> screenAll(Map<String, dynamic> data) {
    final results = <SpecialistScreening>[];
    for (final m in _models) {
      if (!m.loaded) continue;
      final r = _run(m, data);
      if (r != null) results.add(r);
    }
    return results;
  }

  SpecialistScreening? _run(_ModelDef m, Map<String, dynamic> data) {
    // Dispose nulls out the interpreter AND flips m.loaded=false; check both
    // so a screenAll call racing with app shutdown can't hit a closed handle.
    if (m.interpreter == null || !m.loaded || !_initialized) return null;
    final nd = <String, dynamic>{};
    data.forEach((k, v) => nd[k.toLowerCase().replaceAll(' ', '_')] = v);

    int matched = 0;
    final vals = <double>[];
    for (final f in m.features) {
      final k = f.toLowerCase().replaceAll(' ', '_');
      if (nd.containsKey(k)) {
        final v = nd[k];
        if (v is num) { vals.add(v.toDouble()); matched++; }
        else if (v is String) {
          final p = double.tryParse(v);
          vals.add(p ?? _encode(v));
          matched++;
        } else { vals.add(0); }
      } else { vals.add(0); }
    }
    if (matched < m.features.length * 0.4) return null;

    try {
      final input = [vals];
      final output = List.generate(1, (_) => List<double>.filled(m.classes.length, 0.0));
      m.interpreter!.run(input, output);
      final probs = output[0];

      int bi = 0;
      for (int i = 1; i < probs.length; i++) {
        if (probs[i] > probs[bi]) bi = i;
      }

      // ── Label-aware risk scoring ──
      // Naive `probs[bi]` is wrong for 3-class models: if the top prediction is
      // "low risk" at 0.9, the score would be 0.9 and get labeled "High Risk".
      // Instead, compute risk as the total probability mass on positive/severe
      // classes, identified by label name.
      double highMass = 0.0;
      double midMass = 0.0;
      double lowMass = 0.0;
      for (int i = 0; i < m.classes.length; i++) {
        final label = m.classes[i].toLowerCase().trim();
        if (_isHighRiskLabel(label)) {
          highMass += probs[i];
        } else if (_isMidRiskLabel(label)) {
          midMass += probs[i];
        } else if (_isLowRiskLabel(label)) {
          lowMass += probs[i];
        }
      }

      double risk;
      String riskLabel;

      if (highMass + midMass + lowMass > 0.5) {
        // Labels were recognized — use weighted mass
        risk = highMass + (midMass * 0.5);
        if (highMass >= 0.5) {
          riskLabel = 'High Risk';
        } else if (highMass + midMass >= 0.5) {
          riskLabel = 'Moderate Risk';
        } else {
          riskLabel = 'Low Risk';
        }
      } else {
        // Fallback for unlabeled models — use probability of predicted class
        risk = probs[bi];
        riskLabel = risk >= 0.7
            ? 'High Risk'
            : (risk >= 0.4 ? 'Moderate Risk' : 'Low Risk');
      }

      final coverage =
          m.features.isEmpty ? 1.0 : matched / m.features.length;
      return SpecialistScreening(
        modelName: m.name,
        modelKey: m.key,
        riskScore: risk.clamp(0.0, 1.0),
        riskLabel: riskLabel,
        predictedClass: m.classes[bi].trim(),
        featureCoverage: coverage,
      );
    } catch (e) {
      print('[Specialist] ${m.name} error: $e');
      return null;
    }
  }

  /// Labels indicating no disease / negative class / safe outcome.
  /// Checked FIRST because some positive terms are substrings of negative ones
  /// (e.g., "notckd" contains "ckd"; "low risk" must not match "high" logic).
  bool _isLowRiskLabel(String l) {
    return l == '0' ||
        l == '2' ||           // liver ILPD: "2" = no disease
        l.startsWith('not') || // "notckd"
        l.contains('negative') ||
        l.contains('low');
  }

  /// Labels indicating intermediate severity.
  bool _isMidRiskLabel(String l) {
    return l.contains('mid') || l.contains('moderate');
  }

  /// Labels indicating disease / positive class / severe outcome.
  bool _isHighRiskLabel(String l) {
    if (_isLowRiskLabel(l) || _isMidRiskLabel(l)) return false;
    return l == '1' ||
        l.contains('yes') ||
        l.contains('positive') ||
        l.contains('ckd') ||  // kidney disease ("ckd", "ckd\t") — low filtered above
        l.contains('high');   // maternal "high risk"
  }

  double _encode(String v) {
    final l = v.toLowerCase().trim();
    if (l == 'yes' || l == 'true' || l == 'male') return 1;
    if (l == 'no' || l == 'false' || l == 'female') return 0;
    if (l == 'high') return 2;
    if (l == 'mid' || l == 'moderate') return 1;
    return 0;
  }

  static Map<String, dynamic> buildFromVitals({
    int? age, String? sex, String? bp,
    double? temperature, int? heartRate, int? spo2,
    double? weight, double? height,
  }) {
    final d = <String, dynamic>{};
    if (age != null) { d['age'] = age; d['Age'] = age; }
    if (sex != null) {
      d['sex'] = sex.toLowerCase() == 'm' || sex.toLowerCase() == 'male' ? 1 : 0;
      d['gender'] = d['sex'];
    }
    if (bp != null && bp.contains('/')) {
      final p = bp.split('/');
      final s = double.tryParse(p[0]); final di = double.tryParse(p[1]);
      if (s != null) { d['ap_hi'] = s; d['systolicBP'] = s; d['trestbps'] = s; }
      if (di != null) { d['ap_lo'] = di; d['diastolicBP'] = di; }
    }
    if (temperature != null) { d['BodyTemp'] = temperature; }
    if (heartRate != null) { d['HeartRate'] = heartRate; d['thalach'] = heartRate; }
    if (weight != null && height != null && height > 0) {
      final h = height / 100;
      d['bmi'] = weight / (h * h);
      d['BMI'] = d['bmi'];
    }
    return d;
  }

  void dispose() {
    for (final m in _models) {
      m.interpreter?.close();
      m.interpreter = null;
      m.loaded = false;
    }
    _initialized = false;
  }
}
