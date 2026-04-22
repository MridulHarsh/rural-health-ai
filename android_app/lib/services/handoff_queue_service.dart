// handoff_queue_service.dart
// Persistence + query layer for the Outbox. See [HandoffQueueItem] for the
// queue-status semantics (pending vs. launched).
//
// Feature #4 in the NeuCure roadmap — offline-tolerant PHC handoff queue.
//
// Why this layer exists: WhatsApp and SMS already queue messages internally
// once composed, so "auto-sent when a bar returns" is really WhatsApp's job.
// What the ASHA actually loses without this Outbox is the *draft* — if she
// taps "Send to PHC" while offline and the composer can't even open, there's
// no way to retry later. The Outbox pins the intent (message + recipient +
// optional FHIR bundle file) to disk so she can re-launch whenever she has
// signal, and gives us an audit trail of every handoff attempt.

import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/handoff_queue_item.dart';
import 'database_service.dart';
import 'encryption_service.dart';

class HandoffQueueService {
  static const _uuid = Uuid();

  /// Persist a new queue item. PII (payload, recipient, label) is encrypted
  /// before insert. Returns the generated id.
  static Future<String> enqueue({
    required HandoffKind kind,
    required String payload,
    String? recipient,
    String? filePath,
    String? fileHash,
    String? label,
    HandoffStatus status = HandoffStatus.pending,
  }) async {
    final db = await DatabaseService.database;
    final id = _uuid.v4();
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'handoff_queue',
      {
        'id': id,
        'kind': kind.name,
        'payload_enc': EncryptionService.encryptString(payload),
        'recipient_enc': EncryptionService.encryptString(recipient),
        'file_path': filePath,
        'file_hash': fileHash,
        'status': status.name,
        'attempts': status == HandoffStatus.launched ? 1 : 0,
        'created_at': now,
        'last_tried_at':
            status == HandoffStatus.launched ? now : null,
        'label_enc': EncryptionService.encryptString(label),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  /// Mark an existing item as [HandoffStatus.launched] and bump its attempt
  /// counter. Called right after a successful composer launch.
  static Future<void> markLaunched(String id) async {
    final db = await DatabaseService.database;
    final now = DateTime.now().toIso8601String();
    await db.rawUpdate(
      'UPDATE handoff_queue SET status = ?, attempts = attempts + 1, '
      'last_tried_at = ? WHERE id = ?',
      [HandoffStatus.launched.name, now, id],
    );
  }

  /// Remove an item from the queue. If the item owned a backing file (FHIR
  /// bundle), the file is deleted too — leaving orphaned bundles on disk
  /// would contradict the DPDP "minimize retention" posture.
  static Future<void> delete(String id) async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'handoff_queue',
      columns: ['file_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final filePath = rows.first['file_path'] as String?;
      if (filePath != null && filePath.isNotEmpty) {
        try {
          final f = File(filePath);
          if (await f.exists()) await f.delete();
        } catch (_) {/* file may already be gone */}
      }
    }
    await db.delete('handoff_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// All queue items, newest first. UI filters by status locally (cheap,
  /// the queue is small in practice).
  static Future<List<HandoffQueueItem>> list() async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'handoff_queue',
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  /// How many items are still [HandoffStatus.pending] — never launched.
  /// Used by the home-screen Outbox badge.
  static Future<int> pendingCount() async {
    final db = await DatabaseService.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM handoff_queue WHERE status = ?',
      [HandoffStatus.pending.name],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  /// All pending items, oldest first — call-site decides whether to prompt
  /// the user to re-launch them when connectivity returns.
  static Future<List<HandoffQueueItem>> pending() async {
    final db = await DatabaseService.database;
    final rows = await db.query(
      'handoff_queue',
      where: 'status = ?',
      whereArgs: [HandoffStatus.pending.name],
      orderBy: 'created_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  /// Map a SQLite row (with encrypted PII columns) into the model.
  /// Decryption failures yield empty strings rather than crashing — matches
  /// the resilience pattern in [DatabaseService._safeDecrypt].
  static HandoffQueueItem _fromRow(Map<String, Object?> row) {
    return HandoffQueueItem(
      id: row['id'] as String,
      kind: HandoffQueueItem.kindFromName(row['kind'] as String?),
      payload: _safeDecrypt(row['payload_enc'] as String?) ?? '',
      recipient: _safeDecrypt(row['recipient_enc'] as String?),
      filePath: row['file_path'] as String?,
      fileHash: row['file_hash'] as String?,
      status: HandoffQueueItem.statusFromName(row['status'] as String?),
      attempts: (row['attempts'] as int?) ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastTriedAt: row['last_tried_at'] != null
          ? DateTime.tryParse(row['last_tried_at'] as String)
          : null,
      label: _safeDecrypt(row['label_enc'] as String?),
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

  /// Persist a FHIR bundle to the app's documents dir so it survives cache
  /// reclamation until the user either re-shares or deletes the queue item.
  /// Returns the absolute path.
  ///
  /// Kept in a subdirectory (`fhir_outbox/`) for tidiness; the filename
  /// pattern mirrors [HandoffService.shareFhirBundle] so an ASHA looking at
  /// the share sheet sees a consistent name.
  static Future<String> persistFhirBundle({
    required String bundleJson,
    required String bundleHash,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    final outboxDir = Directory(path.join(docs.path, 'fhir_outbox'));
    if (!await outboxDir.exists()) {
      await outboxDir.create(recursive: true);
    }
    final hashPrefix = bundleHash.length >= 8
        ? bundleHash.substring(0, 8)
        : bundleHash;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File(path.join(outboxDir.path, 'fhir_${hashPrefix}_$ts.json'));
    await file.writeAsString(bundleJson, flush: true);
    return file.path;
  }
}
