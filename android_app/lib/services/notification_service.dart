// notification_service.dart
// Thin wrapper around [flutter_local_notifications] for the one purpose we
// use it: alerting the ASHA when connectivity returns AND the Outbox has
// pending items so she can open the composer right now, without hunting
// for the tile.
//
// Feature A1-full in the NeuCure roadmap.
//
// Privacy posture: all notifications are local — there is no push provider,
// no FCM, no remote sender. The only permission added is POST_NOTIFICATIONS
// (Android 13+). Messages never contain patient identifiers, only a count —
// decryption + re-launch happens only when the user explicitly opens Outbox.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Android notification channel for the Outbox reminder. Single-purpose
  /// so the user can disable this specific channel in system settings
  /// without killing all app notifications (there aren't any others, but
  /// future-proofing a dedicated channel costs nothing).
  static const _channelId = 'rh_outbox_reminder';
  static const _channelName = 'Outbox reminders';
  static const _channelDescription =
      'Tells you when signal returns and Outbox has pending messages.';

  /// Persistent notification id — we always overwrite the same one. One
  /// notification at a time regardless of how many items are pending.
  static const _notificationId = 1001;

  static bool _initialized = false;

  /// One-time setup. Accepts an optional [onOpenOutbox] callback invoked
  /// when the user taps the notification — called inside the plugin's
  /// background isolate, so keep work minimal (the caller navigates via
  /// the top-level navigator key).
  static Future<void> initialize({
    VoidCallback? onOpenOutbox,
  }) async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (resp) {
        // Only our channel sends notifications, so any tap routes to Outbox.
        onOpenOutbox?.call();
      },
    );
    // Create the channel explicitly so we can pick importance. (On Android
    // this is a no-op if the channel already exists.)
    final android13 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );
    _initialized = true;
  }

  /// Request POST_NOTIFICATIONS on Android 13+. Safe no-op on older APIs
  /// (returns true on the plugin's internal fallback path).
  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return (await android?.requestNotificationsPermission()) ?? true;
    } catch (e) {
      debugPrint(
          '[NotificationService] requestPermission error: ${e.runtimeType}');
      return false;
    }
  }

  /// Show the "Signal restored, Outbox has N pending" alert. Call when
  /// transitioning offline→online AND pendingCount > 0. No-op on null/0.
  static Future<void> showOutboxPending({
    required int pendingCount,
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    if (pendingCount <= 0) return;
    try {
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            // Make it dismissible — the user may want to send via other
            // means. Not an ongoing/persistent notification.
            ongoing: false,
            autoCancel: true,
          ),
        ),
      );
    } catch (e) {
      // Never log the body — it's generic, but logging it repeatedly in
      // release builds is noise.
      debugPrint(
          '[NotificationService] show error: ${e.runtimeType}');
    }
  }

  /// Remove the Outbox notification (e.g. when the user clears the queue).
  static Future<void> cancelOutbox() async {
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (_) {}
  }
}
