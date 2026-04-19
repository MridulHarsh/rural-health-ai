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
