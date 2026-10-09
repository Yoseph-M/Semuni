// semuni basic smoke test.
//
// Verifies the application launches without errors.
// Full widget tests will be added as features are built in later phases.

import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/app.dart';

void main() {
  testWidgets('semuni app launches smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SmuniApp());
    // The app should render the login screen without errors.
    expect(find.text('semuni'), findsWidgets);
  });
}
