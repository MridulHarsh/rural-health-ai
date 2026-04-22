// connectivity_service.dart
// Thin wrapper around `connectivity_plus` that exposes a boolean "is any
// transport up right now?" answer plus a broadcast stream of changes. The
// rest of the app only cares about the binary (not the specific transport
// medium), so the raw list-of-results is normalised here.
//
// Drives the Outbox (handoff queue): when the ASHA taps "Send to PHC" we
// consult [isOnline] to decide between launching WhatsApp/SMS immediately
// vs. saving the intent to the queue for later re-launch.

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();

  /// Broadcast stream of on/off transitions. Multiple listeners (home badge,
  /// outbox screen, etc.) subscribe independently.
  static final StreamController<bool> _controller =
      StreamController<bool>.broadcast();

  static StreamSubscription<List<ConnectivityResult>>? _sub;
  static bool _lastKnown = false;
  static bool _started = false;

  /// Begin listening to transport-level changes. Safe to call multiple times —
  /// subsequent calls are no-ops.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final current = await _connectivity.checkConnectivity();
      _lastKnown = _hasAny(current);
    } catch (_) {
      // Graceful degrade — platform channel may not be ready on very early
      // boot. Assume offline until proven otherwise.
      _lastKnown = false;
    }
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final now = _hasAny(results);
      if (now != _lastKnown) {
        _lastKnown = now;
        _controller.add(now);
      }
    });
  }

  /// Last observed state. Cheap synchronous read — use this in UI builders.
  static bool get isOnline => _lastKnown;

  /// Force a fresh poll. Called from screens that want the current answer
  /// without waiting on the stream.
  static Future<bool> refresh() async {
    try {
      final current = await _connectivity.checkConnectivity();
      _lastKnown = _hasAny(current);
    } catch (_) {
      _lastKnown = false;
    }
    return _lastKnown;
  }

  /// Cancel the underlying transport-change subscription. Only used by the
  /// top-level app dispose path; normal operation leaves the listener alive
  /// for the whole process lifetime.
  static Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _started = false;
  }

  /// Stream of on/off transitions. Emits the new boolean only when state
  /// actually flips — no duplicates.
  static Stream<bool> get onChange => _controller.stream;

  /// A "connected" transport exists if at least one result is anything other
  /// than [ConnectivityResult.none]. We deliberately do NOT verify actual
  /// internet reachability — that would require an outbound ping, which
  /// contradicts the offline-first posture of the app.
  static bool _hasAny(List<ConnectivityResult> results) {
    for (final r in results) {
      if (r != ConnectivityResult.none) return true;
    }
    return false;
  }
}
