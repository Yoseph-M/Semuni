import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/app.dart';

void main() {
  group('Driver Login Widget & Flow Tests', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.implicitView?.physicalSize = const Size(
        1080,
        2400,
      );
      binding.platformDispatcher.implicitView?.devicePixelRatio = 2.75;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.implicitView?.resetPhysicalSize();
      binding.platformDispatcher.implicitView?.resetDevicePixelRatio();
    });

    testWidgets('1 & 2. Driver role selection and form rendering', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      // Initially passenger is selected
      expect(find.text('Passenger Account'), findsOneWidget);

      // 1. Select Driver role
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      // 2. Driver login screen/form renders correctly with driver context
      expect(find.text('Driver Account'), findsOneWidget);
      expect(
        find.text(
          'Sign in to manage your assigned taxi routes and track today’s earnings.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Demo driver: abel  |  password: password'),
        findsOneWidget,
      );

      // 3 & 4. Username and Password fields exist
      expect(find.widgetWithText(TextFormField, 'Username'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets('5. Password visibility toggle works in driver mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      // Switch to driver
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      final passwordFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Password',
      );
      expect(passwordFinder, findsOneWidget);

      // Initially obscured
      TextField passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isTrue);

      // Tap show password
      final showBtn = find.byTooltip('Show password');
      await tester.ensureVisible(showBtn);
      await tester.tap(showBtn);
      await tester.pumpAndSettle();

      passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isFalse);

      // Tap hide password
      final hideBtn = find.byTooltip('Hide password');
      await tester.ensureVisible(hideBtn);
      await tester.tap(hideBtn);
      await tester.pumpAndSettle();

      passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isTrue);
    });

    testWidgets(
      '6 & 7. Empty username and password validation in driver mode',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SmuniApp());
        await tester.pumpAndSettle();

        // Switch to driver
        await tester.tap(find.text('Driver'));
        await tester.pumpAndSettle();

        // Tap login without typing anything
        final loginBtn = find.text('Login');
        await tester.ensureVisible(loginBtn);
        await tester.tap(loginBtn);
        await tester.pumpAndSettle();

        // 6 & 7. Validation errors appear
        expect(find.text('Please enter your username'), findsOneWidget);
        expect(find.text('Please enter your password'), findsOneWidget);
      },
    );

    testWidgets('8. Invalid driver credentials show human-friendly error', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      // Switch to driver
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      final usernameField = find.widgetWithText(TextFormField, 'Username');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final loginBtn = find.text('Login');

      await tester.enterText(usernameField, 'wrongdriver');
      await tester.enterText(passwordField, 'wrongpass');

      await tester.ensureVisible(loginBtn);
      await tester.tap(loginBtn);

      // Loading indicator appears
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 8. Error banner displayed
      expect(
        find.text('Invalid username or password. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets(
      '9 & 10. Valid driver credentials navigate to Driver Home placeholder',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SmuniApp());
        await tester.pumpAndSettle();

        // Switch to driver
        await tester.tap(find.text('Driver'));
        await tester.pumpAndSettle();

        final usernameField = find.widgetWithText(TextFormField, 'Username');
        final passwordField = find.widgetWithText(TextFormField, 'Password');
        final loginBtn = find.text('Login');

        // Enter valid mock driver credentials
        await tester.enterText(usernameField, 'abel');
        await tester.enterText(passwordField, 'password');

        await tester.ensureVisible(loginBtn);
        await tester.tap(loginBtn);

        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 9 & 10. Navigates to Driver Home placeholder and displays correctly
        expect(find.text('Welcome, Abel'), findsOneWidget);
        expect(find.text('Driver Dashboard'), findsWidgets);
        expect(find.byIcon(Icons.drive_eta_rounded), findsOneWidget);

        // Test logout returns to login screen
        final logoutBtn = find.byIcon(Icons.logout_rounded);
        expect(logoutBtn, findsOneWidget);
        await tester.tap(logoutBtn);
        await tester.pumpAndSettle();

        expect(find.text('Welcome to SMUNI'), findsOneWidget);
        expect(find.text('Login'), findsOneWidget);
      },
    );

    testWidgets(
      '11. Passenger regression: yosef/password still reaches Passenger Home',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SmuniApp());
        await tester.pumpAndSettle();

        // Ensure Passenger is selected
        expect(find.text('Passenger Account'), findsOneWidget);

        final usernameField = find.widgetWithText(TextFormField, 'Username');
        final passwordField = find.widgetWithText(TextFormField, 'Password');
        final loginBtn = find.text('Login');

        await tester.enterText(usernameField, 'yosef');
        await tester.enterText(passwordField, 'password');

        await tester.ensureVisible(loginBtn);
        await tester.tap(loginBtn);

        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 11. Navigates to Passenger Home correctly
        expect(find.textContaining('Yosef'), findsOneWidget);
        expect(find.text('Wallet Balance'), findsOneWidget);
        expect(find.text('Recent Trips'), findsOneWidget);
        expect(find.text('Book Ride'), findsOneWidget);
        expect(find.text('Home'), findsOneWidget);
      },
    );

    testWidgets('Forgot password shows placeholder feedback in driver mode', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      // Switch to driver
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      final forgotBtn = find.text('Forgot password?');
      await tester.ensureVisible(forgotBtn);
      await tester.tap(forgotBtn);
      await tester.pump();

      expect(
        find.text('Password recovery will be available in an upcoming update.'),
        findsOneWidget,
      );
    });
  });
}
