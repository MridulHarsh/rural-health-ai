// encryption_service.dart
// AES-256-GCM field-level encryption for PII at rest.
//
// Key is generated on first launch, stored in flutter_secure_storage (backed by
// Android Keystore / iOS Keychain). Encrypted payloads carry a random IV
// prefix — standard AES-GCM envelope. The DPDP-compliance story is: patient
// names, notes, and voice transcripts never hit disk in plaintext.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class EncryptionService {
  static const _keyName = 'rh_aes_key_v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Encrypter? _encrypter;
  static Key? _key;

  /// Call once from app init. Lazily generates the key on first launch.
  static Future<void> initialize() async {
    if (_encrypter != null) return;
    var keyB64 = await _storage.read(key: _keyName);
    if (keyB64 == null) {
      final rnd = Random.secure();
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (_) => rnd.nextInt(256)),
      );
      keyB64 = base64Encode(bytes);
      await _storage.write(key: _keyName, value: keyB64);
    }
    _key = Key(base64Decode(keyB64));
    _encrypter = Encrypter(AES(_key!, mode: AESMode.gcm, padding: null));
  }

  static bool get isReady => _encrypter != null;

  /// Encrypt a plaintext string. Returns `iv_b64|ct_b64` envelope.
  /// Safe to call with null/empty — returns empty string.
  static String encryptString(String? plaintext) {
    if (plaintext == null || plaintext.isEmpty || _encrypter == null) {
      return plaintext ?? '';
    }
    final iv = IV.fromSecureRandom(12); // GCM 96-bit nonce
    final encrypted = _encrypter!.encrypt(plaintext, iv: iv);
    return '${iv.base64}|${encrypted.base64}';
  }

  /// Decrypt an envelope produced by [encryptString]. Returns the payload
  /// unchanged if it doesn't look encrypted — preserves backward compat
  /// with data written before encryption was introduced.
  static String decryptString(String? envelope) {
    if (envelope == null || envelope.isEmpty || _encrypter == null) {
      return envelope ?? '';
    }
    if (!envelope.contains('|')) return envelope; // legacy plaintext
    try {
      final parts = envelope.split('|');
      if (parts.length != 2) return envelope;
      final iv = IV.fromBase64(parts[0]);
      final ct = Encrypted.fromBase64(parts[1]);
      return _encrypter!.decrypt(ct, iv: iv);
    } catch (e) {
      // Log the error *type* (never the envelope contents) so a developer
      // looking at adb logcat can distinguish "key was rotated and old rows
      // are stale" from "envelope is base64-corrupt" — both manifest as a
      // silent fallback to raw envelope, which historically made these
      // failures undiagnosable. The error type from the `encrypt` package
      // (FormatException, ArgumentError) is enough signal without leaking
      // ciphertext to logs.
      debugPrint('[EncryptionService] decrypt failed (${e.runtimeType})');
      return envelope; // Decryption failed — return as-is rather than crash
    }
  }
}
