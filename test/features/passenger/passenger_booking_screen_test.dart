import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smuni/features/passenger/screens/passenger_booking_screen.dart';
import 'package:smuni/models/passenger.dart';
import 'package:smuni/models/passenger_route.dart';
import 'package:smuni/models/trip.dart';
import 'package:smuni/navigation/app_routes.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/passenger_route_repository.dart';
import 'package:smuni/repositories/trip_repository.dart';
import 'package:smuni/services/mock/mock_passenger_route_service.dart';
import 'package:smuni/services/mock/mock_trip_service.dart';

void main() {
  const testRoute = PassengerRoute(
    id: 'test_route_1',
    name: 'Bole → Piazza',
    startStation: 'bole',
    endStation: 'piazza',
    startLabel: 'Bole',
    endLabel: 'Piazza',
    fare: 25.0,
    isAvailable: true,
    routeCode: 'ET-RT-01',
    estimatedDuration: '25 min',
    distanceKm: 8.5,
    intermediateStops: ['Meskel Square', 'Legehar'],
    instructions: 'Board at Bole station platform 2.',
  );

  Widget createBookingScreen({
    PassengerRoute? route = testRoute,
    required AuthRepository authRepo,
    required TripRepository tripRepo,
    PassengerRouteRepository? routeRepo,
  }) {
    return MaterialApp(
      routes: {
        AppRoutes.passengerHome: (_) =>
            const Scaffold(body: Text('Home Screen Content')),
        AppRoutes.passengerWallet: (_) =>
            const Scaffold(body: Text('Wallet Screen Content')),
        AppRoutes.passengerMap: (_) =>
            const Scaffold(body: Text('Map Screen Content')),
      },
      home: PassengerBookingScreen(
        route: route,
        authRepository: authRepo,
        tripRepository: tripRepo,
        passengerRouteRepository: routeRepo,
      ),
    );
  }

  group('PassengerBookingScreen - Confirmation UI', () {
    testWidgets('renders route details, pickup, destination, fare, duration', (
      tester,
    ) async {
      final authRepo = AuthRepository();
      final tripRepo = TripRepository(
        tripService: MockTripService(simulatedDelay: Duration.zero),
      );

      await tester.pumpWidget(
        createBookingScreen(authRepo: authRepo, tripRepo: tripRepo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirm Booking'), findsOneWidget);
      expect(find.text('Bole → Piazza'), findsOneWidget);
      expect(find.text('Bole'), findsOneWidget);
      expect(find.text('Piazza'), findsOneWidget);
      expect(find.text('ET-RT-01'), findsOneWidget);
      expect(find.text('ETB 25.00'), findsOneWidget);
      expect(find.text('25 min'), findsOneWidget);
      expect(find.text('Confirm Ride'), findsOneWidget);
    });

    testWidgets('displays wallet balance and shows sufficient balance state', (
      tester,
    ) async {
      final authRepo = AuthRepository();
      authRepo.setCurrentPassenger(
        const Passenger(
          id: 'p_1',
          name: 'Yosef Mekonnen',
          username: 'yosef',
          phone: '+251911234567',
          walletBalance: 200.0,
        ),
      );
      final tripRepo = TripRepository(
        tripService: MockTripService(simulatedDelay: Duration.zero),
      );

      await tester.pumpWidget(
        createBookingScreen(authRepo: authRepo, tripRepo: tripRepo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Available: ETB 200.00'), findsOneWidget);
      expect(find.text('Insufficient wallet balance'), findsNothing);
    });

    testWidgets(
      'displays insufficient balance warning and Top Up CTA when balance < fare',
      (tester) async {
        final authRepo = AuthRepository();
        authRepo.setCurrentPassenger(
          const Passenger(
            id: 'p_1',
            name: 'Yosef Mekonnen',
            username: 'yosef',
            phone: '+251911234567',
            walletBalance: 10.0, // less than 25.0 fare
          ),
        );
        final tripRepo = TripRepository(
          tripService: MockTripService(simulatedDelay: Duration.zero),
        );

        await tester.pumpWidget(
          createBookingScreen(authRepo: authRepo, tripRepo: tripRepo),
        );
        await tester.pumpAndSettle();

        expect(find.text('Available: ETB 10.00'), findsOneWidget);
        expect(
          find.textContaining('Insufficient wallet balance'),
          findsOneWidget,
        );
        expect(find.text('Top Up'), findsOneWidget);

        // Tap Top Up navigates to wallet
        await tester.tap(find.text('Top Up'));
        await tester.pumpAndSettle();
        expect(find.text('Wallet Screen Content'), findsOneWidget);
      },
    );
  });

  group('PassengerBookingScreen - Ride Confirmation Flow', () {
    testWidgets(
      'confirming ride deducts balance, stores trip, and shows success view',
      (tester) async {
        final authRepo = AuthRepository();
        authRepo.setCurrentPassenger(
          const Passenger(
            id: 'p_1',
            name: 'Yosef Mekonnen',
            username: 'yosef',
            phone: '+251911234567',
            walletBalance: 100.0,
          ),
        );
        final tripRepo = TripRepository(
          tripService: MockTripService(simulatedDelay: Duration.zero),
        );

        await tester.pumpWidget(
          createBookingScreen(authRepo: authRepo, tripRepo: tripRepo),
        );
        await tester.pumpAndSettle();

        // Ensure the Confirm Ride button is visible before tapping
        await tester.ensureVisible(find.text('Confirm Ride'));
        await tester.pumpAndSettle();

        // Tap Confirm Ride
        await tester.tap(find.text('Confirm Ride'));
        await tester.pumpAndSettle();

        // Verify success view
        expect(find.text('Ride Requested'), findsOneWidget);
        expect(find.text('Booking Confirmed'), findsOneWidget);
        expect(find.text('Status: Requested'), findsOneWidget);
        expect(
          find.text('Your ride from Bole to Piazza has been requested.'),
          findsOneWidget,
        );

        // Verify balance was deducted in AuthRepository
        expect(authRepo.passengerWalletBalance, 75.0);

        // Verify trip was recorded in TripRepository
        final recentTrips = await tripRepo.getRecentTrips();
        expect(recentTrips.first.fromLocation, 'Bole');
        expect(recentTrips.first.toLocation, 'Piazza');
        expect(recentTrips.first.amountPaid, 25.0);
        expect(recentTrips.first.status, TripStatus.requested);

        // Ensure Back to Home button is visible before tapping
        await tester.ensureVisible(find.text('Back to Home'));
        await tester.tap(find.text('Back to Home'));
        await tester.pumpAndSettle();
        expect(find.text('Home Screen Content'), findsOneWidget);
      },
    );

    testWidgets('loads fallback route when no route is provided as argument', (
      tester,
    ) async {
      final authRepo = AuthRepository();
      final tripRepo = TripRepository(
        tripService: MockTripService(simulatedDelay: Duration.zero),
      );
      final routeRepo = PassengerRouteRepository(
        service: MockPassengerRouteService(simulatedDelay: Duration.zero),
      );

      await tester.pumpWidget(
        createBookingScreen(
          route: null,
          authRepo: authRepo,
          tripRepo: tripRepo,
          routeRepo: routeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Expect fallback route loaded
      expect(find.text('Confirm Booking'), findsOneWidget);
      expect(find.text('Confirm Ride'), findsOneWidget);
    });
  });
}
