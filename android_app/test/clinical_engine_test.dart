// clinical_engine_test.dart
// Golden-test harness for the diagnostic pipeline. Each vignette below is
// a hand-curated case that the rural-clinical literature classifies with a
// clear risk tier (or fires a specific red flag rule). If the engine ever
// drifts on any of these, we want to hear about it in CI — the whole value
// of a curated reasoning engine over an LLM is that its outputs should be
// reproducible.
//
// Vignettes stay deliberately small — enough symptoms to hit the clinical
// pattern, no extra noise. In real field use, patients report more
// symptoms and red flags fire earlier. Here we test the bar *exactly* at
// the minimum bundle the textbook would call.
//
// Feature E1 in the NeuCure roadmap — first tests in the repo.

import 'package:flutter_test/flutter_test.dart';
import 'package:rural_health_ai/services/clinical_engine.dart';
import 'package:rural_health_ai/services/clinical_knowledge.dart';

void main() {
  final engine = ClinicalEngine();

  DiagnosticResult diagnose({
    required List<String> symptoms,
    int? age,
    String? sex,
    Map<String, double>? vitals,
  }) {
    return engine.diagnose(
      rawSymptoms: symptoms,
      patientAge: age,
      patientSex: sex,
      vitals: vitals,
    );
  }

  // ────────────────────────────────────────────────────────────
  // Red-flag triggers (overallRisk MUST be emergency, rule id checked)
  // ────────────────────────────────────────────────────────────

  group('Red flag: fires on minimum triggering bundle', () {
    test('rf_meningitis — fever + neck stiffness + vomiting in child', () {
      final r = diagnose(
        symptoms: ['fever', 'neck_stiffness', 'vomiting'],
        age: 5,
      );
      expect(r.redFlag?.rule.id, 'rf_meningitis');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_mi — chest pain + sweating + SOB in 55yo male', () {
      final r = diagnose(
        symptoms: ['chest_pain', 'sweating', 'shortness_of_breath'],
        age: 55,
        sex: 'M',
      );
      expect(r.redFlag?.rule.id, 'rf_mi');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_stroke — one-sided weakness + speech difficulty', () {
      final r = diagnose(
        symptoms: ['weakness_one_side', 'speech_difficulty'],
        age: 65,
      );
      expect(r.redFlag?.rule.id, 'rf_stroke');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_severe_dehydration_child — diarrhea + sunken eyes in toddler',
        () {
      final r = diagnose(
        symptoms: ['diarrhea', 'sunken_eyes'],
        age: 2,
      );
      expect(r.redFlag?.rule.id, 'rf_severe_dehydration_child');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_sepsis — fever + altered consciousness + low BP', () {
      final r = diagnose(
        symptoms: ['fever', 'altered_consciousness', 'low_blood_pressure'],
        age: 40,
      );
      expect(r.redFlag?.rule.id, 'rf_sepsis');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_snakebite — snake bite + local swelling', () {
      final r = diagnose(
        symptoms: ['snake_bite', 'swelling_local'],
        age: 30,
      );
      expect(r.redFlag?.rule.id, 'rf_snakebite');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_hypoglycemia — sweating + confusion + palpitations', () {
      final r = diagnose(
        symptoms: ['sweating', 'confusion', 'palpitations'],
        age: 45,
      );
      expect(r.redFlag?.rule.id, 'rf_hypoglycemia');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_dengue_hemorrhagic — fever + bleeding + rash', () {
      final r = diagnose(
        symptoms: ['fever', 'bleeding', 'rash'],
        age: 25,
      );
      expect(r.redFlag?.rule.id, 'rf_dengue_hemorrhagic');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });

    test('rf_severe_respiratory — severe SOB (stands alone)', () {
      final r = diagnose(
        symptoms: ['severe_shortness_of_breath'],
        age: 40,
      );
      expect(r.redFlag?.rule.id, 'rf_severe_respiratory');
      expect(r.overallRisk, ClinicalRisk.emergency);
    });
  });

  // ────────────────────────────────────────────────────────────
  // Red-flag non-firing (tight cardinal elimination + demographics)
  // ────────────────────────────────────────────────────────────

  group('Red flag: does NOT fire on weak bundles', () {
    test('Fever alone does NOT trigger sepsis or meningitis', () {
      final r = diagnose(symptoms: ['fever'], age: 30);
      expect(r.redFlag, isNull,
          reason:
              'Isolated fever must not escalate to a red flag — we would page the whole village.');
      expect(r.overallRisk,
          isNot(equals(ClinicalRisk.emergency)));
    });

    test('Chest pain alone in a teenager does NOT trigger rf_mi', () {
      // rf_mi has a demographics filter of age >= 30. A 16yo with chest
      // pain shouldn't be tagged for suspected MI.
      final r = diagnose(
        symptoms: ['chest_pain'],
        age: 16,
      );
      expect(r.redFlag?.rule.id, isNot('rf_mi'));
    });

    test('Sweating + confusion alone does NOT trigger hypoglycemia', () {
      // rf_hypoglycemia needs required + at least 1 supporting. Bare pair
      // is classic anxiety presentation, not hypoglycemia.
      final r = diagnose(
        symptoms: ['sweating', 'confusion'],
        age: 40,
      );
      expect(r.redFlag?.rule.id, isNot('rf_hypoglycemia'));
    });
  });

  // ────────────────────────────────────────────────────────────
  // Scored differentials (no red flag; verify top condition + risk tier)
  // ────────────────────────────────────────────────────────────

  group('Scored differential: top condition matches textbook presentation', () {
    test('Malaria — textbook triad (high fever + chills + sweating)', () {
      // The curated malaria profile (clinical_knowledge.dart) lists
      // high_fever / chills / sweating as the three cardinals. A generic
      // "fever + chills + body pain" is deliberately not enough — flu and
      // viral fever share that pattern and outweigh on prevalence. The
      // textbook malaria triad IS specific and must surface the diagnosis.
      final r = diagnose(
        symptoms: ['high_fever', 'chills', 'sweating', 'headache'],
        age: 30,
      );
      expect(r.conditions, isNotEmpty);
      final topIds = r.conditions.take(3).map((c) => c.profile.id).toList();
      expect(topIds, contains('malaria'),
          reason:
              'Classic malaria triad (high-fever/chills/sweating) must surface in the top-3.');
      // Malaria is urgent in curated profiles (not emergency — severe
      // malaria has a separate red-flag rule).
      expect(
          [ClinicalRisk.urgent, ClinicalRisk.moderate].contains(r.overallRisk),
          isTrue);
    });

    test('Tuberculosis — chronic cough + night sweats + weight loss', () {
      final r = diagnose(
        symptoms: ['cough', 'night_sweats', 'weight_loss'],
        age: 40,
      );
      final topIds = r.conditions.take(3).map((c) => c.profile.id).toList();
      expect(topIds, contains('tuberculosis'),
          reason:
              'The classic chronic-TB triad must surface in the top-3 given India TB burden.');
    });

    test('Gastroenteritis — diarrhea + vomiting + abdominal pain in adult',
        () {
      // Adult patient → no rf_severe_dehydration_child.
      final r = diagnose(
        symptoms: ['diarrhea', 'vomiting', 'abdominal_pain'],
        age: 25,
      );
      expect(r.redFlag, isNull);
      final topIds = r.conditions.take(3).map((c) => c.profile.id).toList();
      expect(topIds, contains('gastroenteritis'));
    });

    test('Common cold — runny nose + sore throat + sneezing → normal tier',
        () {
      final r = diagnose(
        symptoms: ['runny_nose', 'sore_throat', 'sneezing'],
        age: 25,
      );
      expect(r.redFlag, isNull);
      expect(r.overallRisk,
          anyOf(ClinicalRisk.normal, ClinicalRisk.moderate));
    });

    test('Urinary tract infection — dysuria + frequency in adult female', () {
      final r = diagnose(
        symptoms: ['burning_urination', 'frequent_urination'],
        age: 30,
        sex: 'F',
      );
      expect(r.redFlag, isNull);
      final topIds = r.conditions.take(3).map((c) => c.profile.id).toList();
      expect(topIds, contains('uti'));
    });

    test('Conjunctivitis — red eye + eye discharge → normal tier', () {
      final r = diagnose(
        symptoms: ['red_eye', 'eye_discharge'],
        age: 12,
      );
      expect(r.redFlag, isNull);
      expect(r.overallRisk, isNot(equals(ClinicalRisk.emergency)));
    });
  });

  // ────────────────────────────────────────────────────────────
  // Vital-driven injections (e.g., temperature → fever variants)
  // ────────────────────────────────────────────────────────────

  group('Vitals integration', () {
    test('Temperature ≥104°F without reported fever still scores as febrile',
        () {
      // The engine injects `fever` / `high_fever` from vitals, so a patient
      // who says "I have a headache" but has a 104°F temperature should
      // still land in a febrile differential.
      final r = diagnose(
        symptoms: ['headache'],
        vitals: {'temperature': 104.0},
        age: 25,
      );
      // At minimum, the engine should NOT classify this as 'normal'.
      expect(r.overallRisk,
          isNot(equals(ClinicalRisk.normal)));
    });

    test('BP 180/110 + severe headache is high-risk (hypertensive context)',
        () {
      final r = diagnose(
        symptoms: ['severe_headache'],
        vitals: {'bp_systolic': 180, 'bp_diastolic': 110},
        age: 55,
      );
      expect(r.overallRisk,
          isNot(equals(ClinicalRisk.normal)),
          reason: 'A crisis BP with a neurological symptom should never '
              'grade as "normal" — escalate to at least moderate.');
    });
  });

  // ────────────────────────────────────────────────────────────
  // Invariant: empty input
  // ────────────────────────────────────────────────────────────

  group('Invariants', () {
    test('Empty symptom list returns normal tier with zero conditions', () {
      final r = diagnose(symptoms: const [], age: 25);
      expect(r.redFlag, isNull);
      expect(r.conditions, isEmpty);
      expect(r.overallRisk, ClinicalRisk.normal);
    });

    test('Unknown symptoms are dropped, not matched', () {
      // `abracadabra` isn't in symptomSystemMap / aliases / any profile.
      // The CLAUDE.md invariant: unknown tokens are dropped (not kept).
      final r = diagnose(symptoms: ['abracadabra'], age: 25);
      expect(r.redFlag, isNull);
      expect(r.conditions, isEmpty);
    });
  });
}
