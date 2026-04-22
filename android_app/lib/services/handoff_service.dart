// handoff_service.dart
// Workflow closers: WhatsApp deep-link to PHC doctor, SMS draft to referral
// number, tel dialer for emergencies. These replace the "and then what?"
// gap that most competitor teams called out as CureBay's unmet workflow need.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/handoff_queue_item.dart';
import 'connectivity_service.dart';
import 'handoff_queue_service.dart';

/// Outcome of a send-or-queue attempt. `launched` means the system composer
/// opened (WhatsApp / SMS / share sheet); `queued` means we saved the intent
/// to the Outbox because the device reported offline. `failed` is reserved
/// for hard errors (launch exception) — note that user-cancellation from
/// the share sheet counts as `launched`, not `failed`.
enum HandoffResult { launched, queued, failed }

class HandoffService {
  /// Short-code emergency numbers that must ALWAYS be dialable, regardless
  /// of the 7-digit minimum below. India uses 108 (ambulance), 102 (medical),
  /// 112 (unified), 100 (police), 101 (fire), 104 (state health helplines),
  /// 1098 (child helpline). Without this allowlist, the default 7-15-digit
  /// sanitizer would silently reject `dial('108')` — a patient-safety
  /// regression caught in the second audit round.
  static const Set<String> _emergencyShortCodes = {
    '100', '101', '102', '104', '108', '112', '1098',
  };

  /// Normalize a user-supplied phone number to digits-only. Returns null if
  /// the result is empty or clearly not a dialable number (too short/long).
  /// Indian mobile numbers are 10 digits; with country code they're 12. We
  /// accept 7–15 digits to be permissive across regions while rejecting
  /// obvious garbage ("hello", "n/a") before it reaches launchUrl and
  /// confuses downstream apps. Emergency short codes bypass the length
  /// minimum via [_emergencyShortCodes].
  static String? _sanitizePhone(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (_emergencyShortCodes.contains(digits)) return digits;
    if (digits.length < 7 || digits.length > 15) return null;
    return digits;
  }

  /// Share a patient summary to a PHC doctor via WhatsApp. Tries the WhatsApp
  /// app scheme first (opens the app directly), then falls back to wa.me URL
  /// which works even without the app installed (opens in browser).
  static Future<bool> sendToWhatsApp({
    required String message,
    String? phone,
    String? filePath,
  }) async {
    final encoded = Uri.encodeComponent(message);
    final num = _sanitizePhone(phone) ?? '';

    // 1. Try native WhatsApp scheme (opens app directly on Android/iOS).
    final nativeUrl = num.isEmpty
        ? 'whatsapp://send?text=$encoded'
        : 'whatsapp://send?phone=$num&text=$encoded';
    if (await _tryLaunch(nativeUrl, checkCanLaunch: false)) return true;

    // 2. Fall back to wa.me universal link (browser or app via App Links).
    final waUrl = num.isEmpty
        ? 'https://wa.me/?text=$encoded'
        : 'https://wa.me/$num?text=$encoded';
    return _tryLaunch(waUrl, checkCanLaunch: false);
  }

  /// Open the SMS composer pre-filled with the message and optional recipient.
  /// Used by the red-flag auto-SMS draft — ASHA taps once to send.
  static Future<bool> draftSms({required String message, String? phone}) async {
    final encoded = Uri.encodeComponent(message);
    final num = _sanitizePhone(phone) ?? '';
    final url = Platform.isIOS
        ? 'sms:$num&body=$encoded'
        : 'sms:$num?body=$encoded';
    return _tryLaunch(url);
  }

  /// Dial an emergency number (108 for ambulance in India).
  static Future<bool> dial(String phone) async {
    final num = _sanitizePhone(phone);
    if (num == null) return false;
    return _tryLaunch('tel:$num');
  }

  /// Attempt to launch [url] with [LaunchMode.externalApplication]. By
  /// default we skip the [canLaunchUrl] precheck — on Android 11+ it
  /// returns false for any package not declared in the manifest's
  /// `<queries>` block even when the app is installed, and the actual
  /// launch often succeeds anyway. We only mark a launch failed when
  /// [launchUrl] itself throws or returns false.
  static Future<bool> _tryLaunch(String url, {bool checkCanLaunch = false}) async {
    try {
      final uri = Uri.parse(url);
      if (checkCanLaunch) {
        final can = await canLaunchUrl(uri);
        if (!can) return false;
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      // Do NOT log the full URL — WhatsApp / SMS handoffs URL-encode the
      // patient summary (name, conditions, notes) into the query string,
      // and debugPrint is NOT stripped in release builds. Log only the
      // scheme and the exception type.
      final scheme = Uri.tryParse(url)?.scheme ?? 'unknown';
      debugPrint('[HandoffService] launch error (scheme=$scheme): ${e.runtimeType}');
      return false;
    }
  }

  /// Default emergency number for India. Override per deployment region.
  static const String defaultEmergencyNumber = '108';

  /// Write the FHIR bundle JSON to a short-lived file in the app cache dir
  /// and hand it off via the platform share sheet. The ASHA can then pick
  /// WhatsApp / Gmail / Drive / Bluetooth — whatever the PHC physician uses.
  ///
  /// The file is written to the app's *cache* directory (not documents)
  /// because it's a share-in-flight artefact, not durable state. Android
  /// reclaims cache aggressively under storage pressure, which is the
  /// right behavior: if the share didn't happen, the patient data doesn't
  /// linger on disk.
  ///
  /// The filename is `fhir_<hash-prefix>_<timestamp>.json` — the hash
  /// prefix makes dedup obvious to a receiver who gets two copies, and the
  /// timestamp prevents collisions when the same bundle is re-shared.
  ///
  /// Returns true on a clean share-sheet return, false on any launch
  /// error. `share_plus` swallows user-cancellation as a success — that's
  /// correct: the ASHA chose not to send, which isn't a failure.
  static Future<bool> shareFhirBundle({
    required String bundleJson,
    required String bundleHash,
    String? subject,
    String? messageBody,
  }) async {
    try {
      final dir = await getTemporaryDirectory();
      final hashPrefix = bundleHash.length >= 8
          ? bundleHash.substring(0, 8)
          : bundleHash;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/fhir_${hashPrefix}_$ts.json');
      await file.writeAsString(bundleJson, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/fhir+json')],
          subject: subject ?? 'Clinical Assessment Summary (FHIR Bundle)',
          text: messageBody,
        ),
      );
      return true;
    } catch (e) {
      // Never log the bundle — it contains patient name + conditions.
      debugPrint('[HandoffService] FHIR share error: ${e.runtimeType}');
      return false;
    }
  }

  /// Share the de-identified analytics JSONL via the platform share sheet.
  /// Used from Settings → "Export my anonymized contributions" so the ASHA
  /// can send the rolling record to the NeuCure research inbox manually
  /// (explicit, visible, user-initiated — no silent network upload).
  static Future<bool> shareAnalyticsFile({
    required String filePath,
    String? messageBody,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath, mimeType: 'application/x-ndjson')],
          subject: 'De-identified outcome records',
          text: messageBody,
        ),
      );
      return true;
    } catch (e) {
      debugPrint(
          '[HandoffService] analytics share error: ${e.runtimeType}');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Outbox-aware wrappers
  //
  // Every send-or-queue call creates a row in `handoff_queue` so the ASHA
  // has a durable record of the intent regardless of outcome. Online path:
  // the row is marked launched right after the composer opens. Offline path:
  // the row stays [HandoffStatus.pending] until the user reopens it from
  // the Outbox screen.
  // ──────────────────────────────────────────────────────────────

  /// Online → launch WhatsApp composer + stash a `launched` audit row.
  /// Offline → save only a `pending` row, no launch attempt (WhatsApp will
  /// report "no internet" if we open it dry, which confuses the ASHA more
  /// than a clear "saved to Outbox" message).
  static Future<HandoffResult> sendWhatsAppOrQueue({
    required String message,
    String? phone,
    String? label,
  }) async {
    final online = await ConnectivityService.refresh();
    if (!online) {
      await HandoffQueueService.enqueue(
        kind: HandoffKind.whatsapp,
        payload: message,
        recipient: phone,
        label: label,
      );
      return HandoffResult.queued;
    }
    final id = await HandoffQueueService.enqueue(
      kind: HandoffKind.whatsapp,
      payload: message,
      recipient: phone,
      label: label,
    );
    final ok = await sendToWhatsApp(message: message, phone: phone);
    if (ok) {
      await HandoffQueueService.markLaunched(id);
      return HandoffResult.launched;
    }
    return HandoffResult.failed;
  }

  /// Online → launch SMS composer pre-filled + stash a `launched` audit row.
  /// Offline → save only a `pending` row. SMS at the platform level does
  /// queue when no signal, so offline-launch would actually work — but we
  /// still defer because the ASHA might want to edit or re-target before
  /// signal returns, and launching blindly burns the draft.
  static Future<HandoffResult> draftSmsOrQueue({
    required String message,
    String? phone,
    String? label,
  }) async {
    final online = await ConnectivityService.refresh();
    if (!online) {
      await HandoffQueueService.enqueue(
        kind: HandoffKind.sms,
        payload: message,
        recipient: phone,
        label: label,
      );
      return HandoffResult.queued;
    }
    final id = await HandoffQueueService.enqueue(
      kind: HandoffKind.sms,
      payload: message,
      recipient: phone,
      label: label,
    );
    final ok = await draftSms(message: message, phone: phone);
    if (ok) {
      await HandoffQueueService.markLaunched(id);
      return HandoffResult.launched;
    }
    return HandoffResult.failed;
  }

  /// Online → write bundle + launch share sheet + stash a `launched` audit
  /// row.
  /// Offline → pin the bundle to app documents dir (not cache) and save a
  /// `pending` row; the Outbox can re-launch later without rebuilding the
  /// bundle.
  static Future<HandoffResult> shareFhirOrQueue({
    required String bundleJson,
    required String bundleHash,
    String? subject,
    String? messageBody,
    String? label,
  }) async {
    final online = await ConnectivityService.refresh();
    if (!online) {
      final persistedPath = await HandoffQueueService.persistFhirBundle(
        bundleJson: bundleJson,
        bundleHash: bundleHash,
      );
      await HandoffQueueService.enqueue(
        kind: HandoffKind.fhirShare,
        payload: messageBody ?? '',
        filePath: persistedPath,
        fileHash: bundleHash,
        label: label,
      );
      return HandoffResult.queued;
    }
    // Pin the bundle even on the online path so the Outbox can re-share it
    // later without rebuilding. File cleanup happens via
    // [HandoffQueueService.delete] when the user dismisses the queue item.
    final persistedPath = await HandoffQueueService.persistFhirBundle(
      bundleJson: bundleJson,
      bundleHash: bundleHash,
    );
    final id = await HandoffQueueService.enqueue(
      kind: HandoffKind.fhirShare,
      payload: messageBody ?? '',
      filePath: persistedPath,
      fileHash: bundleHash,
      label: label,
    );
    final ok = await _shareFileWithShareSheet(
      filePath: persistedPath,
      mimeType: 'application/fhir+json',
      subject: subject ?? 'Clinical Assessment Summary (FHIR Bundle)',
      text: messageBody,
    );
    if (ok) {
      await HandoffQueueService.markLaunched(id);
      return HandoffResult.launched;
    }
    return HandoffResult.failed;
  }

  /// Re-launch a queued item from the Outbox screen. Returns true on a
  /// successful composer launch; the caller marks the item as launched.
  /// For fhirShare items, the backing file must still exist on disk.
  static Future<bool> retryQueueItem(HandoffQueueItem item) async {
    switch (item.kind) {
      case HandoffKind.whatsapp:
        return sendToWhatsApp(
          message: item.payload,
          phone: item.recipient,
        );
      case HandoffKind.sms:
        return draftSms(message: item.payload, phone: item.recipient);
      case HandoffKind.fhirShare:
        if (item.filePath == null) return false;
        final f = File(item.filePath!);
        if (!await f.exists()) return false;
        return _shareFileWithShareSheet(
          filePath: item.filePath!,
          mimeType: 'application/fhir+json',
          subject: 'Clinical Assessment Summary (FHIR Bundle)',
          text: item.payload.isEmpty ? null : item.payload,
        );
    }
  }

  /// Internal helper to avoid re-writing the share_plus boilerplate in both
  /// [shareFhirBundle] and [shareFhirOrQueue] / [retryQueueItem].
  static Future<bool> _shareFileWithShareSheet({
    required String filePath,
    required String mimeType,
    String? subject,
    String? text,
  }) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath, mimeType: mimeType)],
          subject: subject,
          text: text,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[HandoffService] share error: ${e.runtimeType}');
      return false;
    }
  }
}
