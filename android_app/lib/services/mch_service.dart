// mch_service.dart
// Maternal & Child Health tracker — ANC visit schedule, immunizations, EDD
// calculator. Closes a real ASHA operational gap: most diagnostic apps ignore
// routine MCH work entirely. Borrowed from SwasthyaSathi + Karam Saathi decks.

import 'package:sqflite/sqflite.dart';

import 'database_service.dart';

enum MchKind { anc, immunization }

class MchRecord {
  final int? id;
  final String patientName;
  final int? patientAge;
  final MchKind kind;
  final String label;         // "ANC visit 2" or "BCG"
  final DateTime dueDate;
  final bool completed;
  final DateTime? completedOn;
  final String? notes;

  MchRecord({
    this.id,
    required this.patientName,
    this.patientAge,
    required this.kind,
    required this.label,
    required this.dueDate,
    this.completed = false,
    this.completedOn,
    this.notes,
  });

  bool get isOverdue =>
      !completed && dueDate.isBefore(DateTime.now());
  bool get isDueSoon =>
      !completed &&
      dueDate.difference(DateTime.now()).inDays <= 7 &&
      dueDate.isAfter(DateTime.now());

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'patient_name': patientName,
        'patient_age': patientAge,
        'kind': kind.name,
        'label': label,
        'due_date': dueDate.toIso8601String(),
        'completed': completed ? 1 : 0,
        'completed_on': completedOn?.toIso8601String(),
        'notes': notes,
      };

  factory MchRecord.fromMap(Map<String, dynamic> m) => MchRecord(
        id: m['id'] as int?,
        patientName: m['patient_name'] as String,
        patientAge: m['patient_age'] as int?,
        kind: MchKind.values.firstWhere(
          (k) => k.name == m['kind'],
          orElse: () => MchKind.anc,
        ),
        label: m['label'] as String,
        dueDate: DateTime.parse(m['due_date'] as String),
        completed: (m['completed'] as int?) == 1,
        completedOn: m['completed_on'] != null
            ? DateTime.tryParse(m['completed_on'] as String)
            : null,
        notes: m['notes'] as String?,
      );
}

class MchService {
  static const String _table = 'mch_records';

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        patient_name TEXT NOT NULL,
        patient_age INTEGER,
        kind TEXT NOT NULL,
        label TEXT NOT NULL,
        due_date TEXT NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        completed_on TEXT,
        notes TEXT
      )
    ''');
  }

  /// Compute EDD (estimated due date) from LMP using Naegele's rule:
  /// LMP + 280 days.
  static DateTime eddFromLmp(DateTime lmp) =>
      lmp.add(const Duration(days: 280));

  /// Generate the standard 4-visit ANC schedule (WHO/Govt of India protocol).
  /// Visit 1: <12 weeks, Visit 2: 14-26 weeks, Visit 3: 28-34 weeks, Visit 4: 36-40 weeks.
  static List<MchRecord> scheduleAnc({
    required String patientName,
    int? patientAge,
    required DateTime lmp,
  }) {
    final edd = eddFromLmp(lmp);
    final weeks = {
      'ANC Visit 1 (booking)': 8,
      'ANC Visit 2': 20,
      'ANC Visit 3': 30,
      'ANC Visit 4': 36,
    };
    final visits = <MchRecord>[];
    weeks.forEach((label, wk) {
      visits.add(MchRecord(
        patientName: patientName,
        patientAge: patientAge,
        kind: MchKind.anc,
        label: '$label (EDD ${_fmt(edd)})',
        dueDate: lmp.add(Duration(days: wk * 7)),
      ));
    });
    return visits;
  }

  /// Standard India UIP immunization schedule for a child born on [birthDate].
  /// Covers BCG, OPV, Penta, Rota, PCV, IPV, MR, JE, TT/Td milestones.
  static List<MchRecord> scheduleImmunizations({
    required String patientName,
    required DateTime birthDate,
  }) {
    // Days offset from birth
    const schedule = {
      'BCG + OPV-0 + Hep-B (birth)': 0,
      'Penta-1 + OPV-1 + Rota-1 + PCV-1 (6w)': 42,
      'Penta-2 + OPV-2 + Rota-2 (10w)': 70,
      'Penta-3 + OPV-3 + Rota-3 + PCV-2 (14w)': 98,
      'MR-1 + JE-1 + Vit A (9-12m)': 280,
      'DPT booster-1 + OPV booster + MR-2 + JE-2 (16-24m)': 540,
      'DPT booster-2 (5-6y)': 2000,
      'Td (10y)': 3650,
      'Td (16y)': 5840,
    };
    final visits = <MchRecord>[];
    schedule.forEach((label, days) {
      visits.add(MchRecord(
        patientName: patientName,
        kind: MchKind.immunization,
        label: label,
        dueDate: birthDate.add(Duration(days: days)),
      ));
    });
    return visits;
  }

  static Future<List<MchRecord>> upcoming({int days = 30}) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    final now = DateTime.now();
    final horizon = now.add(Duration(days: days));
    final rows = await db.query(
      _table,
      where: 'completed = 0 AND due_date <= ?',
      whereArgs: [horizon.toIso8601String()],
      orderBy: 'due_date ASC',
    );
    return rows.map(MchRecord.fromMap).toList();
  }

  static Future<int> pendingCount() async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM $_table WHERE completed = 0 AND due_date <= ?',
            [DateTime.now().toIso8601String()],
          ),
        ) ??
        0;
  }

  static Future<List<MchRecord>> all() async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    final rows = await db.query(_table, orderBy: 'due_date ASC');
    return rows.map(MchRecord.fromMap).toList();
  }

  static Future<int> insertBatch(List<MchRecord> records) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    final batch = db.batch();
    for (final r in records) {
      batch.insert(_table, r.toMap());
    }
    await batch.commit(noResult: true);
    return records.length;
  }

  static Future<int> markComplete(int id) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return db.update(
      _table,
      {
        'completed': 1,
        'completed_on': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  static Future<int> delete(int id) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  static String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
