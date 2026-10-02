import '../../models/trip.dart';

/// Abstract service for fetching trip data.
///
/// Follows the architecture:
/// UI → TripRepository → TripService (Mock or Real API)
abstract interface class TripService {
  /// Fetches the recent trips taken by the passenger.
  Future<List<Trip>> getRecentTrips({int limit = 5});

  /// Records a completed taxi journey.
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  });

  /// Books a new ride request for the passenger.
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  });
}

/// Mock implementation of [TripService].
///
/// Provides realistic Ethiopian taxi trip records for frontend demonstration.
class MockTripService implements TripService {
  MockTripService({this.simulatedDelay = const Duration(milliseconds: 400)});

  /// Simulated latency to replicate real-world API behavior.
  final Duration simulatedDelay;

  late final List<Trip> _trips = _generateInitialTrips();

  static int _idCounter = 0;

  static List<Trip> _generateInitialTrips() {
    final now = DateTime.now();
    return [
      Trip(
        id: 'trip_001',
        fromLocation: 'Bole',
        toLocation: 'Piazza',
        amountPaid: 85.00,
        completedAt: DateTime(now.year, now.month, now.day, 8, 42),
        driverName: 'Abebe T.',
        status: TripStatus.completed,
      ),
      Trip(
        id: 'trip_002',
        fromLocation: 'Mexico',
        toLocation: 'Saris',
        amountPaid: 70.00,
        completedAt: DateTime(now.year, now.month, now.day - 1, 17, 20),
        driverName: 'Dawit K.',
        status: TripStatus.completed,
      ),
      Trip(
        id: 'trip_003',
        fromLocation: 'Megenagna',
        toLocation: 'CMC',
        amountPaid: 50.00,
        completedAt: DateTime(now.year, now.month, now.day - 2, 12, 15),
        driverName: 'Ermias G.',
        status: TripStatus.completed,
      ),
      Trip(
        id: 'trip_004',
        fromLocation: 'Tor Hailoch',
        toLocation: 'Ayat',
        amountPaid: 120.00,
        completedAt: DateTime(now.year, now.month, now.day - 3, 9, 30),
        driverName: 'Kassahun M.',
        status: TripStatus.completed,
      ),
    ];
  }

  @override
  Future<List<Trip>> getRecentTrips({int limit = 5}) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    return _trips.take(limit).toList();
  }

  @override
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    final newTrip = Trip(
      id: 'TRP-${++_idCounter}',
      fromLocation: fromLocation,
      toLocation: toLocation,
      amountPaid: fare,
      completedAt: DateTime.now(),
      driverName: 'Local Taxi',
      status: TripStatus.completed,
      routeCode: routeCode,
    );

    _trips.insert(0, newTrip);
    return newTrip;
  }

  @override
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    final newTrip = Trip(
      id: 'TRP-${++_idCounter}',
      fromLocation: fromLocation,
      toLocation: toLocation,
      amountPaid: estimatedFare,
      completedAt: DateTime.now(),
      driverName: 'Pending',
      status: TripStatus.requested,
      routeCode: routeCode,
    );

    _trips.insert(0, newTrip);
    return newTrip;
  }
}
