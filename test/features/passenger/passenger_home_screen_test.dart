import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/core/utils/app_formatters.dart';
import 'package:smuni/features/passenger/screens/passenger_home_screen.dart';
import 'package:smuni/features/passenger/screens/passenger_map_screen.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/trip_repository.dart';
import 'package:smuni/services/mock/mock_auth_service.dart';
import 'package:smuni/services/mock/mock_trip_service.dart';
import '../../support/smuni_test_app.dart';

void main() {
  group('PassengerHomeScreen Widget Tests', () {
    /// Pops the current screen using whichever back affordance it shows: the
    /// map's custom header uses a rounded arrow, pushed AppBars use the
    /// framework's [BackButton].
    Future<void> popScreen(WidgetTester tester) async {
      final rounded = find.byIcon(Icons.arrow_back_rounded);
      if (rounded.evaluate().isNotEmpty) {
        await tester.tap(rounded.first);
      } else if (find.byType(BackButton).evaluate().isNotEmpty) {
        await tester.tap(find.byType(BackButton));
      }
      await tester.pumpAndSettle();
    }

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

    Widget createTestWidget({
      AuthRepository? authRepository,
      TripRepository? tripRepository,
    }) {
      // The shipped repositories default to the real API-backed services, so
      // the offline mocks are injected explicitly here.
      final authRepo =
          authRepository ??
          AuthRepository(
            authService: MockAuthService(simulatedDelay: Duration.zero),
          );
      final tripRepo =
          tripRepository ??
          TripRepository(
            tripService: MockTripService(simulatedDelay: Duration.zero),
          );

      return MaterialApp(
        home: PassengerHomeScreen(
          authRepository: authRepo,
          tripRepository: tripRepo,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Test 1: Passenger Home renders with all expected sections
    // -------------------------------------------------------------------------
    testWidgets('Passenger Home renders with greeting, balance, and actions', (
      WidgetTester tester,
    ) async {
      final authRepo = AuthRepository(
        authService: MockAuthService(simulatedDelay: Duration.zero),
      );
      // Pre-authenticate passenger using runAsync for simulated delay
      await tester.runAsync(() async {
        await authRepo.loginPassenger(username: 'yosef', password: 'password');
      });

      await tester.pumpWidget(createTestWidget(authRepository: authRepo));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // 1. Passenger Home renders
      expect(find.byType(PassengerHomeScreen), findsOneWidget);

      // 2. Greeting/name appears
      expect(find.textContaining('Yosef'), findsOneWidget);
      expect(find.text('Where would you like to go?'), findsOneWidget);

      // 3. Wallet balance appears
      expect(find.text('Wallet Balance'), findsOneWidget);
      expect(find.text(AppFormatters.formatCurrency(1250.0)), findsOneWidget);

      // 4. Top Up action exists
      expect(find.text('Top Up'), findsOneWidget);

      // 5. Find Route action exists
      expect(find.text('Find Route'), findsOneWidget);

      // 6. Wallet action exists
      expect(find.text('Wallet'), findsOneWidget);

      // 7. Recent Trips section appears
      expect(find.text('Recent Trips'), findsOneWidget);

      // 8. View all appears
      expect(find.text('View all'), findsOneWidget);

      // 9. Mock trip data renders
      expect(find.text('Bole'), findsOneWidget);
      expect(find.text('Piazza'), findsOneWidget);
      expect(find.text('Mexico'), findsOneWidget);
      expect(find.text('Saris'), findsOneWidget);

      // 10. Bottom navigation contains Map, Home, Settings
      expect(find.text('Map'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      // 11. Home is selected by default
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
    });

    // -------------------------------------------------------------------------
    // Test 2: Full app flow integration — covers Phase 10 Book Ride → Map
    // -------------------------------------------------------------------------
    testWidgets('Full app flow: Login -> Home -> Navigate to sub-screens', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(smuniTestApp());
      await tester.pumpAndSettle();

      // Login as Passenger
      final usernameField = find.widgetWithText(TextFormField, 'Username');
      final passwordField = find.widgetWithText(TextFormField, 'Password');
      final loginButton = find.text('Login');

      await tester.enterText(usernameField, 'yosef');
      await tester.enterText(passwordField, 'password');
      await tester.ensureVisible(loginButton);
      await tester.tap(loginButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Confirm we are on Passenger Home
      expect(find.byType(PassengerHomeScreen), findsOneWidget);

      // ── Test 12: Bottom-nav Map tab navigates to PassengerMapScreen ──
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // PassengerMapScreen replaces the old PlaceholderScreen
      expect(find.byType(PassengerMapScreen), findsOneWidget);

      // Map header is visible
      expect(find.text('Taxi Map'), findsOneWidget);

      // Search field is visible
      expect(find.text('Discover Routes'), findsOneWidget);

      // Back button returns to Passenger Home
      final backButton = find.byIcon(Icons.arrow_back_rounded);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      expect(find.byType(PassengerHomeScreen), findsOneWidget);
      expect(find.text('Wallet Balance'), findsOneWidget);

      // ── Test 13: Settings tab opens the Settings screen ──
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      await popScreen(tester);
      expect(find.byType(PassengerHomeScreen), findsOneWidget);

      // ── Test 14: Find Route navigates to PassengerMapScreen (Phase 10) ──
      final findRouteBtn = find.text('Find Route');
      await tester.ensureVisible(findRouteBtn);
      await tester.tap(findRouteBtn);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // Find Route now opens the Passenger Map / Route Discovery screen
      expect(find.byType(PassengerMapScreen), findsOneWidget);
      expect(find.text('Taxi Map'), findsOneWidget);
      expect(find.text('Discover Routes'), findsOneWidget);

      await popScreen(tester);
      expect(find.byType(PassengerHomeScreen), findsOneWidget);

      // ── Test 15: Wallet action navigates to the Wallet screen ──
      final walletBtn = find.text('Wallet');
      await tester.ensureVisible(walletBtn);
      await tester.tap(walletBtn);
      await tester.pumpAndSettle();
      // The wallet screen's own AppBar title proves the navigation happened.
      expect(find.text('My Wallet'), findsOneWidget);
      await popScreen(tester);
      expect(find.byType(PassengerHomeScreen), findsOneWidget);

      // ── Test 16: View all opens the Trip History screen ──
      final viewAllBtn = find.text('View all');
      await tester.ensureVisible(viewAllBtn);
      await tester.tap(viewAllBtn);
      await tester.pumpAndSettle();
      expect(find.text('Trip History'), findsWidgets);
    });

    // -------------------------------------------------------------------------
    // Test 3: Phase 10 Complete Flow:
    // Passenger Home -> Find Route -> Map -> Search -> Select Route -> Details -> Pay
    // -------------------------------------------------------------------------
    testWidgets(
      'Phase 10 Flow: Home -> Find Route -> Map -> Search -> Route Details -> Pay',
      (WidgetTester tester) async {
        await tester.pumpWidget(smuniTestApp());
        await tester.pumpAndSettle();

        // Login as passenger
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Username'),
          'yosef',
        );
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'),
          'password',
        );
        final loginButton = find.text('Login');
        await tester.ensureVisible(loginButton);
        await tester.tap(loginButton);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // 1. Passenger Home renders and Find Route exists
        expect(find.byType(PassengerHomeScreen), findsOneWidget);
        final findRouteBtn = find.text('Find Route');
        expect(findRouteBtn, findsOneWidget);

        // 2. Tap Find Route -> navigates to PassengerMapScreen
        await tester.tap(findRouteBtn);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(find.byType(PassengerMapScreen), findsOneWidget);
        expect(find.text('Taxi Map'), findsOneWidget);

        // 3. Search destination (the screen has From + To inputs)
        final toField = find.byType(TextField).at(1);
        await tester.enterText(toField, 'Piazza');
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 4. Destination results / routes are displayed
        expect(find.text('Matching Routes'), findsOneWidget);
        expect(find.textContaining('ETB '), findsWidgets);

        // 5. Select route -> route details bottom sheet opens
        await tester.tap(find.textContaining('ETB ').first);
        await tester.pumpAndSettle();

        // 6. View route details
        expect(
          find.text('From').evaluate().isNotEmpty ||
              find.text('To').evaluate().isNotEmpty,
          isTrue,
        );

        // Scroll the sheet up to reveal the CTA
        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, -300),
        );
        await tester.pumpAndSettle();

        // 7. Pay Taxi Fare button opens the payment flow
        final payFareBtn = find.byKey(const Key('pay_taxi_fare_button'));
        expect(payFareBtn, findsOneWidget);
        await tester.tap(payFareBtn);
        await tester.pumpAndSettle(const Duration(seconds: 2));

        // Lands on the payment screen
        expect(find.text('Taxi Payment'), findsWidgets);
      },
    );
  });
}
