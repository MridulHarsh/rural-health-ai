// emergency_service.dart
// Emergency alarm on red-flag trigger: vibration pattern + pre-drafted SMS.
// Mirrors NirogPath's "alarm + flash + SMS to PHC" bundle from their deck.

import 'package:vibration/vibration.dart';

class EmergencyService {
  /// Three-burst vibration to get the health worker's attention when a
  /// life-threatening red flag fires. Gracefully no-ops on devices without
  /// a vibrator.
  static Future<void> triggerAlarm() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;
      // Pattern: [wait, vibrate, wait, vibrate, ...] in ms
      await Vibration.vibrate(
        pattern: [0, 400, 200, 400, 200, 400],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } catch (_) {
      // Some devices throw PlatformException for patterns; fall back
      try {
        await Vibration.vibrate(duration: 800);
      } catch (_) {}
    }
  }

  static Future<void> cancel() async {
    try {
      await Vibration.cancel();
    } catch (_) {}
  }
}
