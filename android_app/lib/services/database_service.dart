import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

import 'encryption_service.dart';
import 'inventory_service.dart';
import 'mch_service.dart';

/// Local SQLite database for patient records. PII columns (patient_name,
/// voice_transcript, notes) are encrypted at rest via [EncryptionService].
class DatabaseService {
  static Database? _db;
  static const int _schemaVersion = 2; // 1 -> 2: household_id on assessments

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
        await InventoryService.ensureSchema(db);
        await MchService.ensureSchema(db);
      },
    );
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
