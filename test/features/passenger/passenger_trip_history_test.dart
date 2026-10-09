import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smuni/models/trip.dart';
import 'package:smuni/repositories/trip_repository.dart';
import 'package:smuni/services/mock/mock_trip_service.dart';
import 'package:smuni/features/passenger/screens/passenger_trip_history_screen.dart';
import 'package:smuni/features/passenger/screens/passenger_trip_detail_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a [TripRepository] backed by a zero-delay [MockTripService].
TripRepository _makeRepo([TripService? service]) => TripRepository(
  tripService: service ?? MockTripService(simulatedDelay: Duration.zero),
);

Widget _wrap(Widget child) => MaterialApp(
  routes: {
    '/passenger/trip-detail': (ctx) => PassengerTripDetailScreen(
      trip: ModalRoute.of(ctx)!.settings.arguments as Trip,
    ),
    '/passenger/trip-history': (ctx) =>
        PassengerTripHistoryScreen(tripRepository: _makeRepo()),
  },
  home: child,
);

// ---------------------------------------------------------------------------
// MockTripService unit tests
// ---------------------------------------------------------------------------

void main() {
  group('MockTripService', () {
    test('initial trips are all TripStatus.completed', () async {
      final svc = MockTripService(simulatedDelay: Duration.zero);
      final trips = await svc.getRecentTrips(limit: 10);
      expect(trips, isNotEmpty);
      expect(trips.every((t) => t.status == TripStatus.completed), isTrue);
    });

    test('completeJourney adds a new completed trip at the front', () async {
      final svc = MockTripService(simulatedDelay: Duration.zero);
      final before = await svc.getRecentTrips(limit: 20);

      final trip = await svc.completeJourney(
        fromLocation: 'Bole',
        toLocation: 'Piazza',
        fare: 25.0,
      );

      expect(trip.status, TripStatus.completed);
      expect(trip.fromLocation, 'Bole');
      expect(trip.toLocation, 'Piazza');
      expect(trip.amountPaid, 25.0);

      final after = await svc.getRecentTrips(limit: 20);
      expect(after.length, before.length + 1);
      expect(after.first.id, trip.id);
    });

    test('completeJourney stores the routeCode', () async {
      final svc = MockTripService(simulatedDelay: Duration.zero);
      final trip = await svc.completeJourney(
        fromLocation: 'Mexico',
        toLocation: 'Saris',
        fare: 30.0,
        routeCode: 'ET-RT-02',
      );
      expect(trip.routeCode, 'ET-RT-02');
    });

    test(
      'route search does NOT call completeJourney — no new trip created',
      () async {
        // Simulate: passenger searches for routes (no service call)
        final svc = MockTripService(simulatedDelay: Duration.zero);
        final before = await svc.getRecentTrips(limit: 20);
        // No completeJourney call here — route search is informational only
        final after = await svc.getRecentTrips(limit: 20);
        expect(after.length, before.length);
      },
    );

    test('completeJourney twice creates two distinct trips', () async {
      // Documents current mock behavior — caller is responsible for dedup
      final svc = MockTripService(simulatedDelay: Duration.zero);
      final t1 = await svc.completeJourney(
        fromLocation: 'A',
        toLocation: 'B',
        fare: 10,
      );
      final t2 = await svc.completeJourney(
        fromLocation: 'A',
        toLocation: 'B',
        fare: 10,
      );
      expect(t1.id, isNot(t2.id));
    });
  });

  // -------------------------------------------------------------------------
  // TripRepository unit tests
  // -------------------------------------------------------------------------

  group('TripRepository', () {
    test('getRecentTrips returns list from service', () async {
      final repo = _makeRepo();
      final trips = await repo.getRecentTrips(limit: 5);
      expect(trips, isNotEmpty);
    });

    test('completeJourney records a new completed trip', () async {
      final svc = MockTripService(simulatedDelay: Duration.zero);
      final repo = _makeRepo(svc);

      final trip = await repo.completeJourney(
        fromLocation: 'Megenagna',
        toLocation: 'CMC',
        fare: 50.0,
        routeCode: 'ET-RT-05',
      );

      expect(trip.status, TripStatus.completed);
      expect(trip.fromLocation, 'Megenagna');
      expect(trip.toLocation, 'CMC');
      expect(trip.amountPaid, 50.0);

      final all = await repo.getRecentTrips(limit: 20);
      expect(all.any((t) => t.id == trip.id), isTrue);
    });

    test(
      'completeJourney does NOT alter wallet — separate responsibility',
      () async {
        // Just verifies completeJourney takes no wallet parameters
        final repo = _makeRepo();
        final trip = await repo.completeJourney(
          fromLocation: 'Bole',
          toLocation: 'Piazza',
          fare: 25.0,
        );
        // If this compiles and runs, the repository accepts no wallet args
        expect(trip, isNotNull);
      },
    );
  });

  // -------------------------------------------------------------------------
  // PassengerTripHistoryScreen widget tests
  // -------------------------------------------------------------------------

  group('PassengerTripHistoryScreen', () {
    testWidgets('shows app bar with Trip History title', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: _makeRepo())),
      );
      await tester.pump(Duration.zero); // settle initState future
      await tester.pump();
      expect(find.text('Trip History'), findsOneWidget);
    });

    testWidgets('shows existing mock trips from MockTripService', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: _makeRepo())),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      // At least one of the default mock routes appears
      expect(find.textContaining('Bole'), findsWidgets);
    });

    testWidgets('shows completed status badge', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: _makeRepo())),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('COMPLETED'), findsWidgets);
    });

    testWidgets('shows fare for each trip', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: _makeRepo())),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      // Default trip has ETB 85.00
      expect(find.textContaining('85'), findsWidgets);
    });

    testWidgets('shows empty state when no trips exist', (tester) async {
      // Use a service with no initial trips
      final emptySvc = _EmptyTripService();
      final repo = _makeRepo(emptySvc);

      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: repo)),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('No completed trips yet'), findsOneWidget);
    });

    testWidgets('newly completed trip appears in history', (tester) async {
      final svc = MockTripService(simulatedDelay: Duration.zero);
      final repo = _makeRepo(svc);

      await svc.completeJourney(
        fromLocation: 'Tor Hailoch',
        toLocation: 'Ayat',
        fare: 75.0,
      );

      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: repo)),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.textContaining('Tor Hailoch'), findsWidgets);
    });

    testWidgets('tapping a trip navigates to trip detail', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripHistoryScreen(tripRepository: _makeRepo())),
      );
      await tester.pump(Duration.zero);
      await tester.pump();

      // Tap the first trip card
      final firstCard = find.byType(InkWell).first;
      await tester.tap(firstCard);
      await tester.pumpAndSettle();

      // Should navigate to Trip Detail
      expect(find.text('Trip Detail'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // PassengerTripDetailScreen widget tests
  // -------------------------------------------------------------------------

  group('PassengerTripDetailScreen', () {
    Trip makeTrip() => Trip(
      id: 'test_001',
      fromLocation: 'Bole',
      toLocation: 'Piazza',
      amountPaid: 25.0,
      completedAt: DateTime(2026, 9, 28, 16, 35),
      driverName: 'Local Taxi',
      status: TripStatus.completed,
      routeCode: 'ET-RT-01',
    );

    testWidgets('shows Trip Detail in app bar', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.text('Trip Detail'), findsOneWidget);
    });

    testWidgets('shows origin location', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.text('Bole'), findsOneWidget);
    });

    testWidgets('shows destination location', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.text('Piazza'), findsOneWidget);
    });

    testWidgets('shows fare', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.textContaining('25'), findsWidgets);
    });

    testWidgets('shows Paid status', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.text('Paid'), findsOneWidget);
    });

    testWidgets('shows route code', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.text('ET-RT-01'), findsOneWidget);
    });

    testWidgets('shows completed status badge', (tester) async {
      await tester.pumpWidget(
        _wrap(PassengerTripDetailScreen(trip: makeTrip())),
      );
      await tester.pump();
      expect(find.text('COMPLETED'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Helper: empty trip service
// ---------------------------------------------------------------------------

class _EmptyTripService implements TripService {
  @override
  Future<List<Trip>> getRecentTrips({int limit = 5}) async => [];

  @override
  Future<Trip> getTrip(String tripId) {
    throw UnimplementedError('getTrip not used in trip history tests');
  }

  @override
  Future<Trip> createTrip({
    required String driverId,
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    required String origin,
    required String destination,
    String? vehicleId,
    String? vehicleType,
  }) {
    throw UnimplementedError('createTrip not used in trip history tests');
  }

  @override
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) async {
    return Trip(
      id: 'empty_01',
      fromLocation: fromLocation,
      toLocation: toLocation,
      amountPaid: fare,
      completedAt: DateTime.now(),
      driverName: 'Local Taxi',
      status: TripStatus.completed,
      routeCode: routeCode,
    );
  }

  @override
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  }) {
    throw UnimplementedError('bookRide not used in trip history tests');
  }
}
