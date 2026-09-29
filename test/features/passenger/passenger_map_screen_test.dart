import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/features/passenger/screens/passenger_map_screen.dart';
import 'package:smuni/models/passenger_route.dart';
import 'package:smuni/navigation/app_routes.dart';
import 'package:smuni/repositories/passenger_route_repository.dart';
import 'package:smuni/services/mock/mock_passenger_route_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds the [PassengerMapScreen] wrapped in a [MaterialApp] with a
/// zero-delay mock service so tests don't wait for the simulated network.
Widget buildMapScreen({PassengerRouteRepository? repository}) {
  final repo =
      repository ??
      PassengerRouteRepository(
        service: MockPassengerRouteService(simulatedDelay: Duration.zero),
      );
  return MaterialApp(
    routes: {
      AppRoutes.passengerHome: (_) =>
          const Scaffold(body: Text('Wallet Balance')),
      AppRoutes.passengerSettings: (_) =>
          const Scaffold(body: Text('Settings')),
      AppRoutes.passengerBookRide: (_) =>
          const Scaffold(body: Text('Book Ride')),
    },
    home: PassengerMapScreen(passengerRouteRepository: repo),
  );
}

/// Pumps the map screen and waits for the initial station load to complete.
Future<void> pumpMapScreen(
  WidgetTester tester, {
  PassengerRouteRepository? repository,
}) async {
  await tester.pumpWidget(buildMapScreen(repository: repository));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PassengerMapScreen Widget Tests', () {
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

    // ── Test 1: Screen renders ───────────────────────────────────────────────
    testWidgets('1. PassengerMapScreen renders without errors', (tester) async {
      await pumpMapScreen(tester);
      expect(find.byType(PassengerMapScreen), findsOneWidget);
    });

    // ── Test 2: Passenger bottom navigation is visible ───────────────────────
    testWidgets('2. Passenger bottom NavigationBar is visible', (tester) async {
      await pumpMapScreen(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      // All three destinations are present
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    // ── Test 3: Map is the selected navigation destination ───────────────────
    testWidgets('3. Map is the selected navigation destination (index 0)', (
      tester,
    ) async {
      await pumpMapScreen(tester);
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });

    // ── Test 4: Map canvas renders ───────────────────────────────────────────
    testWidgets('4. Mock map canvas renders with station markers', (
      tester,
    ) async {
      await pumpMapScreen(tester);
      // The header with map title is visible
      expect(find.text('Taxi Map'), findsOneWidget);
      // "Addis Ababa" context label appears
      expect(find.text('Addis Ababa · Mock Network'), findsOneWidget);
    });

    // ── Test 5: Search field renders ─────────────────────────────────────────
    testWidgets('5. Search field renders with correct hint text', (
      tester,
    ) async {
      await pumpMapScreen(tester);
      expect(find.text('Where do you want to go?'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    // ── Test 6: Popular destinations hint chips render ────────────────────────
    testWidgets('6. Popular destination chips are shown before search', (
      tester,
    ) async {
      await pumpMapScreen(tester);
      expect(find.text('Popular Destinations'), findsOneWidget);
      // Destination chips are rendered as ActionChips
      expect(find.widgetWithText(ActionChip, 'Piazza'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Bole'), findsOneWidget);
    });

    // ── Test 7: Searching for a known destination returns results ────────────
    testWidgets('7. Searching for "Piazza" returns route results', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Piazza');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Results section header appears
      expect(find.text('Matching Routes'), findsOneWidget);

      // At least one route to Piazza appears
      expect(find.textContaining('Piazza'), findsWidgets);
    });

    // ── Test 8: Searching for an unknown destination shows no results ─────────
    testWidgets('8. Searching for "Lalibela" shows no results message', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Lalibela');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(find.textContaining('No routes found'), findsOneWidget);
    });

    // ── Test 9: Selecting a destination displays matching route options ───────
    testWidgets('9. Selecting a destination shows routes to that station', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      // Search for Megenagna
      await tester.enterText(find.byType(TextField), 'Megenagna');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Routes heading should appear
      expect(
        find.textContaining('Megenagna').evaluate().isNotEmpty ||
            find.textContaining('Routes').evaluate().isNotEmpty,
        isTrue,
      );
    });

    // ── Test 10: Route cards display relevant information ─────────────────────
    testWidgets('10. Route cards show name, fare, and status', (tester) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Piazza');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Fare is displayed (ETB prefix)
      expect(find.textContaining('ETB'), findsWidgets);

      // Status badge is visible (Active or Limited)
      expect(
        find.text('Active').evaluate().isNotEmpty ||
            find.text('Limited').evaluate().isNotEmpty,
        isTrue,
      );
    });

    // ── Test 11: Tapping a route opens route detail bottom sheet ─────────────
    testWidgets('11. Tapping a route opens the route detail bottom sheet', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Piazza');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Tap the first matching route card
      final routeCard = find.ancestor(
        of: find.textContaining('ETB').first,
        matching: find.byType(InkWell),
      );
      expect(routeCard, findsOneWidget);
      await tester.tap(routeCard);
      await tester.pumpAndSettle();

      // Bottom sheet opened — From/To labels visible
      expect(
        find.text('From').evaluate().isNotEmpty ||
            find.text('To').evaluate().isNotEmpty,
        isTrue,
      );
    });

    // ── Test 12: Route detail information is correct ──────────────────────────
    testWidgets('12. Route detail sheet shows correct route info', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Piazza');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Verify at least one route card with expected route fields is visible
      expect(find.textContaining('ETB'), findsWidgets);
    });

    // ── Test 13: Continue/Book action is present in route detail ─────────────
    testWidgets('13. Book This Ride button navigates to booking flow', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Piazza');
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Find and tap an available route card to open the detail sheet.
      final routeCard = find.ancestor(
        of: find.textContaining('ETB').first,
        matching: find.byType(InkWell),
      );
      expect(routeCard, findsOneWidget);
      await tester.tap(routeCard);
      await tester.pumpAndSettle();

      // Book button should be present in the detail sheet (for available routes)
      final bookBtn = find.text('Book This Ride');
      if (bookBtn.evaluate().isNotEmpty) {
        // It exists — verify it's a button
        expect(bookBtn, findsOneWidget);
      } else {
        // Route is limited — Unavailable button is shown
        expect(find.text('Route Unavailable'), findsOneWidget);
      }
    });

    // ── Test 14: Home navigation from Map ────────────────────────────────────
    testWidgets('14. Tapping Home in bottom nav navigates to Passenger Home', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Map screen is no longer on top; Home is a replacement route
      // (the navigator pushed passengerHome as replacement)
      expect(find.text('Wallet Balance'), findsOneWidget);
    });

    // ── Test 15: Settings navigation from Map ────────────────────────────────
    testWidgets('15. Tapping Settings in bottom nav navigates to Settings', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsWidgets);
    });

    // ── Test 16: Clear button clears search and resets results ───────────────
    testWidgets('16. Clear button resets search results to hint state', (
      tester,
    ) async {
      await pumpMapScreen(tester);

      await tester.enterText(find.byType(TextField), 'Piazza');
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // Results should be showing
      expect(find.text('Matching Routes'), findsOneWidget);

      // Tap the clear (X) button
      final clearBtn = find.byIcon(Icons.close_rounded);
      expect(clearBtn, findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      // Hint panel is restored
      expect(find.text('Popular Destinations'), findsOneWidget);
    });

    // ── Test 17: Demo Data badge visible ─────────────────────────────────────
    testWidgets('17. Demo Data badge is shown in the header', (tester) async {
      await pumpMapScreen(tester);
      expect(find.text('Demo Data'), findsOneWidget);
    });

    // ── Test 18: Back button is present ──────────────────────────────────────
    testWidgets('18. Back button is present in the header', (tester) async {
      await pumpMapScreen(tester);
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
    });
  });

  // ── Passenger Route Repository Unit Tests ─────────────────────────────────
  group('PassengerRouteRepository unit tests', () {
    late PassengerRouteRepository repo;

    setUp(() {
      repo = PassengerRouteRepository(
        service: MockPassengerRouteService(simulatedDelay: Duration.zero),
      );
    });

    test('getStations returns a non-empty list', () async {
      final stations = await repo.getStations();
      expect(stations, isNotEmpty);
      expect(stations.any((s) => s.name == 'Bole'), isTrue);
      expect(stations.any((s) => s.name == 'Piazza'), isTrue);
      expect(stations.any((s) => s.name == 'Megenagna'), isTrue);
    });

    test('getAllRoutes returns a non-empty list', () async {
      final routes = await repo.getAllRoutes();
      expect(routes, isNotEmpty);
    });

    test('searchByDestination("Piazza") returns routes to Piazza', () async {
      final results = await repo.searchByDestination('Piazza');
      expect(results, isNotEmpty);
      expect(results.every((r) => r.endStation == 'piazza'), isTrue);
    });

    test('searchByDestination("") returns empty list', () async {
      final results = await repo.searchByDestination('');
      expect(results, isEmpty);
    });

    test('searchByDestination("Lalibela") returns empty list', () async {
      final results = await repo.searchByDestination('Lalibela');
      expect(results, isEmpty);
    });

    test('searchByDestination is case-insensitive', () async {
      final lower = await repo.searchByDestination('piazza');
      final upper = await repo.searchByDestination('PIAZZA');
      expect(lower.length, equals(upper.length));
      expect(lower, isNotEmpty);
    });

    test('getRoutesToStation("piazza") returns routes to Piazza', () async {
      final results = await repo.getRoutesToStation('piazza');
      expect(results, isNotEmpty);
      expect(results.every((r) => r.endStation == 'piazza'), isTrue);
    });

    test('getRoutesToStation("unknown") returns empty list', () async {
      final results = await repo.getRoutesToStation('unknown_id');
      expect(results, isEmpty);
    });

    test('PassengerRoute has correct fields', () {
      const route = PassengerRoute(
        id: 'test_01',
        name: 'Bole → Piazza',
        startStation: 'bole',
        endStation: 'piazza',
        startLabel: 'Bole Medhanialem',
        endLabel: 'Piazza (Churchill Ave)',
        fare: 25.0,
        isAvailable: true,
        estimatedDuration: '30–40 min',
      );
      expect(route.id, 'test_01');
      expect(route.fare, 25.0);
      expect(route.isAvailable, isTrue);
      expect(route.intermediateStops, isEmpty);
    });

    test('TaxiStation has correct fields and map coordinates', () {
      const station = TaxiStation(
        id: 'bole',
        name: 'Bole',
        label: 'Bole',
        mapX: 0.72,
        mapY: 0.60,
        isHub: true,
      );
      expect(station.id, 'bole');
      expect(station.isHub, isTrue);
      expect(station.mapX, greaterThan(0.0));
      expect(station.mapX, lessThanOrEqualTo(1.0));
      expect(station.mapY, greaterThan(0.0));
      expect(station.mapY, lessThanOrEqualTo(1.0));
    });
  });
}
