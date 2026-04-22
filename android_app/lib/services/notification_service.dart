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

  /// Was the current app process launched by a notification tap? Set during
  /// [initialize] if `getNotificationAppLaunchDetails` reports a pending tap
  /// that delivered before the Flutter engine was ready (cold start).
  ///
  /// Without this, cold-start taps silently no-op: the plugin delivers them
  /// before `MaterialApp.build` runs, so [navigatorKey.currentState] is null
  /// and the onDidReceiveNotificationResponse callback's `pushNamed` is a
  /// dead write. The caller inspects this flag after `runApp` and schedules
  /// a post-frame navigation instead.
  static bool _launchedFromTap = false;

  static bool get launchedFromNotificationTap => _launchedFromTap;

  /// One-time setup. Accepts optional [onOpenOutbox] callback invoked
  /// when the user taps a notification WHILE the app is running. Cold-start
  /// taps set [launchedFromNotificationTap] instead; the caller checks that
  /// flag after initialization and routes itself once the navigator is
  /// ready. The [channelName] / [channelDescription] parameters let the
  /// caller pass locale-appropriate strings (Android caches channel names
  /// at creation time, so we can't reactively re-localize — best effort is
  /// to use the user's current locale on first creation).
  static Future<void> initialize({
    VoidCallback? onOpenOutbox,
    String channelName = _channelName,
    String channelDescription = _channelDescription,
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

    // Check for a cold-start launch tap. On cold start the plugin delivers
    // the tap before the Dart side is ready, so we read it here and let the
    // caller act on it once the navigator is live.
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp ?? false) {
        _launchedFromTap = true;
      }
    } catch (_) {
      // No-op — absence of launch details is harmless.
    }

    // Create the channel explicitly so we can pick importance. (On Android
    // this is a no-op if the channel already exists; first creation wins on
    // the name + description, per platform spec.)
    final android13 = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android13?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId,
        channelName,
        description: channelDescription,
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
