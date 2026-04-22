// handoff_queue_service_test.dart
// Unit-level lifecycle test for the Outbox queue. Uses sqflite_common_ffi
// for an in-memory database (no device / emulator needed) and plants a
// deterministic AES key via EncryptionService.initializeForTests so PII
// round-trips correctly without flutter_secure_storage.
//
// Coverage: enqueue → pendingCount → pending() filter → markLaunched →
// list() ordering → delete(). We don't exercise the HandoffService
// launch wrappers because those invoke platform channels (url_launcher,
// share_plus) that aren't available in pure Dart tests.
//
// Feature E2 in the NeuCure roadmap.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:rural_health_ai/models/handoff_queue_item.dart';
import 'package:rural_health_ai/services/database_service.dart';
import 'package:rural_health_ai/services/encryption_service.dart';
import 'package:rural_health_ai/services/handoff_queue_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database testDb;

  setUpAll(() {
    // Route sqflite calls to the ffi (desktop/test) implementation.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Fresh in-memory database + schema per test. `:memory:` alone can
    // return the same handle under some factory impls; we make the path
    // unique per test to guarantee isolation.
    testDb = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
      ),
    );
    await DatabaseService.createHandoffQueueTable(testDb);
    DatabaseService.debugOverrideDatabase(testDb);

    // Plant a 32-byte zero key — deterministic so ciphertext is
    // reproducible across runs. Production uses a Keystore-backed random
    // key; the test cares that round-trips work, not that the key itself
    // is secret.
    EncryptionService.initializeForTests(Uint8List(32));
  });

  tearDown(() async {
    DatabaseService.debugOverrideDatabase(null);
    await testDb.close();
  });

  group('HandoffQueueService — lifecycle', () {
    test('enqueue starts an item as pending + increments pendingCount',
        () async {
      expect(await HandoffQueueService.pendingCount(), 0);

      final id = await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: 'Patient Anita — suspected sepsis — 2yo',
        recipient: '+919876543210',
        label: 'Referral — Anita',
      );
      expect(id, isNotEmpty);
      expect(await HandoffQueueService.pendingCount(), 1);

      final pending = await HandoffQueueService.pending();
      expect(pending, hasLength(1));
      expect(pending.first.kind, HandoffKind.whatsapp);
      expect(pending.first.status, HandoffStatus.pending);
    });

    test('enqueue roundtrips PII through AES-GCM encryption', () async {
      const payload = 'Patient Ravi — suspected TB — cough 3wk';
      const phone = '+918765432109';
      const label = 'Referral — Ravi TB';
      await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: payload,
        recipient: phone,
        label: label,
      );

      final list = await HandoffQueueService.list();
      expect(list, hasLength(1));
      expect(list.first.payload, payload,
          reason: 'Payload must decrypt back to original plaintext.');
      expect(list.first.recipient, phone);
      expect(list.first.label, label);
    });

    test('markLaunched transitions pending → launched, decrements pending',
        () async {
      final id = await HandoffQueueService.enqueue(
        kind: HandoffKind.sms,
        payload: 'EMERGENCY — transport now',
        recipient: '+911234567890',
      );
      expect(await HandoffQueueService.pendingCount(), 1);

      await HandoffQueueService.markLaunched(id);

      expect(await HandoffQueueService.pendingCount(), 0,
          reason: 'Launched items no longer count as pending.');

      final all = await HandoffQueueService.list();
      expect(all, hasLength(1));
      expect(all.first.status, HandoffStatus.launched);
      expect(all.first.attempts, greaterThanOrEqualTo(1));
      expect(all.first.lastTriedAt, isNotNull);
    });

    test('delete removes the item from the queue', () async {
      final id = await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: 'draft message',
      );
      expect((await HandoffQueueService.list()), hasLength(1));

      await HandoffQueueService.delete(id);

      expect((await HandoffQueueService.list()), isEmpty);
      expect(await HandoffQueueService.pendingCount(), 0);
    });

    test('list orders newest-first', () async {
      final a = await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: 'first',
      );
      // Small delay so created_at timestamps differ.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: 'second',
      );

      final list = await HandoffQueueService.list();
      expect(list.map((i) => i.id).toList(), [b, a],
          reason: 'list() must be newest-first by created_at.');
    });

    test('enqueue with status=launched records attempt + timestamp upfront',
        () async {
      // Online path: HandoffService enqueues an item as already-launched
      // immediately after the composer opened, so the audit row skips the
      // pending state.
      await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: 'already sent',
        status: HandoffStatus.launched,
      );
      final list = await HandoffQueueService.list();
      expect(list, hasLength(1));
      expect(list.first.status, HandoffStatus.launched);
      expect(list.first.attempts, 1);
      expect(list.first.lastTriedAt, isNotNull);
      expect(await HandoffQueueService.pendingCount(), 0);
    });
  });

  group('HandoffQueueItem — model helpers', () {
    test('kindFromName / statusFromName round-trip', () {
      expect(HandoffQueueItem.kindFromName('whatsapp'),
          HandoffKind.whatsapp);
      expect(HandoffQueueItem.kindFromName('sms'), HandoffKind.sms);
      expect(HandoffQueueItem.kindFromName('fhirShare'),
          HandoffKind.fhirShare);
      expect(HandoffQueueItem.kindFromName(null), HandoffKind.whatsapp,
          reason: 'Fallback to whatsapp for unknown / null values.');

      expect(HandoffQueueItem.statusFromName('pending'),
          HandoffStatus.pending);
      expect(HandoffQueueItem.statusFromName('launched'),
          HandoffStatus.launched);
      expect(HandoffQueueItem.statusFromName(null),
          HandoffStatus.pending);
    });

    test('copyWith preserves unchanged fields', () {
      final item = HandoffQueueItem(
        id: 'abc',
        kind: HandoffKind.fhirShare,
        payload: 'body',
        recipient: 'somebody@phc.in',
        label: 'FHIR — foo',
      );
      final updated = item.copyWith(
        status: HandoffStatus.launched,
        attempts: 2,
      );
      expect(updated.id, 'abc');
      expect(updated.kind, HandoffKind.fhirShare);
      expect(updated.payload, 'body');
      expect(updated.recipient, 'somebody@phc.in');
      expect(updated.label, 'FHIR — foo');
      expect(updated.status, HandoffStatus.launched);
      expect(updated.attempts, 2);
    });
  });
}
