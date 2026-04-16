import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

/// Local SQLite database for patient records
class DatabaseService {
  static Database? _db;

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
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE assessments(
            id TEXT PRIMARY KEY,
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
      },
    );
  }

  /// Save an assessment record
  static Future<void> saveAssessment(Map<String, dynamic> data) async {
    final db = await database;
    await db.insert(
      'assessments',
      {
        'id': data['patient']?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'patient_name': data['patient']?['name'] ?? 'Unknown',
        'patient_age': data['patient']?['age'] ?? 0,
        'patient_gender': data['patient']?['gender'] ?? '',
        'symptoms': jsonEncode(data['symptoms'] ?? []),
        'vitals': jsonEncode(data['vitals'] ?? {}),
        'conditions': jsonEncode(data['conditions'] ?? []),
        'overall_risk': data['overallRisk'] ?? 'urgent',
        'next_steps': jsonEncode(data['nextSteps'] ?? []),
        'image_path': data['imagePath'],
        'voice_transcript': data['voiceTranscript'],
        'notes': data['additionalNotes'],
        'created_at': data['assessedAt'] ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get all assessment records
  static Future<List<Map<String, dynamic>>> getAssessments() async {
    final db = await database;
    final results = await db.query(
      'assessments',
      orderBy: 'created_at DESC',
    );

    return results.map((row) {
      return {
        'id': row['id'],
        'patientName': row['patient_name'],
        'patientAge': row['patient_age'],
        'patientGender': row['patient_gender'],
        'symptoms': _safeDecode(row['symptoms'], fallback: const []),
        'vitals': _safeDecode(row['vitals'], fallback: const {}),
        'conditions': _safeDecode(row['conditions'], fallback: const []),
        'overallRisk': row['overall_risk'],
        'nextSteps': _safeDecode(row['next_steps'], fallback: const []),
        'imagePath': row['image_path'],
        'voiceTranscript': row['voice_transcript'],
        'notes': row['notes'],
        'createdAt': row['created_at'],
      };
    }).toList();
  }

  /// Decode a JSON-encoded column safely. A single corrupted record must not
  /// crash history retrieval for the entire dataset.
  static dynamic _safeDecode(dynamic raw, {required dynamic fallback}) {
    if (raw == null) return fallback;
    if (raw is! String || raw.isEmpty) return fallback;
    try {
      return jsonDecode(raw);
    } catch (e) {
      // Log and return fallback — don't propagate the crash.
      // ignore: avoid_print
      print('[DatabaseService] corrupted JSON column: $e');
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
