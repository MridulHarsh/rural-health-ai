// outcome_service.dart
// CRUD for the followup_outcomes table. PII fields are encrypted at rest
// through EncryptionService; enum / flag / date columns stay plaintext so
// AnalyticsExporter can aggregate without the key.
//
// Feature #3 in the NeuCure roadmap: opt-in real-world outcome tracking.

import 'package:sqflite/sqflite.dart';

import '../models/followup_outcome.dart';
import 'database_service.dart';
import 'encryption_service.dart';

class OutcomeService {
  /// Follow-up is considered "due" this many days after the original
  /// assessment. 7 days mirrors the standard ASHA home-visit schedule.
  static const Duration followupDue = Duration(days: 7);

  /// Persist an outcome. PII fields (actual_diagnosis, treatment_given,
  /// notes) are encrypted before insert.
  static Future<void> save(FollowupOutcome outcome) async {
    final db = await DatabaseService.database;
    await db.insert(
      'followup_outcomes',
      {
        'id': outcome.id,
        'assessment_id': outcome.assessmentId,
        'followup_date': outcome.followupDate.toIso8601String(),
        'actual_diagnosis':
            EncryptionService.encryptString(outcome.actualDiagnosis),
        'treatment_given':
            EncryptionService.encryptString(outcome.treatmentGiven),
        'adherence': outcome.adherence.name,
        'outcome_status': outcome.outcomeStatus.name,
        'notes': EncryptionService.encryptString(outcome.notes),
        'consent_to_share': outcome.consentToShare ? 1 : 0,
        'created_at': outcome.createdAt.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// All outcomes recorded against a given assessment, newest first.
  static Future<List<FollowupOutcome>> listForAssessment(
      String assessmentId) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'followup_outcomes',
      where: 'assessment_id = ?',
      whereArgs: [assessmentId],
      orderBy: 'followup_date DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Map a SQLite row (with encrypted PII columns) into the model.
  /// Decryption failures yield null on the affected field — we refuse to
  /// crash the follow-up screen because one stale envelope is un-decodable.
  static FollowupOutcome _fromRow(Map<String, Object?> row) {
    return FollowupOutcome(
      id: row['id'] as String,
      assessmentId: row['assessment_id'] as String,
      followupDate: DateTime.parse(row['followup_date'] as String),
      actualDiagnosis: _safeDecrypt(row['actual_diagnosis'] as String?),
      treatmentGiven: _safeDecrypt(row['treatment_given'] as String?),
      adherence:
          FollowupOutcome.adherenceFromName(row['adherence'] as String?),
      outcomeStatus: FollowupOutcome.statusFromName(
          row['outcome_status'] as String?),
      notes: _safeDecrypt(row['notes'] as String?),
      consentToShare: (row['consent_to_share'] as int?) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  static String? _safeDecrypt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return EncryptionService.decryptString(raw);
    } catch (_) {
      return null;
    }
  }

  /// Set of assessment IDs with at least one recorded outcome. Used by the
  /// history screen to hide the "Record outcome" call-to-action once
  /// something has already been captured.
  static Future<Set<String>> assessmentIdsWithOutcomes() async {
    final db = await DatabaseService.database;
    final rows = await db.rawQuery(
        'SELECT DISTINCT assessment_id FROM followup_outcomes');
    return rows.map((r) => r['assessment_id'] as String).toSet();
  }

  /// True when [assessmentDate] is at least [followupDue] in the past AND
  /// no outcome has been recorded yet. Drives the amber "Follow-up due"
  /// badge on the history list.
  static bool isFollowupDue({
    required DateTime assessmentDate,
    required bool hasOutcome,
    DateTime? now,
  }) {
    if (hasOutcome) return false;
    final n = now ?? DateTime.now();
    return n.difference(assessmentDate) >= followupDue;
  }
}
