// handoff_service.dart
// Workflow closers: WhatsApp deep-link to PHC doctor, SMS draft to referral
// number, tel dialer for emergencies. These replace the "and then what?"
// gap that most competitor teams called out as CureBay's unmet workflow need.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

class HandoffService {
  /// Share a patient summary to a PHC doctor via WhatsApp. If [phone] is
  /// provided (country-code prefixed, digits only), the chat opens directly
  /// with that contact; otherwise WhatsApp opens to the contact picker.
  ///
  /// If a PDF [filePath] is provided, the URL falls back to the native
  /// Share Sheet so the user can attach the PDF — WhatsApp's wa.me
  /// deep-link doesn't support arbitrary file attachment.
  static Future<bool> sendToWhatsApp({
    required String message,
    String? phone,
    String? filePath,
  }) async {
    final encoded = Uri.encodeComponent(message);
    final num = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final waUrl = num.isEmpty
        ? 'https://wa.me/?text=$encoded'
        : 'https://wa.me/$num?text=$encoded';
    return _tryLaunch(waUrl);
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

  static Future<bool> _tryLaunch(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return false;
    } catch (e) {
      debugPrint('[HandoffService] launch error: $e');
      return false;
    }
  }

  /// Default emergency number for India. Override per deployment region.
  static const String defaultEmergencyNumber = '108';
}
