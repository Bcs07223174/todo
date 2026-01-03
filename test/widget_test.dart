import 'package:flutter_test/flutter_test.dart';
import 'package:neon_task/main.dart';

void main() {
  testWidgets('Dashboard loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the dashboard title is present.
    expect(find.text('Dashboard'), findsOneWidget);
    
    // Check for chart titles/headings
    expect(find.text('Weekly Activity'), findsOneWidget);
    expect(find.text('Task Status'), findsOneWidget);
  });
}
