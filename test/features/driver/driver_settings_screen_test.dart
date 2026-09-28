import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/app.dart';
import 'package:smuni/features/auth/screens/login_screen.dart';
import 'package:smuni/features/driver/screens/driver_home_screen.dart';
import 'package:smuni/features/driver/screens/driver_routes_screen.dart';
import 'package:smuni/features/driver/screens/driver_settings_screen.dart';
import 'package:smuni/features/driver/widgets/driver_bottom_nav.dart';

void main() {
  group('Driver Settings Screen Tests', () {
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

    Future<void> loginAsDriver(WidgetTester tester) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      final usernameField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'abel');
      await tester.enterText(passwordField, 'password');
      await tester.tap(loginButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    testWidgets(
      '1. Driver Settings screen renders with authenticated driver info',
      (tester) async {
        await loginAsDriver(tester);

        // Navigate to Settings
        final navBar = find.byType(NavigationBar);
        await tester.tap(
          find.descendant(of: navBar, matching: find.text('Settings')),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DriverSettingsScreen), findsOneWidget);

        // 2. Authenticated driver info displayed (matches MockAuthService._mockDriver)
        expect(find.text('Abel Girma'), findsOneWidget);
        expect(find.text('@abel • Driver'), findsOneWidget);
        expect(find.text('+251922345678'), findsOneWidget);
        expect(find.text('ET-DL-2021-00456'), findsOneWidget); // License
        expect(find.text('AA-3-12345'), findsOneWidget); // Plate

        // Avatar initial
        expect(find.text('A'), findsOneWidget);
      },
    );

    testWidgets(
      '2. Driver bottom navigation renders and Settings is selected',
      (tester) async {
        await loginAsDriver(tester);

        final navBarFinder = find.byType(NavigationBar);
        await tester.tap(
          find.descendant(of: navBarFinder, matching: find.text('Settings')),
        );
        await tester.pumpAndSettle();

        // 3. Bottom nav renders
        expect(find.byType(DriverBottomNav), findsOneWidget);

        // 4. Settings is selected (index 2)
        final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        expect(navBar.selectedIndex, 2);
      },
    );

    testWidgets('3. Home and Routes navigation works from Settings', (
      tester,
    ) async {
      await loginAsDriver(tester);

      final navBarFinder = find.byType(NavigationBar);
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Settings')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DriverSettingsScreen), findsOneWidget);

      // 5. Home navigation works
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Home')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DriverHomeScreen), findsOneWidget);

      // Go back to Settings
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Settings')),
      );
      await tester.pumpAndSettle();

      // 6. Routes navigation works
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Routes')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DriverRoutesScreen), findsOneWidget);
    });

    testWidgets('4. Logout action is visible and shows confirmation dialog', (
      tester,
    ) async {
      await loginAsDriver(tester);

      final navBarFinder = find.byType(NavigationBar);
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Settings')),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(ListView).first;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();

      // 8. Logout action is visible
      final logoutBtn = find.byKey(const Key('driver_logout_button'));
      expect(logoutBtn, findsOneWidget);

      // 9. Logout confirmation dialog appears
      await tester.tap(logoutBtn);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.text('Are you sure you want to sign out of your driver account?'),
        findsOneWidget,
      );
    });

    testWidgets('5. Canceling logout keeps the driver authenticated', (
      tester,
    ) async {
      await loginAsDriver(tester);

      final navBarFinder = find.byType(NavigationBar);
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Settings')),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(ListView).first;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('driver_logout_button')));
      await tester.pumpAndSettle();

      // 10. Canceling logout
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog dismissed, still on settings
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DriverSettingsScreen), findsOneWidget);
    });

    testWidgets('6. Confirming logout logs driver out and goes to login', (
      tester,
    ) async {
      await loginAsDriver(tester);

      final navBarFinder = find.byType(NavigationBar);
      await tester.tap(
        find.descendant(of: navBarFinder, matching: find.text('Settings')),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(ListView).first;
      await tester.drag(scrollable, const Offset(0, -500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('driver_logout_button')));
      await tester.pumpAndSettle();

      // 11. Confirming logout
      // 12. Reaches login screen
      // 13. Driver cannot remain authenticated
      await tester.tap(find.widgetWithText(TextButton, 'Log out'));
      await tester.pumpAndSettle(
        const Duration(seconds: 1),
      ); // Wait for mock logout network delay

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(DriverSettingsScreen), findsNothing);
    });

    testWidgets('7. Passenger login still works (regression)', (tester) async {
      await tester.pumpWidget(const SmuniApp());
      await tester.pumpAndSettle();

      final usernameField = find.byType(TextFormField).first;
      final passwordField = find.byType(TextFormField).last;
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'yosef');
      await tester.enterText(passwordField, 'password');
      await tester.tap(loginButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // 14. Passenger login works
      expect(find.textContaining('Yosef'), findsWidgets);
    });
  });
}
