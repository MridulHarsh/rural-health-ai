import '../services/specialist_models.dart';
import 'dart:convert';

/// Patient demographics
class Patient {
  final String id;
  final String name;
  final int age;
  final String gender;
  final DateTime createdAt;
  /// Household identifier — groups family members for cluster/contagion view.
  /// A free-form string (e.g., village + head-of-household name + phone suffix).
  final String? householdId;
  /// 14-digit ABHA ID (Ayushman Bharat Health Account). Optional — many rural
  /// patients don't have one. When present, it's embedded as the Patient
  /// resource identifier in the FHIR bundle exported to ABDM-compliant
  /// endpoints.
  final String? abhaId;
  /// ABHA Address (format: username@hiu). Human-readable alternative to the
  /// numeric ABHA ID. Either one is enough for ABDM handoff.
  final String? abhaAddress;

  Patient({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    DateTime? createdAt,
    this.householdId,
    this.abhaId,
    this.abhaAddress,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'createdAt': createdAt.toIso8601String(),
        'householdId': householdId,
        'abhaId': abhaId,
        'abhaAddress': abhaAddress,
      };

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'],
        name: json['name'],
        age: json['age'],
        gender: json['gender'],
        createdAt: DateTime.parse(json['createdAt']),
        householdId: json['householdId'] as String?,
        abhaId: json['abhaId'] as String?,
        abhaAddress: json['abhaAddress'] as String?,
      );
}

/// Risk level — now includes 'moderate' between urgent and normal.
enum RiskLevel {
  emergency,
  urgent,
  moderate,
  normal,
}

/// Vital signs
class Vitals {
  final double? temperature;
  final String? bloodPressure;
  final int? heartRate;
  final int? spo2;
  final double? weight;
  final double? height;

  Vitals({
    this.temperature,
    this.bloodPressure,
    this.heartRate,
    this.spo2,
    this.weight,
    this.height,
  });

  /// Convert vitals to the `Map<String, double>` format the clinical engine expects.
  Map<String, double> toEngineMap() {
    final map = <String, double>{};
    if (temperature != null) map['temperature'] = temperature!;
    if (heartRate != null) map['heart_rate'] = heartRate!.toDouble();
    if (spo2 != null) map['spo2'] = spo2!.toDouble();

    // Parse BP string like "120/80" into systolic/diastolic
    if (bloodPressure != null && bloodPressure!.contains('/')) {
      final parts = bloodPressure!.split('/');
      final sys = double.tryParse(parts[0].trim());
      final dia = double.tryParse(parts[1].trim());
      if (sys != null) map['bp_systolic'] = sys;
      if (dia != null) map['bp_diastolic'] = dia;
    }

    return map;
  }

  Map<String, dynamic> toJson() => {
        'temperature': temperature,
        'bloodPressure': bloodPressure,
        'heartRate': heartRate,
        'spo2': spo2,
        'weight': weight,
        'height': height,
      };

  factory Vitals.fromJson(Map<String, dynamic> json) => Vitals(
        temperature: json['temperature']?.toDouble(),
        bloodPressure: json['bloodPressure'],
        heartRate: json['heartRate']?.toInt(),
        spo2: json['spo2']?.toInt(),
        weight: json['weight']?.toDouble(),
        height: json['height']?.toDouble(),
      );
}

/// A predicted condition with confidence and clinical reasoning.
class PredictedCondition {
  /// Canonical DiseaseProfile ID (e.g. `dengue`, `copd`). Required for
  /// FHIR Condition resource coding and for de-identified analytics export —
  /// the display name is localized/humanized and unsuitable for either.
  final String canonicalId;
  final String name;
  final double confidence;
  final RiskLevel riskLevel;
  final String? description;
  final String? reasoning;
  final List<String> matchedCardinal;
  final List<String> missingCardinal;
  final List<String> nextSteps;

  PredictedCondition({
    required this.canonicalId,
    required this.name,
    required this.confidence,
    required this.riskLevel,
    this.description,
    this.reasoning,
    this.matchedCardinal = const [],
    this.missingCardinal = const [],
    this.nextSteps = const [],
  });

  Map<String, dynamic> toJson() => {
        'canonicalId': canonicalId,
        'name': name,
        'confidence': confidence,
        'riskLevel': riskLevel.name,
        'description': description,
        'reasoning': reasoning,
        'matchedCardinal': matchedCardinal,
        'missingCardinal': missingCardinal,
        'nextSteps': nextSteps,
      };
}

/// Red flag alert — shown prominently at top of results.
class RedFlagAlert {
  final String conditionName;
  final String immediateAction;
  final List<String> triggerSymptoms;

  /// Canonical rule ID (e.g. `rf_sepsis`, `rf_severe_malaria`) — stable
  /// across locales and releases. `conditionName` is the English display
  /// label; `ruleId` is the key the analytics exporter uses so downstream
  /// aggregation doesn't depend on English string stability.
  final String? ruleId;

  RedFlagAlert({
    required this.conditionName,
    required this.immediateAction,
    required this.triggerSymptoms,
    this.ruleId,
  });

  Map<String, dynamic> toJson() => {
        'conditionName': conditionName,
        'immediateAction': immediateAction,
        'triggerSymptoms': triggerSymptoms,
        if (ruleId != null) 'ruleId': ruleId,
      };
}

/// Complete assessment result
class AssessmentResult {
  final Patient patient;
  final Vitals vitals;
  final List<String> symptoms;
  final List<PredictedCondition> conditions;
  final RiskLevel overallRisk;
  final List<String> nextSteps;
  final String? imagePath;
  final String? voiceTranscript;
  final String? additionalNotes;
  final RedFlagAlert? redFlag;
  final List<String> implicatedSystems;
  final List<SpecialistScreening> specialistScreenings;
  final List<MapEntry<String, double>>? imageClassificationResults;
  final String? imageType;
  DateTime assessedAt;

  AssessmentResult({
    required this.patient,
    required this.vitals,
    required this.symptoms,
    required this.conditions,
    required this.overallRisk,
    required this.nextSteps,
    this.imagePath,
    this.voiceTranscript,
    this.additionalNotes,
    this.redFlag,
    this.implicatedSystems = const [],
    this.specialistScreenings = const [],
    this.imageClassificationResults,
    this.imageType,
    DateTime? assessedAt,
  }) : assessedAt = assessedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'patient': patient.toJson(),
        'vitals': vitals.toJson(),
        'symptoms': symptoms,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'overallRisk': overallRisk.name,
        'nextSteps': nextSteps,
        'imagePath': imagePath,
        'voiceTranscript': voiceTranscript,
        'additionalNotes': additionalNotes,
        'redFlag': redFlag?.toJson(),
        'implicatedSystems': implicatedSystems,
        'specialistScreenings': specialistScreenings.map((s) => s.toJson()).toList(),
        'assessedAt': assessedAt.toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());
}
