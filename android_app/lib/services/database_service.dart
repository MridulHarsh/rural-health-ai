import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import 'encryption_service.dart';
import 'inventory_service.dart';
import 'mch_service.dart';

// ignore_for_file: unused_element

/// Local SQLite database for patient records. PII columns (patient_name,
/// voice_transcript, notes, abha_id, abha_address, outcome free-text) are
/// encrypted at rest via [EncryptionService].
class DatabaseService {
  static Database? _db;
  // Schema versions:
  //   1 -> 2: household_id on assessments
  //   2 -> 3: abha_id + abha_address on assessments; followup_outcomes table
  //   3 -> 4: handoff_queue table (feature #4 — offline Outbox)
  static const int _schemaVersion = 4;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final dbFile = path.join(dbPath, 'rural_health.db');

    return openDatabase(
      dbFile,
      version: _schemaVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE assessments(
            id TEXT PRIMARY KEY,
            household_id TEXT,
            patient_name TEXT,
            patient_age INTEGER,
            patient_gender TEXT,
            abha_id TEXT,
            abha_address TEXT,
            symptoms TEXT,
            vitals TEXT,
            conditions TEXT,
            overall_risk TEXT,
            next_steps TEXT,
            image_path TEXT,
            voice_transcript TEXT,
            notes TEXT,
            created_at TEXT
          )
        ''');
        await _createFollowupOutcomesTable(db);
        await _createHandoffQueueTable(db);
        await InventoryService.ensureSchema(db);
        await MchService.ensureSchema(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try {
            await db.execute(
                'ALTER TABLE assessments ADD COLUMN household_id TEXT');
          } catch (_) {/* column may exist */}
        }
        if (oldV < 3) {
          // ABHA fields are nullable — pre-existing rows stay valid as NULL.
          for (final col in ['abha_id', 'abha_address']) {
            try {
              await db.execute(
                  'ALTER TABLE assessments ADD COLUMN $col TEXT');
            } catch (_) {/* column may exist */}
          }
          await _createFollowupOutcomesTable(db);
        }
        if (oldV < 4) {
          await _createHandoffQueueTable(db);
        }
        await InventoryService.ensureSchema(db);
        await MchService.ensureSchema(db);
      },
    );
  }

  /// handoff_queue schema. The `payload_enc`, `recipient_enc`, and
  /// `label_enc` columns are AES-GCM envelopes (see [EncryptionService]) —
  /// the message body contains the patient summary and the recipient is a
  /// phone number, both PII under DPDP. The status enum + kind + counters
  /// stay plaintext so the Outbox can aggregate without the key.
  ///
  /// Marked [visibleForTesting] so the unit-test harness can re-create the
  /// schema on an in-memory sqflite_common_ffi database without duplicating
  /// the DDL.
  @visibleForTesting
  static Future<void> createHandoffQueueTable(Database db) =>
      _createHandoffQueueTable(db);

  static Future<void> _createHandoffQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS handoff_queue(
        id TEXT PRIMARY KEY,
        kind TEXT NOT NULL,
        payload_enc TEXT NOT NULL,
        recipient_enc TEXT,
        file_path TEXT,
        file_hash TEXT,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        last_tried_at TEXT,
        label_enc TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_handoff_status ON handoff_queue(status)');
  }

  /// Replace the shared SQLite handle for unit tests. Production code never
  /// touches this — it's guarded behind [visibleForTesting] and the CI
  /// build does not include test sources.
  @visibleForTesting
  static void debugOverrideDatabase(Database? db) {
    _db = db;
  }

  /// followup_outcomes schema. PII fields (actual_diagnosis, treatment_given,
  /// notes) are AES-GCM envelopes; enum fields and the consent flag stay
  /// plaintext so the analytics exporter can read them without the key.
  static Future<void> _createFollowupOutcomesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS followup_outcomes(
        id TEXT PRIMARY KEY,
        assessment_id TEXT NOT NULL,
        followup_date TEXT NOT NULL,
        actual_diagnosis TEXT,
        treatment_given TEXT,
        adherence TEXT NOT NULL,
        outcome_status TEXT NOT NULL,
        notes TEXT,
        consent_to_share INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY(assessment_id) REFERENCES assessments(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_followup_assessment ON followup_outcomes(assessment_id)');
  }

  /// Save an assessment record. PII fields are encrypted transparently.
  static Future<void> saveAssessment(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'assessments',
      {
        'id': data['patient']?['id'] ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        'household_id': data['patient']?['householdId'],
        'patient_name': EncryptionService.encryptString(
            data['patient']?['name'] ?? 'Unknown'),
        'patient_age': data['patient']?['age'] ?? 0,
        'patient_gender': data['patient']?['gender'] ?? '',
        // ABHA identifiers are PII under DPDP — store encrypted. Patient may
        // consent to sharing with a specific HIU later; that's a re-share
        // action, not a reason to leave the value plaintext on disk.
        'abha_id':
            EncryptionService.encryptString(data['patient']?['abhaId']),
        'abha_address':
            EncryptionService.encryptString(data['patient']?['abhaAddress']),
        'symptoms': jsonEncode(data['symptoms'] ?? []),
        'vitals': jsonEncode(data['vitals'] ?? {}),
        'conditions': jsonEncode(data['conditions'] ?? []),
        'overall_risk': data['overallRisk'] ?? 'urgent',
        'next_steps': jsonEncode(data['nextSteps'] ?? []),
        'image_path': data['imagePath'],
        'voice_transcript':
            EncryptionService.encryptString(data['voiceTranscript']),
        'notes': EncryptionService.encryptString(data['additionalNotes']),
        'created_at':
            data['assessedAt'] ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all assessment records. PII is decrypted transparently.
  static Future<List<Map<String, dynamic>>> getAssessments() async {
    final db = await database;
    final results = await db.query(
      'assessments',
      orderBy: 'created_at DESC',
    );

    return results.map((row) {
      return {
        'id': row['id'],
        'householdId': row['household_id'],
        'patientName': _safeDecrypt(row['patient_name'] as String?),
        'patientAge': row['patient_age'],
        'patientGender': row['patient_gender'],
        'abhaId': _safeDecrypt(row['abha_id'] as String?),
        'abhaAddress': _safeDecrypt(row['abha_address'] as String?),
        'symptoms': _safeDecode(row['symptoms'], fallback: const []),
        'vitals': _safeDecode(row['vitals'], fallback: const {}),
        'conditions': _safeDecode(row['conditions'], fallback: const []),
        'overallRisk': row['overall_risk'],
        'nextSteps': _safeDecode(row['next_steps'], fallback: const []),
        'imagePath': row['image_path'],
        'voiceTranscript': _safeDecrypt(row['voice_transcript'] as String?),
        'notes': _safeDecrypt(row['notes'] as String?),
        'createdAt': row['created_at'],
      };
    }).toList();
  }

  /// Decrypt a PII column. If the stored envelope is corrupt (or was written
  /// by an earlier keystore that got wiped), return null instead of crashing
  /// the entire history retrieval — matches the _safeDecode resilience pattern
  /// we already apply to JSON columns. Partial patient records beat an app
  /// that refuses to load any history.
  static String? _safeDecrypt(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return EncryptionService.decryptString(raw);
    } catch (_) {
      return null;
    }
  }

  /// Get all assessments for a given household (for family/clustered view).
  static Future<List<Map<String, dynamic>>> getByHousehold(
      String householdId) async {
    final all = await getAssessments();
    return all.where((r) => r['householdId'] == householdId).toList();
  }

  /// Decode a JSON-encoded column safely. A single corrupted record must not
  /// crash history retrieval for the entire dataset.
  static dynamic _safeDecode(dynamic raw, {required dynamic fallback}) {
    if (raw == null) return fallback;
    if (raw is! String || raw.isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (e) {
      // The offending JSON is patient data (symptoms / vitals / conditions);
      // jsonDecode exceptions typically embed a fragment of the source
      // string. Log only the exception type so release-build logcat never
      // leaks partial patient records.
      debugPrint('[DatabaseService] corrupted JSON column: ${e.runtimeType}');
      return fallback;
    }
  }

  /// Delete an assessment
  static Future<void> deleteAssessment(String id) async {
    final db = await database;
    await db.delete('assessments', where: 'id = ?', whereArgs: [id]);
  }

  /// Get record count
  static Future<int> getCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM assessments');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
