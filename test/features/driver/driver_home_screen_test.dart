import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/core/utils/app_formatters.dart';
import 'package:smuni/features/driver/screens/driver_home_screen.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/driver_dashboard_repository.dart';
import 'package:smuni/services/mock/mock_auth_service.dart';
import 'package:smuni/services/mock/mock_driver_dashboard_service.dart';
import '../../support/smuni_test_app.dart';

void main() {
  group('DriverHomeScreen Widget Tests', () {
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

    /// Create a driver-authenticated widget tree.
    Future<({AuthRepository auth, DriverDashboardRepository dash})>
    createAuthenticatedDeps(WidgetTester tester) async {
      final auth = AuthRepository(
        authService: MockAuthService(simulatedDelay: Duration.zero),
      );
      final dash = DriverDashboardRepository();
      await tester.runAsync(() async {
        await auth.loginDriver(username: 'abel', password: 'password');
      });
      return (auth: auth, dash: dash);
    }

    Widget buildScreen(AuthRepository auth, DriverDashboardRepository dash) {
      return MaterialApp(
        home: DriverHomeScreen(authRepository: auth, dashboardRepository: dash),
      );
    }

    // -------------------------------------------------------------------------
    // Test 1: DriverHomeScreen renders
    // -------------------------------------------------------------------------
    testWidgets('1. DriverHomeScreen renders without errors', (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.byType(DriverHomeScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 2: Greeting displays driver name
    // -------------------------------------------------------------------------
    testWidgets('2. Greeting contains driver name Abel', (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.textContaining('Abel'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // Test 3: Earnings card renders
    // -------------------------------------------------------------------------
    testWidgets("3. Today's Earnings card renders", (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.textContaining("Today's Earnings"), findsOneWidget);
      // Earnings amount appears after async data loads
      expect(find.textContaining('ETB'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // Test 4: Available balance renders
    // -------------------------------------------------------------------------
    testWidgets('4. Available Balance card renders', (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final driver = deps.auth.currentDriver!;
      final expectedBalance = AppFormatters.formatCurrency(
        driver.accountBalance,
      );

      expect(find.text('Available Balance'), findsOneWidget);
      expect(find.text(expectedBalance), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 7: Today's activity renders
    // -------------------------------------------------------------------------
    testWidgets("7. Today's Activity summary renders", (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.textContaining("Today's Activity"), findsOneWidget);
      expect(find.text('Completed Rides'), findsOneWidget);
      expect(find.text('Average Fare'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Tests 8–10: Primary Actions render
    // -------------------------------------------------------------------------
    testWidgets('8-9. Primary action cards render', (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Transactions'),
        150,
        scrollable: scrollable,
      );

      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Withdraw'), findsAtLeastNWidgets(1));
      // The Routes action card is gone from the dashboard; Routes is reachable
      // from the bottom navigation only, so its card subtitle must be absent.
      expect(find.text('Assigned'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Tests 11–12: Recent transactions section
    // -------------------------------------------------------------------------
    testWidgets('11. Recent Transactions section renders', (tester) async {
      final deps = await createAuthenticatedDeps(tester);
      // The shipped repository defaults to the real API-backed service, so the
      // offline mock is injected explicitly here to give the section data.
      final dash = DriverDashboardRepository(
        service: MockDriverDashboardService(),
      );
      await tester.pumpWidget(buildScreen(deps.auth, dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Recent Transactions'),
        150,
        scrollable: scrollable,
      );

      expect(find.text('Recent Transactions'), findsOneWidget);
      // Verify mock transaction data appears
      expect(find.textContaining('Taxi Fare Payment'), findsWidgets);
    });

    testWidgets('12. View all button exists in Recent Transactions', (
      tester,
    ) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('View all'),
        150,
        scrollable: scrollable,
      );

      expect(find.text('View all'), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 14–15: Bottom navigation renders & Home selected
    // -------------------------------------------------------------------------
    testWidgets('14-15. Bottom navigation renders with Home selected', (
      tester,
    ) async {
      final deps = await createAuthenticatedDeps(tester);
      await tester.pumpWidget(buildScreen(deps.auth, deps.dash));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Routes'), findsWidgets);
      expect(find.text('Settings'), findsOneWidget);

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Full-app flow tests (mock-wired app, real navigation)
  // ---------------------------------------------------------------------------
  group('DriverHomeScreen — Full App Navigation Flow', () {
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
      await tester.pumpWidget(smuniTestApp());
      await tester.pumpAndSettle();

      // Select Driver role
      await tester.tap(find.text('Driver'));
      await tester.pumpAndSettle();

      // Enter credentials
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'abel',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password',
      );

      await tester.ensureVisible(find.text('Login'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    // -------------------------------------------------------------------------
    // Test 19: abel/password reaches Driver Home
    // -------------------------------------------------------------------------
    testWidgets('19. abel/password credentials reach Driver Home', (
      tester,
    ) async {
      await loginAsDriver(tester);
      expect(find.byType(DriverHomeScreen), findsOneWidget);
      expect(find.textContaining('Abel'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // Test 8: Transactions action navigates to placeholder
    // -------------------------------------------------------------------------
    testWidgets(
      '8. Transactions action navigates to Transactions placeholder',
      (tester) async {
        await loginAsDriver(tester);

        final scrollable = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Transactions'),
          150,
          scrollable: scrollable,
        );

        await tester.tap(find.text('Transactions'));
        await tester.pumpAndSettle();

        expect(find.text('Transactions'), findsWidgets);

        // Pop back
        if (find.byType(BackButton).evaluate().isNotEmpty) {
          await tester.tap(find.byType(BackButton));
          await tester.pumpAndSettle();
        } else if (find
            .byIcon(Icons.arrow_back_rounded)
            .evaluate()
            .isNotEmpty) {
          await tester.tap(find.byIcon(Icons.arrow_back_rounded));
          await tester.pumpAndSettle();
        }
        expect(find.byType(DriverHomeScreen), findsOneWidget);
      },
    );

    // -------------------------------------------------------------------------
    // Test 9: Withdraw action navigates to placeholder
    // -------------------------------------------------------------------------
    testWidgets('9. Withdraw action navigates to Withdraw placeholder', (
      tester,
    ) async {
      await loginAsDriver(tester);

      // The primary action Withdraw card
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Transactions'),
        150,
        scrollable: scrollable,
      );

      // 'Withdraw' appears in primary actions AND in DriverBalanceCard
      // Tap the Withdraw text in primary actions section (below Routes)
      final withdrawFinders = find.text('Withdraw');
      // Tap the last Withdraw to get the primary action card
      await tester.tap(withdrawFinders.last);
      await tester.pumpAndSettle();

      expect(find.text('Withdraw'), findsWidgets);

      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      } else if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }
      expect(find.byType(DriverHomeScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 12: View all navigates to transactions placeholder
    // -------------------------------------------------------------------------
    testWidgets('12. View all navigates to Transactions placeholder', (
      tester,
    ) async {
      await loginAsDriver(tester);

      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('View all'),
        150,
        scrollable: scrollable,
      );

      await tester.tap(find.text('View all'));
      await tester.pumpAndSettle();

      expect(find.text('Transactions'), findsWidgets);

      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      } else if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }
      expect(find.byType(DriverHomeScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 13: Notifications navigation
    // -------------------------------------------------------------------------
    testWidgets('13. Notifications button navigates to Notifications', (
      tester,
    ) async {
      await loginAsDriver(tester);

      // Notification icon button is in the header
      final notifBtn = find.byIcon(Icons.notifications_outlined);
      expect(notifBtn, findsOneWidget);
      await tester.tap(notifBtn);
      await tester.pumpAndSettle();

      expect(find.text('Notifications'), findsWidgets);

      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      } else if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }
      expect(find.byType(DriverHomeScreen), findsOneWidget);
    });

    // -------------------------------------------------------------------------
    // Test 16: Routes bottom nav works
    // -------------------------------------------------------------------------
    testWidgets('16. Bottom nav Routes tab navigates', (tester) async {
      await loginAsDriver(tester);

      // Routes in bottom nav (first occurrence is bottom nav)
      final routesNavItem = find.text('Routes');
      await tester.tap(routesNavItem.last);
      await tester.pumpAndSettle();

      expect(find.textContaining('Routes'), findsWidgets);

      if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
      } else if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------------------
    // Test 17: Settings bottom nav works
    // -------------------------------------------------------------------------
    testWidgets('17. Bottom nav Settings tab navigates', (tester) async {
      await loginAsDriver(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);

      if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }
    });

    // -------------------------------------------------------------------------
    // Test 20: yosef/password still reaches Passenger Home (regression)
    // -------------------------------------------------------------------------
    testWidgets('20. yosef/password reaches Passenger Home (regression)', (
      tester,
    ) async {
      await tester.pumpWidget(smuniTestApp());
      await tester.pumpAndSettle();

      // Default role is Passenger — just enter credentials
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'yosef',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password',
      );

      await tester.ensureVisible(find.text('Login'));
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Must NOT navigate to driver home
      expect(find.byType(DriverHomeScreen), findsNothing);
      // Must show wallet balance (Passenger Home)
      expect(find.text('Wallet Balance'), findsOneWidget);
    });
  });
}
