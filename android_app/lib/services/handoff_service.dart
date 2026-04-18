// handoff_service.dart
// Workflow closers: WhatsApp deep-link to PHC doctor, SMS draft to referral
// number, tel dialer for emergencies. These replace the "and then what?"
// gap that most competitor teams called out as CureBay's unmet workflow need.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class HandoffService {
  /// Share a patient summary to a PHC doctor via WhatsApp. Tries the WhatsApp
  /// app scheme first (opens the app directly), then falls back to wa.me URL
  /// which works even without the app installed (opens in browser).
  static Future<bool> sendToWhatsApp({
    required String message,
    String? phone,
    String? filePath,
  }) async {
    final encoded = Uri.encodeComponent(message);
    final num = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';

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
    final num = phone ?? '';
    final url = Platform.isIOS
        ? 'sms:$num&body=$encoded'
        : 'sms:$num?body=$encoded';
    return _tryLaunch(url);
  }

  /// Dial an emergency number (108 for ambulance in India).
  static Future<bool> dial(String phone) async {
    return _tryLaunch('tel:$phone');
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
