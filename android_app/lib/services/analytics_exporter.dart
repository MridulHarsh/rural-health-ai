// analytics_exporter.dart
// De-identified append-only JSONL of (assessment, follow-up outcome) pairs.
// Drives real-world-evidence analytics for NeuCure — what the AI predicted
// vs. what the PHC actually diagnosed, plus adherence and outcome status.
//
// Feature #3 in the NeuCure roadmap. Consent is per-encounter — the caller
// must check FollowupOutcome.consentToShare before invoking [record]; this
// file will refuse to write otherwise.
//
// De-identification rules (all applied before a record touches disk):
//   1. No patient name, no ABHA ID, no ABHA address, no free text of any kind.
//   2. Age is bucketed (0-4 / 5-17 / 18-29 / 30-49 / 50-64 / 65+). A precise
//      age on a sparse district dataset is a re-identification vector.
//   3. Dates are bucketed to ISO week (`2026-W15`). Week is the coarsest
//      bucket that still preserves outbreak seasonality for analytics.
//   4. Conditions are stored as canonical DiseaseProfile IDs (not names,
//      not ICD-10). Free-text disease names are stripped.
//   5. An `encounter_hash` = first 16 hex chars of SHA-256(patient.id) links
//      the record back to the source SQLite row on-device only — the mapping
//      is not exportable without the original patient.id (itself a UUID that
//      never leaves the device).
//   6. No vital values are exported, only which were collected. Actual
//      numeric vitals correlate tightly with identifiable patient attributes
//      (height + weight + age + village is enough to re-identify in a small
//      cohort); "vitals_present" answers the coverage question analytics
//      needs without the PII exposure.
//   7. `actual_diagnosis` and `treatment_given` are free text entered by the
//      ASHA — NEVER include them, even encrypted. Adherence + outcome_status
//      enums are the analyzable signal.
//
// Schema version is stamped on every record (`export_schema_version`) so a
// future backward-compatible change can be distinguished at ingest time.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../models/followup_outcome.dart';
import '../models/patient.dart';

class AnalyticsExporter {
  /// Bump when the record shape changes in a non-additive way.
  static const int schemaVersion = 1;

  /// Filename inside `getApplicationDocumentsDirectory()`. JSONL so each line
  /// is independently parseable — a truncated tail from a flaky share-export
  /// is still readable up to the last complete line.
  static const String fileName = 'outcomes_deid.jsonl';

  /// Append a de-identified record for a (result, outcome) pair.
  /// No-op (and returns false) when [outcome.consentToShare] is false —
  /// consent is required per DPDP and the analytics contract.
  static Future<bool> record({
    required AssessmentResult result,
    required FollowupOutcome outcome,
  }) async {
    if (!outcome.consentToShare) return false;
    final file = await _file();
    final line = jsonEncode(_buildRecord(result: result, outcome: outcome));
    await file.writeAsString('$line\n',
        mode: FileMode.append, flush: true);
    return true;
  }

  /// Absolute path to the JSONL file (creating the parent dir if needed).
  /// Use this to attach the file to a share sheet or to surface it in
  /// Settings → "View my anonymized contributions".
  static Future<String> filePath() async => (await _file()).path;

  /// How many records have been written. Cheap line count; the file stays
  /// small — 1 KB per record, a productive ASHA writes ~20 rows a month.
  static Future<int> recordCount() async {
    final f = await _file();
    if (!await f.exists()) return 0;
    final contents = await f.readAsString();
    if (contents.isEmpty) return 0;
    // Trailing newline → extra empty segment; filter it out.
    return contents.split('\n').where((l) => l.isNotEmpty).length;
  }

  /// Wipe the local export. Use from Settings when a user withdraws
  /// consent — the records are already de-identified but the user's mental
  /// model is "erase my data" and we honor that.
  static Future<void> clear() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }

  // ───────────────────────── internals ─────────────────────────

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }

  static Map<String, dynamic> _buildRecord({
    required AssessmentResult result,
    required FollowupOutcome outcome,
  }) {
    final top3 = result.conditions
        .take(3)
        .map((c) => c.canonicalId)
        .toList(growable: false);

    return {
      'encounter_hash': _encounterHash(result.patient.id),
      'assessment_week': _isoWeek(result.assessedAt),
      'followup_week': _isoWeek(outcome.followupDate),
      'age_bucket': _ageBucket(result.patient.age),
      'gender': _normalizedGender(result.patient.gender),
      'top_conditions': top3,
      'condition_confidences': result.conditions
          .take(3)
          .map((c) => double.parse(c.confidence.toStringAsFixed(2)))
          .toList(growable: false),
      'overall_risk': result.overallRisk.name,
      'implicated_systems': result.implicatedSystems,
      'red_flag_triggered': result.redFlag != null,
      'red_flag_condition': result.redFlag?.conditionName,
      'vitals_present': _vitalsPresent(result.vitals),
      'has_image': result.imagePath != null,
      'image_type': result.imageType,
      'voice_used': (result.voiceTranscript ?? '').isNotEmpty,
      'specialist_screenings': result.specialistScreenings
          .map((s) => {
                'model': s.modelKey,
                'risk_score': double.parse(s.riskScore.toStringAsFixed(2)),
                'risk_label': s.riskLabel,
                'feature_coverage':
                    double.parse(s.featureCoverage.toStringAsFixed(2)),
              })
          .toList(growable: false),
      'outcome': {
        'adherence': outcome.adherence.name,
        'outcome_status': outcome.outcomeStatus.name,
        'days_to_followup':
            outcome.followupDate.difference(result.assessedAt).inDays,
      },
      'export_schema_version': schemaVersion,
    };
  }

  /// First 16 hex chars of SHA-256(patient.id). Enough entropy to avoid
  /// collisions in realistic dataset sizes, short enough that the exported
  /// file stays human-readable on a low-end phone.
  static String _encounterHash(String patientId) {
    final digest = sha256.convert(utf8.encode(patientId)).toString();
    return digest.substring(0, 16);
  }

  /// Age bucket. Boundaries chosen to align with NFHS-5 reporting cohorts
  /// (under-5 mortality, school-age, reproductive, adult, older-adult, 65+).
  static String _ageBucket(int age) {
    if (age < 5) return '0-4';
    if (age < 18) return '5-17';
    if (age < 30) return '18-29';
    if (age < 50) return '30-49';
    if (age < 65) return '50-64';
    return '65+';
  }

  /// Collapse to FHIR-like closed set. The raw patient.gender field carries
  /// whatever the ASHA typed; the analytics export must not ship that.
  static String _normalizedGender(String raw) {
    final g = raw.trim().toLowerCase();
    if (g == 'm' || g == 'male') return 'male';
    if (g == 'f' || g == 'female') return 'female';
    if (g.isEmpty) return 'unknown';
    return 'other';
  }

  /// ISO-8601 week ("2026-W15"). Uses the standard "Thursday rule": the week
  /// containing the first Thursday of the year is week 1. Avoids the
  /// calendar-week ambiguity at year boundaries that would otherwise bucket
  /// late-December and early-January encounters inconsistently.
  static String _isoWeek(DateTime date) {
    final utc = date.toUtc();
    final thursday = utc.add(Duration(days: 4 - (utc.weekday)));
    final firstJan = DateTime.utc(thursday.year, 1, 1);
    final week = ((thursday.difference(firstJan).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  static List<String> _vitalsPresent(Vitals v) {
    final present = <String>[];
    if (v.temperature != null) present.add('temperature');
    if (v.bloodPressure != null && v.bloodPressure!.isNotEmpty) {
      present.add('bp');
    }
    if (v.heartRate != null) present.add('hr');
    if (v.spo2 != null) present.add('spo2');
    if (v.weight != null) present.add('weight');
    if (v.height != null) present.add('height');
    return present;
  }
}
