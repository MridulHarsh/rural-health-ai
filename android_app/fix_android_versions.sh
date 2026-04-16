#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Configure Rural Health AI for Android 6 (API 23) → Android 16 (API 36)
# Run from: ~/Downloads/rural_health_ai/android_app/
# ═══════════════════════════════════════════════════════════════

set -e
cd "$(dirname "$0")"

echo "📱 Configuring Android 6–16 support (API 23–36)..."
echo ""

# ─── 1. Install Android SDK Platform 36 ───
echo "  [1/4] Installing Android SDK Platform 36..."
ANDROID_SDK="$HOME/Library/Android/sdk"
if [ -d "$ANDROID_SDK" ]; then
  "$ANDROID_SDK/cmdline-tools/latest/bin/sdkmanager" "platforms;android-36" 2>/dev/null \
    || echo "    ⚠ Could not auto-install. Open Android Studio → SDK Manager → install API 36 manually."
else
  echo "    ⚠ Android SDK not found at default path. Install API 36 via Android Studio SDK Manager."
fi

# ─── 2. Update android/app/build.gradle ───
echo "  [2/4] Updating android/app/build.gradle..."
BUILD_GRADLE="android/app/build.gradle"

# Set compileSdk to 36
sed -i '' 's/compileSdk flutter\.compileSdkVersion/compileSdk 36/' "$BUILD_GRADLE"
sed -i '' 's/compileSdkVersion flutter\.compileSdkVersion/compileSdk 36/' "$BUILD_GRADLE"
sed -i '' 's/compileSdk [0-9]*/compileSdk 36/' "$BUILD_GRADLE"

# Set targetSdkVersion to 36
sed -i '' 's/targetSdkVersion flutter\.targetSdkVersion/targetSdkVersion 36/' "$BUILD_GRADLE"
sed -i '' 's/targetSdkVersion [0-9]*/targetSdkVersion 36/' "$BUILD_GRADLE"

# Ensure minSdkVersion is 23
sed -i '' 's/minSdkVersion [0-9]*/minSdkVersion 23/' "$BUILD_GRADLE"

echo "    ✓ compileSdk = 36"
echo "    ✓ targetSdkVersion = 36"
echo "    ✓ minSdkVersion = 23"

# ─── 3. Update AGP version for API 36 compatibility ───
echo "  [3/4] Updating Android Gradle Plugin..."
SETTINGS_GRADLE="android/settings.gradle"

# Update AGP from 7.x to 8.1.0 (minimum for reliable API 36 support)
sed -i '' 's/id "com.android.application" version "[^"]*"/id "com.android.application" version "8.1.0"/' "$SETTINGS_GRADLE"

# Update Kotlin version to match
sed -i '' 's/id "org.jetbrains.kotlin.android" version "[^"]*"/id "org.jetbrains.kotlin.android" version "1.9.22"/' "$SETTINGS_GRADLE"

echo "    ✓ AGP → 8.1.0"
echo "    ✓ Kotlin → 1.9.22"

# ─── 4. Update Gradle wrapper for AGP 8.x ───
echo "  [4/4] Updating Gradle wrapper..."
GRADLE_PROPS="android/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$GRADLE_PROPS" ]; then
  sed -i '' 's|distributionUrl=.*|distributionUrl=https\\://services.gradle.org/distributions/gradle-8.9-all.zip|' "$GRADLE_PROPS"
  echo "    ✓ Gradle → 8.9"
else
  echo "    ⚠ gradle-wrapper.properties not found. Run: cd android && ./gradlew wrapper --gradle-version 8.9"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Done! Your app now targets:"
echo "   • Minimum:  Android 6.0  (API 23)"
echo "   • Target:   Android 16   (API 36)"
echo "   • Compile:  Android 16   (API 36)"
echo ""
echo "Next steps:"
echo "   cd ~/Downloads/rural_health_ai/android_app"
echo "   flutter clean"
echo "   flutter pub get"
echo "   flutter run"
echo "═══════════════════════════════════════════════════════════"
