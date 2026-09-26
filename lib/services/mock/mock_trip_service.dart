import '../../models/trip.dart';

/// Abstract service for fetching trip data.
///
/// Follows the architecture:
/// UI → TripRepository → TripService (Mock or Real API)
abstract interface class TripService {
  /// Fetches the recent trips taken by the passenger.
  Future<List<Trip>> getRecentTrips({int limit = 5});
}

/// Mock implementation of [TripService].
///
/// Provides realistic Ethiopian taxi trip records for frontend demonstration.
class MockTripService implements TripService {
  /// Simulated latency to replicate real-world API behavior.
  static const Duration _simulatedDelay = Duration(milliseconds: 400);

  @override
  Future<List<Trip>> getRecentTrips({int limit = 5}) async {
    await Future<void>.delayed(_simulatedDelay);

    final now = DateTime.now();

    final List<Trip> trips = [
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

    return trips.take(limit).toList();
  }
}
