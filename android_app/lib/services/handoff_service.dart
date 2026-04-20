// handoff_service.dart
// Workflow closers: WhatsApp deep-link to PHC doctor, SMS draft to referral
// number, tel dialer for emergencies. These replace the "and then what?"
// gap that most competitor teams called out as CureBay's unmet workflow need.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

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
  /// <queries> block even when the app is installed, and the actual
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
      debugPrint('[HandoffService] launch error for $url: $e');
      return false;
    }
  }

  /// Default emergency number for India. Override per deployment region.
  static const String defaultEmergencyNumber = '108';
}
