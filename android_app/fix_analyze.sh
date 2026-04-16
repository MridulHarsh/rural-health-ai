#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# Fix all 25 flutter analyze issues for Rural Health AI
# Run from: ~/Downloads/rural_health_ai/android_app/
# Usage:  chmod +x fix_analyze.sh && ./fix_analyze.sh
# ═══════════════════════════════════════════════════════════════

set -e
cd "$(dirname "$0")"

echo "🔧 Fixing flutter analyze issues..."
echo ""

# ─── 1. app.dart: Remove unused import (results_screen.dart) ───
echo "  [1/7] Fixing lib/app.dart — unused import..."
sed -i '' "/^import 'screens\/results_screen.dart';$/d" lib/app.dart

# ─── 2. app.dart: Remove unused variables warningAmber, safeGreen ───
echo "  [2/7] Fixing lib/app.dart — unused variables..."
sed -i '' '/const Color warningAmber/d' lib/app.dart
sed -i '' '/const Color safeGreen/d' lib/app.dart

# ─── 3. home_screen.dart: Remove unused variable 'size' ───
echo "  [3/7] Fixing lib/screens/home_screen.dart — unused variable..."
sed -i '' '/final size = MediaQuery\.of(context)\.size;/d' lib/screens/home_screen.dart

# ─── 4. Replace ALL .withOpacity() → .withValues(alpha:) across all files ───
echo "  [4/7] Fixing deprecated .withOpacity() → .withValues(alpha:) ..."

FILES=(
  "lib/app.dart"
  "lib/screens/assessment_screen.dart"
  "lib/screens/history_screen.dart"
  "lib/screens/home_screen.dart"
  "lib/screens/results_screen.dart"
  "lib/screens/settings_screen.dart"
)

for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then
    # Replace .withOpacity(X) with .withValues(alpha: X)
    sed -i '' 's/\.withOpacity(\([^)]*\))/.withValues(alpha: \1)/g' "$f"
    echo "    ✓ $f"
  fi
done

# ─── 5. database_service.dart: Fix 'path' import ───
echo "  [5/7] Fixing lib/services/database_service.dart — path import..."
# Replace the bare 'path' package import with path_provider-compatible approach
sed -i '' "s|import 'package:path/path.dart';|import 'package:sqflite/sqflite.dart' show getDatabasesPath;\nimport 'package:path/path.dart' as p;|" lib/services/database_service.dart

# Check if 'path' is in pubspec.yaml dependencies, add if missing
if ! grep -q "^  path:" pubspec.yaml 2>/dev/null; then
  echo "    Adding 'path' dependency to pubspec.yaml..."
  sed -i '' '/^  sqflite:/a\
  path: ^1.9.0
' pubspec.yaml
fi

# ─── 6. widget_test.dart: Fix MyApp → RuralHealthApp ───
echo "  [6/7] Fixing test/widget_test.dart..."
if [ -f "test/widget_test.dart" ]; then
  cat > test/widget_test.dart << 'DART'
import 'package:flutter_test/flutter_test.dart';
import 'package:rural_health_ai/app.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const RuralHealthApp());
    // Verify the splash or home screen renders
    expect(find.text('Rural Health AI'), findsOneWidget);
  });
}
DART
  echo "    ✓ test/widget_test.dart"
fi

# ─── 7. Run flutter pub get to pick up any dependency changes ───
echo "  [7/7] Running flutter pub get..."
flutter pub get 2>/dev/null || echo "    ⚠ flutter pub get skipped (run manually if needed)"

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ All 25 issues fixed! Run 'flutter analyze' to verify."
echo "═══════════════════════════════════════════════════════════"
