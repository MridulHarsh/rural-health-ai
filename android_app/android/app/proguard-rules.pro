# R8/ProGuard keep rules for the release APK.
#
# The rules below are about bundled plugin dependencies that reference
# classes from OPTIONAL companion artifacts we intentionally don't ship.
# Without a `-dontwarn`, R8 treats an unresolved reference as a hard
# error during minifyReleaseWithR8 and aborts the build.

# ── Google ML Kit Text Recognition ──
# `google_mlkit_text_recognition` references per-script recognizers
# (Chinese, Devanagari, Japanese, Korean) behind feature flags. We only
# use the default Latin recognizer for reading English-script
# prescription labels; pulling the other scripts' artifacts would add
# ~10 MB to the APK for no benefit on this app's target workflow.
# These `-dontwarn` lines tell R8 "it's fine, the references are
# deliberately unresolved" without actually keeping anything.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ── TFLite GPU delegate (unused) ──
# tflite_flutter pulls in GPU-delegate stubs even when we run on CPU.
# They reference classes not present in our cpu-only variant.
-dontwarn org.tensorflow.lite.gpu.**

# ── Play Core (split-install APIs) ──
# Flutter's base lint ships references to Play Core for deferred
# components, which we don't use in a standalone release APK.
-dontwarn com.google.android.play.core.**

# ─────────────────────────────────────────────────────────────────────
# -KEEP rules (below). These protect classes that R8 would otherwise
# obfuscate or strip, which would break them at runtime ONLY in release
# builds (debug skips R8). Every entry here corresponds to a library
# that uses reflection, JNI, or a dynamic class loader.
# ─────────────────────────────────────────────────────────────────────

# ── TFLite (tflite_flutter) ──
# The TFLite Java API crosses a JNI boundary; native code references
# Java class + method names as strings. Obfuscating them silently breaks
# Interpreter.run with opaque "method not found" crashes on real device,
# but passes on simulator where R8 isn't usually run.
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.support.** { *; }

# ── flutter_secure_storage ──
# Uses reflection to detect Keystore provider availability on older
# Android versions, and to fall through to EncryptedSharedPreferences
# on Android < 5.0. Keeping the plugin's public classes + members.
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }

# ── encrypt + pointycastle ──
# `encrypt` delegates to pointycastle's AES-GCM. PointyCastle registers
# provider classes via reflection (`java.security.Security.addProvider`)
# and looks them up by string name at decrypt time. Obfuscation breaks
# that lookup and decryptString silently returns the raw envelope.
# (We documented exactly this silent-failure mode in encryption_service.dart's
# debugPrint.)
-keep class org.pointycastle.** { *; }
-keep class org.bouncycastle.** { *; }
-dontwarn org.pointycastle.jce.provider.**
-dontwarn org.bouncycastle.jce.provider.**

# ── Google ML Kit TextRecognizer ──
# The recognizer's init path reads option-builder classes via reflection
# when no per-script options are passed. Keep the default Latin recognizer
# entry points; the other scripts are already covered by -dontwarn above.
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.** { *; }

# ── sqflite ──
# The Flutter sqflite plugin uses native SQLite through JNI; same obfuscation
# risk as TFLite.
-keep class io.flutter.plugins.sqflite.** { *; }

# ── PDF (pdf + printing) ──
# The pdf package uses reflection for font loading on the native side
# (pdfium binding). Without keeps, release APK can't generate the
# patient-summary PDF.
-keep class com.tekartik.sqflite.** { *; }
-keep class fr.cancerbero78.printing.** { *; }
-dontwarn fr.cancerbero78.printing.**

# ── speech_to_text ──
# Android speech recognizer intent wiring uses reflection on the Intent
# extras bag; keep the plugin surface.
-keep class com.csdcorp.speech_to_text.** { *; }
