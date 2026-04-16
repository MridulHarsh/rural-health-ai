import 'package:flutter_test/flutter_test.dart';
import 'package:rural_health_ai/app.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const RuralHealthApp());
    // Verify the splash or home screen renders
    expect(find.text('Rural Health AI'), findsOneWidget);
  });
}
