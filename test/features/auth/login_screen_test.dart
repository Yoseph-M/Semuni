import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/app.dart';

void main() {
  group('LoginScreen Widget Tests', () {
    // Set standard phone viewport dimensions for widget tests
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

    testWidgets('Renders SMUNI branding, role selector, inputs, and button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      // Verify branding and welcome text
      expect(find.text('SMUNI'), findsWidgets);
      expect(find.text('Welcome to SMUNI'), findsOneWidget);

      // Verify role selector (Passenger selected by default)
      expect(find.text('Passenger'), findsOneWidget);
      expect(find.text('Driver'), findsOneWidget);
      expect(find.text('Passenger Account'), findsOneWidget);

      // Verify form fields
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Login'), findsOneWidget);
    });

    testWidgets(
      'Toggling role selector switches between Passenger and Driver',
      (WidgetTester tester) async {
        await tester.pumpWidget(const SmuniApp());
        await tester.pumpAndSettle();

        expect(find.text('Passenger Account'), findsOneWidget);

        // Tap on Driver
        await tester.tap(find.text('Driver'));
        await tester.pumpAndSettle();

        expect(find.text('Driver Account'), findsOneWidget);

        // Tap back to Passenger
        await tester.tap(find.text('Passenger'));
        await tester.pumpAndSettle();

        expect(find.text('Passenger Account'), findsOneWidget);
      },
    );

    testWidgets('Empty field submission triggers validation errors', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      final loginButton = find.text('Login');
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await tester.pumpAndSettle();

      expect(find.text('Please enter your username'), findsOneWidget);
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('Password visibility toggle toggles obscureText', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      final passwordFinder = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Password',
      );
      expect(passwordFinder, findsOneWidget);

      TextField passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isTrue);

      // Tap visibility toggle icon
      final toggleFinder = find.byTooltip('Show password');
      await tester.ensureVisible(toggleFinder);
      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isFalse);

      // Tap again to hide
      final hideToggleFinder = find.byTooltip('Hide password');
      await tester.ensureVisible(hideToggleFinder);
      await tester.tap(hideToggleFinder);
      await tester.pumpAndSettle();

      passwordField = tester.widget<TextField>(passwordFinder);
      expect(passwordField.obscureText, isTrue);
    });

    testWidgets('Invalid credentials displays error banner', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      final usernameField = find.widgetWithText(TextFormField, 'Username');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'wronguser');
      await tester.enterText(passwordField, 'wrongpass');

      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);

      // Advance clock through the mock network delay
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        find.text('Invalid username or password. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('Successful passenger login navigates to Passenger Dashboard', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      final usernameField = find.widgetWithText(TextFormField, 'Username');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'yosef');
      await tester.enterText(passwordField, 'password');

      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Successfully navigated to passenger home
      expect(find.textContaining('Yosef'), findsOneWidget);
      expect(find.text('Wallet Balance'), findsOneWidget);
      expect(find.text('Book Ride'), findsOneWidget);
    });

    testWidgets('Successful driver login navigates to Driver Dashboard', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      // Switch to driver role
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      final usernameField = find.widgetWithText(TextFormField, 'Username');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'abel');
      await tester.enterText(passwordField, 'password');

      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);

      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Successfully navigated to driver home
      expect(find.text('Welcome, Abel'), findsOneWidget);
      expect(find.text('Driver Dashboard'), findsWidgets);
    });
  });
}
