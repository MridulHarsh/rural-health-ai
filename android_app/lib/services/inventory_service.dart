// inventory_service.dart
// ASHA medicine-kit inventory tracker. CRUD over a small SQLite table. Turns
// the app from a diagnostic-only tool into an operational one — borrowed from
// SwasthyaSathi, SwarmDoc, Karam Saathi decks.
//
// Stock-out detection surfaces on the home screen so the ASHA knows what to
// refill on their next PHC visit, and the diagnostic nextSteps can be
// annotated with "(out of stock)" where appropriate.

import 'package:sqflite/sqflite.dart';

import 'database_service.dart';

class MedicineItem {
  final int? id;
  final String name;          // generic name (e.g., "Paracetamol 500mg")
  final String category;      // "fever", "antibiotic", "ORS", "maternal", etc.
  final int stockQty;
  final int reorderThreshold; // alert when stockQty <= this
  final String? notes;
  final DateTime? expiryDate;

  MedicineItem({
    this.id,
    required this.name,
    required this.category,
    required this.stockQty,
    this.reorderThreshold = 5,
    this.notes,
    this.expiryDate,
  });

  bool get isLowStock => stockQty <= reorderThreshold;
  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    return expiryDate!.difference(DateTime.now()).inDays <= 30;
  }
  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'category': category,
        'stock_qty': stockQty,
        'reorder_threshold': reorderThreshold,
        'notes': notes,
        'expiry_date': expiryDate?.toIso8601String(),
      };

  factory MedicineItem.fromMap(Map<String, dynamic> m) => MedicineItem(
        id: m['id'] as int?,
        name: m['name'] as String,
        category: m['category'] as String? ?? 'other',
        stockQty: (m['stock_qty'] as int?) ?? 0,
        reorderThreshold: (m['reorder_threshold'] as int?) ?? 5,
        notes: m['notes'] as String?,
        expiryDate: m['expiry_date'] != null
            ? DateTime.tryParse(m['expiry_date'] as String)
            : null,
      );
}

class InventoryService {
  static const String _table = 'inventory';

  /// Seed a realistic ASHA kit if the table is empty. Common meds the WHO
  /// Essential Medicines List recommends for primary care in India.
  static const List<Map<String, dynamic>> _seed = [
    {'name': 'Paracetamol 500mg', 'category': 'fever', 'stock_qty': 30},
    {'name': 'ORS sachet', 'category': 'diarrhea', 'stock_qty': 40},
    {'name': 'Iron + Folic Acid', 'category': 'maternal', 'stock_qty': 50},
    {'name': 'Albendazole 400mg', 'category': 'deworming', 'stock_qty': 20},
    {'name': 'Zinc tablets 20mg', 'category': 'diarrhea', 'stock_qty': 25},
    {'name': 'Amoxicillin 250mg', 'category': 'antibiotic', 'stock_qty': 12},
    {'name': 'Co-trimoxazole', 'category': 'antibiotic', 'stock_qty': 10},
    {'name': 'Metronidazole 400mg', 'category': 'antibiotic', 'stock_qty': 10},
    {'name': 'Vitamin A capsules', 'category': 'nutrition', 'stock_qty': 15},
    {'name': 'Chloroquine (NVBDCP)', 'category': 'antimalarial', 'stock_qty': 8},
    {'name': 'Misoprostol', 'category': 'maternal', 'stock_qty': 4},
    {'name': 'Magnesium sulfate inj.', 'category': 'maternal', 'stock_qty': 2},
    {'name': 'Paracetamol syrup (ped.)', 'category': 'pediatric', 'stock_qty': 6},
    {'name': 'Disposable gloves', 'category': 'supplies', 'stock_qty': 20},
    {'name': 'Thermometer', 'category': 'equipment', 'stock_qty': 1},
  ];

  static Future<void> ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL,
        stock_qty INTEGER NOT NULL DEFAULT 0,
        reorder_threshold INTEGER NOT NULL DEFAULT 5,
        notes TEXT,
        expiry_date TEXT
      )
    ''');
    final cnt = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM $_table'),
        ) ??
        0;
    if (cnt == 0) {
      final batch = db.batch();
      for (final s in _seed) {
        batch.insert(_table, s);
      }
      await batch.commit(noResult: true);
    }
  }

  static Future<List<MedicineItem>> getAll() async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    final rows = await db.query(_table, orderBy: 'category, name');
    return rows.map(MedicineItem.fromMap).toList();
  }

  static Future<List<MedicineItem>> lowStock() async {
    final all = await getAll();
    return all.where((m) => m.isLowStock || m.isExpired).toList();
  }

  static Future<int> insert(MedicineItem m) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return db.insert(_table, m.toMap());
  }

  static Future<int> update(MedicineItem m) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return db.update(_table, m.toMap(), where: 'id = ?', whereArgs: [m.id]);
  }

  static Future<int> delete(int id) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  static Future<int> adjustStock(int id, int delta) async {
    final db = await DatabaseService.database;
    await ensureSchema(db);
    return db.rawUpdate(
      'UPDATE $_table SET stock_qty = MAX(0, stock_qty + ?) WHERE id = ?',
      [delta, id],
    );
  }
}
