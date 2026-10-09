import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/features/passenger/screens/passenger_settings_screen.dart';
import 'package:smuni/models/passenger.dart';
import 'package:smuni/navigation/app_routes.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/services/mock/mock_auth_service.dart';

/// Creates a pre-authenticated AuthRepository using [MockAuthService] so that
/// [logout()] completes without a network call, and injects a fake Passenger
/// directly — no backend required.
AuthRepository authenticatedPassengerRepo() {
  final repo = AuthRepository(authService: MockAuthService());
  repo.setCurrentPassenger(
    const Passenger(
      id: 'test-id-001',
      name: 'Abebe Girma',
      username: 'abebe',
      phone: '+251911123456',
      walletBalance: 250.0,
    ),
  );
  return repo;
}

void main() {
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

  Widget wrapScreen(
    Widget child, {
    Map<String, WidgetBuilder> extraRoutes = const {},
  }) {
    return MaterialApp(
      routes: {
        AppRoutes.login: (_) => const Scaffold(body: Text('Login Screen')),
        AppRoutes.passengerNotifications: (_) =>
            const Scaffold(body: Text('Passenger Notifications')),
        ...extraRoutes,
      },
      home: child,
    );
  }

  group('PassengerSettingsScreen', () {
    // -------------------------------------------------------------------------
    // 1. Screen renders with account info
    // -------------------------------------------------------------------------

    testWidgets('1. opens successfully and displays account info', (
      tester,
    ) async {
      final repo = authenticatedPassengerRepo();

      await tester.pumpWidget(
        wrapScreen(PassengerSettingsScreen(authRepository: repo)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PassengerSettingsScreen), findsOneWidget);
      // AppBar title
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Settings'),
        ),
        findsOneWidget,
      );
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Abebe Girma'), findsOneWidget);
      expect(find.text('@abebe • Passenger'), findsOneWidget);
      expect(find.text('+251911123456'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 2. Sections and rows appear
    // -------------------------------------------------------------------------

    testWidgets('2. sections and rows appear', (tester) async {
      final repo = authenticatedPassengerRepo();

      await tester.pumpWidget(
        wrapScreen(PassengerSettingsScreen(authRepository: repo)),
      );
      await tester.pumpAndSettle();

      // Visible rows near the top
      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Notification History'), findsOneWidget);

      // Scroll to Language
      await tester.dragUntilVisible(
        find.text('Language'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('English'), findsOneWidget);

      // Scroll to Support section
      await tester.dragUntilVisible(
        find.text('Support / Information'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('Support / Information'), findsOneWidget);
      expect(find.text('About semuni'), findsOneWidget);
      expect(find.text('Version'), findsOneWidget);

      // Logout button must exist
      expect(find.byKey(const Key('passenger_logout_button')), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // 3. Notification History navigates to notifications screen
    // -------------------------------------------------------------------------

    testWidgets(
      '3. Notification History navigates to Passenger Notifications',
      (tester) async {
        final repo = authenticatedPassengerRepo();

        await tester.pumpWidget(
          wrapScreen(PassengerSettingsScreen(authRepository: repo)),
        );
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.text('Notification History'),
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Notification History'));
        await tester.pumpAndSettle();

        expect(find.text('Passenger Notifications'), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // 4. Language row shows dialog
    // -------------------------------------------------------------------------

    testWidgets('4. Language row shows English-only dialog', (tester) async {
      final repo = authenticatedPassengerRepo();

      await tester.pumpWidget(
        wrapScreen(PassengerSettingsScreen(authRepository: repo)),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Language'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();

      expect(
        find.text('Currently, only English is supported.'),
        findsOneWidget,
      );

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('Currently, only English is supported.'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // 5. About semuni dialog
    // -------------------------------------------------------------------------

    testWidgets('5. About semuni displays product description', (tester) async {
      final repo = authenticatedPassengerRepo();

      await tester.pumpWidget(
        wrapScreen(PassengerSettingsScreen(authRepository: repo)),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('About semuni'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('About semuni'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('taxi route and station discovery platform'),
        findsOneWidget,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('taxi route and station discovery platform'),
        findsNothing,
      );
    });

    // -------------------------------------------------------------------------
    // 6. Logout confirmation — Cancel keeps session
    // -------------------------------------------------------------------------

    testWidgets(
      '6. Logout confirmation: Cancel keeps passenger authenticated',
      (tester) async {
        final repo = authenticatedPassengerRepo();

        await tester.pumpWidget(
          wrapScreen(PassengerSettingsScreen(authRepository: repo)),
        );
        await tester.pumpAndSettle();

        await tester.dragUntilVisible(
          find.byKey(const Key('passenger_logout_button')),
          find.byType(ListView),
          const Offset(0, -500),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('passenger_logout_button')));
        await tester.pumpAndSettle();

        // Dialog appears
        expect(find.text('Log out?'), findsOneWidget);

        // Tap Cancel
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Dialog gone — still on Settings, session intact
        expect(find.text('Log out?'), findsNothing);
        // Confirm still on settings: AppBar title
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text('Settings'),
          ),
          findsOneWidget,
        );
        expect(repo.currentPassenger, isNotNull);
      },
    );

    // -------------------------------------------------------------------------
    // 7. Logout — Confirm clears session and navigates to Login
    // -------------------------------------------------------------------------

    testWidgets('7. Logout confirmed: clears session and navigates to Login', (
      tester,
    ) async {
      final repo = authenticatedPassengerRepo();

      await tester.pumpWidget(
        wrapScreen(PassengerSettingsScreen(authRepository: repo)),
      );
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.byKey(const Key('passenger_logout_button')),
        find.byType(ListView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('passenger_logout_button')));
      await tester.pumpAndSettle();

      // Tap 'Log out' in dialog (last, since the button label also says 'Log out')
      await tester.tap(find.text('Log out').last);
      await tester.pumpAndSettle();

      // Should have navigated to the login stub
      expect(find.text('Login Screen'), findsOneWidget);

      // Session is cleared
      expect(repo.currentPassenger, isNull);
    });
  });
}
