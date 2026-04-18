// tts_service.dart
// Text-to-speech wrapper for voice-narrated results in the patient's language.
// Many ASHA patients cannot read — speaking the diagnosis + action steps aloud
// is a direct low-literacy win.

import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  static final TtsService _instance = TtsService._();
  factory TtsService() => _instance;
  TtsService._();

  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  /// Flutter-TTS locale mapping per our in-app language code.
  /// These codes work on Android where the corresponding TTS voice data is
  /// installed. English is the always-available fallback.
  static const Map<String, String> _localeForLang = {
    'en': 'en-IN',
    'hi': 'hi-IN',
    'ta': 'ta-IN',
    'te': 'te-IN',
    'ml': 'ml-IN',
    'kn': 'kn-IN',
    'bn': 'bn-IN',
    'mr': 'mr-IN',
    'gu': 'gu-IN',
    'or': 'or-IN',
    'pa': 'pa-IN',
    'as': 'as-IN',
  };

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setSpeechRate(0.45); // slower than default for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _initialized = true;
  }

  /// Speak [text] in the voice matching [langCode]. Falls back to English
  /// if the requested voice isn't installed on the device.
  Future<void> speak(String text, {String langCode = 'en'}) async {
    if (text.trim().isEmpty) return;
    await _init();
    final locale = _localeForLang[langCode] ?? 'en-IN';
    try {
      await _tts.setLanguage(locale);
    } catch (_) {
      await _tts.setLanguage('en-IN');
    }
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    if (!_initialized) return;
    await _tts.stop();
  }
}
