import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/core/utils/app_formatters.dart';
import 'package:smuni/features/driver/screens/driver_home_screen.dart';
import 'package:smuni/features/driver/screens/driver_routes_screen.dart';
import 'package:smuni/features/driver/widgets/driver_bottom_nav.dart';
import 'package:smuni/features/driver/widgets/driver_route_card.dart';
import 'package:smuni/features/driver/widgets/driver_route_details_sheet.dart';
import 'package:smuni/navigation/app_routes.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/driver_route_repository.dart';
import 'package:smuni/services/mock/mock_driver_route_service.dart';
import '../../support/smuni_test_app.dart';

void main() {
  group('DriverRoutesScreen Widget Tests', () {
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

    Widget buildScreen({
      DriverRouteRepository? routeRepo,
      AuthRepository? authRepo,
    }) {
      final auth = authRepo ?? AuthRepository();
      final routes = routeRepo ?? DriverRouteRepository();
      return MaterialApp(
        routes: {
          AppRoutes.driverHome: (_) =>
              const Scaffold(body: Text('Driver Home')),
          AppRoutes.driverSettings: (_) =>
              const Scaffold(body: Text('Settings')),
        },
        home: DriverRoutesScreen(routeRepository: routes, authRepository: auth),
      );
    }

    testWidgets('1. DriverRoutesScreen renders with title and header', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      expect(find.byType(DriverRoutesScreen), findsOneWidget);
      expect(find.text('My Routes'), findsOneWidget);
      expect(find.text('Assigned taxi corridors & fares'), findsOneWidget);
    });

    testWidgets('2. Displays route data from repository dynamically', (
      tester,
    ) async {
      final service = MockDriverRouteService(simulatedDelay: Duration.zero);
      final repo = DriverRouteRepository(service: service);
      final expectedRoutes = await service.getAssignedRoutes();

      await tester.pumpWidget(buildScreen(routeRepo: repo));
      await tester.pumpAndSettle();

      // Check first route name, locations, and fare dynamically
      final firstRoute = expectedRoutes.first;
      expect(find.text(firstRoute.name), findsOneWidget);
      expect(find.text(firstRoute.startLocation), findsWidgets);
      expect(find.text(firstRoute.endLocation), findsWidgets);

      final expectedFare = AppFormatters.formatCurrency(firstRoute.fare);
      expect(find.text(expectedFare), findsWidgets);

      // Verify all route cards render
      expect(
        find.byType(DriverRouteCard),
        findsNWidgets(expectedRoutes.length),
      );
    });

    testWidgets('3. Route status tags (Active / Inactive) display accurately', (
      tester,
    ) async {
      final service = MockDriverRouteService(simulatedDelay: Duration.zero);
      final expectedRoutes = await service.getAssignedRoutes();
      final activeCount = expectedRoutes.where((r) => r.isActive).length;
      final inactiveCount = expectedRoutes.length - activeCount;

      await tester.pumpWidget(
        buildScreen(routeRepo: DriverRouteRepository(service: service)),
      );
      await tester.pumpAndSettle();

      // Filter chips display the exact counts
      expect(find.text('Active ($activeCount)'), findsOneWidget);
      expect(find.text('Inactive ($inactiveCount)'), findsOneWidget);
      expect(find.textContaining('Active Routes Assigned'), findsOneWidget);
    });

    testWidgets('4. Filter chips switch displayed routes correctly', (
      tester,
    ) async {
      final service = MockDriverRouteService(simulatedDelay: Duration.zero);
      final expectedRoutes = await service.getAssignedRoutes();
      final activeCount = expectedRoutes.where((r) => r.isActive).length;
      final inactiveCount = expectedRoutes.length - activeCount;

      await tester.pumpWidget(
        buildScreen(routeRepo: DriverRouteRepository(service: service)),
      );
      await tester.pumpAndSettle();

      // Tap 'Active' filter chip
      await tester.tap(find.text('Active ($activeCount)'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverRouteCard), findsNWidgets(activeCount));

      // Tap 'Inactive' filter chip
      await tester.tap(find.text('Inactive ($inactiveCount)'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverRouteCard), findsNWidgets(inactiveCount));

      // Tap 'All Routes' filter chip
      await tester.tap(find.text('All Routes (${expectedRoutes.length})'));
      await tester.pumpAndSettle();

      expect(
        find.byType(DriverRouteCard),
        findsNWidgets(expectedRoutes.length),
      );
    });

    testWidgets('5. Empty state renders cleanly when no routes are available', (
      tester,
    ) async {
      final emptyService = MockDriverRouteService(
        simulatedDelay: Duration.zero,
        initialRoutes: const [],
      );
      final repo = DriverRouteRepository(service: emptyService);

      await tester.pumpWidget(buildScreen(routeRepo: repo));
      await tester.pumpAndSettle();

      expect(find.text('No Assigned Routes'), findsOneWidget);
      expect(
        find.textContaining('Contact your fleet supervisor'),
        findsOneWidget,
      );
      expect(find.text('Refresh'), findsOneWidget);
      expect(find.byType(DriverRouteCard), findsNothing);
    });

    testWidgets('6. Tapping route card opens DriverRouteDetailsSheet', (
      tester,
    ) async {
      final service = MockDriverRouteService(simulatedDelay: Duration.zero);
      final repo = DriverRouteRepository(service: service);
      final expectedRoutes = await service.getAssignedRoutes();
      final firstRoute = expectedRoutes.first;

      await tester.pumpWidget(buildScreen(routeRepo: repo));
      await tester.pumpAndSettle();

      // Tap first route card
      await tester.tap(find.byType(DriverRouteCard).first);
      await tester.pumpAndSettle();

      // Route details sheet is visible
      expect(find.byType(DriverRouteDetailsSheet), findsOneWidget);
      expect(find.text('Route Details'), findsOneWidget);
      expect(find.text('Stations & Intermediate Stops'), findsOneWidget);

      // Verify intermediate stop is displayed
      if (firstRoute.intermediateStops.isNotEmpty) {
        expect(find.text(firstRoute.intermediateStops.first), findsOneWidget);
      }

      // Close the sheet via Done button
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(DriverRouteDetailsSheet), findsNothing);
    });

    testWidgets('7. Driver bottom navigation renders with Routes active', (
      tester,
    ) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      final bottomNav = find.byType(DriverBottomNav);
      expect(bottomNav, findsOneWidget);

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1); // Routes is index 1
    });
  });

  group('Driver Routes — Full App Navigation Flow', () {
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

    testWidgets(
      '9. Tapping Routes in Driver bottom navigation opens Driver Routes',
      (tester) async {
        await loginAsDriver(tester);

        // Routes in bottom nav is the last 'Routes' finder
        final routesNavItem = find.text('Routes');
        await tester.tap(routesNavItem.last);
        await tester.pumpAndSettle();

        expect(find.byType(DriverRoutesScreen), findsOneWidget);
        expect(find.text('My Routes'), findsOneWidget);
      },
    );

    testWidgets(
      '10. Tapping Home from Driver Routes bottom nav navigates to Driver Home',
      (tester) async {
        await loginAsDriver(tester);

        // Navigate to Routes first
        final routesNavItem = find.text('Routes');
        await tester.tap(routesNavItem.last);
        await tester.pumpAndSettle();
        expect(find.byType(DriverRoutesScreen), findsOneWidget);

        // Tap 'Home' in bottom nav
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();

        expect(find.byType(DriverHomeScreen), findsOneWidget);
      },
    );

    testWidgets('11. Passenger navigation remains unaffected (regression)', (
      tester,
    ) async {
      await tester.pumpWidget(smuniTestApp());
      await tester.pumpAndSettle();

      // Default role is Passenger
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

      // Must NOT navigate to Driver routes or Driver home
      expect(find.byType(DriverRoutesScreen), findsNothing);
      expect(find.byType(DriverHomeScreen), findsNothing);

      // Must be on Passenger Home with passenger destinations
      expect(find.text('Wallet Balance'), findsOneWidget);
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });
  });
}
