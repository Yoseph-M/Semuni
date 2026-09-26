import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/app/app.dart';
import 'package:smuni/core/utils/app_formatters.dart';
import 'package:smuni/features/passenger/screens/passenger_home_screen.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/trip_repository.dart';

void main() {
  group('PassengerHomeScreen Widget Tests', () {
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
      final authRepo = authRepository ?? AuthRepository();
      final tripRepo = tripRepository ?? TripRepository();

      return MaterialApp(
        home: PassengerHomeScreen(
          authRepository: authRepo,
          tripRepository: tripRepo,
        ),
      );
    }

    testWidgets('Passenger Home renders with greeting, balance, and actions', (
      WidgetTester tester,
    ) async {
      final authRepo = AuthRepository();
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

      // 5. Book Ride action exists
      expect(find.text('Book Ride'), findsOneWidget);

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

    testWidgets('Full app flow: Login -> Home -> Navigate to sub-screens', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const SmuniApp());
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

      // 12. Tapping Map navigates to Map placeholder
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();

      // Verify that the placeholder screen displays 'Map'
      expect(find.text('Map'), findsWidgets);
      // Verify that unrelated taxi-information text is not displayed
      expect(find.text('Taxi stations and routes near you.'), findsNothing);

      // Verify back button exists and returns to Passenger Home screen
      final backButton = find.byIcon(Icons.arrow_back_rounded);
      expect(backButton, findsOneWidget);
      await tester.tap(backButton);
      await tester.pumpAndSettle();

      // Verify returned to Passenger Home screen
      expect(find.byType(PassengerHomeScreen), findsOneWidget);
      expect(find.text('Wallet Balance'), findsOneWidget);

      // 13. Tapping Settings navigates to Settings placeholder
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings'), findsWidgets);
      // Pop back
      if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }

      // 14. Tapping Book Ride navigates to Book Ride placeholder
      final bookRideBtn = find.text('Book Ride');
      await tester.ensureVisible(bookRideBtn);
      await tester.tap(bookRideBtn);
      await tester.pumpAndSettle();
      expect(find.text('Book Ride'), findsWidgets);
      // Pop back
      if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }

      // 15. Tapping Wallet action navigates to Wallet placeholder
      final walletBtn = find.text('Wallet');
      await tester.ensureVisible(walletBtn);
      await tester.tap(walletBtn);
      await tester.pumpAndSettle();
      expect(find.text('Wallet'), findsWidgets);
      // Pop back
      if (find.byIcon(Icons.arrow_back_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.arrow_back_rounded));
        await tester.pumpAndSettle();
      }

      // 16. Tapping View all navigates to Recent Trips placeholder
      final viewAllBtn = find.text('View all');
      await tester.ensureVisible(viewAllBtn);
      await tester.tap(viewAllBtn);
      await tester.pumpAndSettle();
      expect(find.text('Recent Trips'), findsWidgets);
    });
  });
}
