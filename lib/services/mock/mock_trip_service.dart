import '../../models/trip.dart';
import '../api/interfaces.dart';

export '../api/interfaces.dart' show TripService;

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
  Future<Trip> getTrip(String tripId) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    final matches = _trips.where((trip) => trip.id == tripId);
    if (matches.isEmpty) {
      throw StateError('Unknown trip $tripId');
    }
    return matches.first;
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
  }) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }

    final newTrip = Trip(
      id: 'TRP-${++_idCounter}',
      fromLocation: origin,
      toLocation: destination,
      amountPaid: 85.00,
      completedAt: DateTime.now(),
      driverName: 'Mock Driver',
      status: TripStatus.requested,
      fareMinor: 8500,
      paymentStatus: 'UNPAID',
    );

    _trips.insert(0, newTrip);
    return newTrip;
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

  void markTripPaid(String tripId, String receiptNumber) {
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index == -1) return;

    final old = _trips[index];
    _trips[index] = Trip(
      id: old.id,
      fromLocation: old.fromLocation,
      toLocation: old.toLocation,
      amountPaid: old.amountPaid,
      completedAt: DateTime.now(),
      driverName: old.driverName,
      status: TripStatus.completed,
      routeCode: old.routeCode,
      fareMinor: old.fareMinor,
      paymentStatus: 'PAID',
      receiptNumber: receiptNumber,
    );
  }
}
