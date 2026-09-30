import '../models/trip.dart';
import '../services/mock/mock_trip_service.dart';

/// Repository for passenger trip operations.
///
/// Mediates between the presentation layer and the trip service layer.
///
/// Architecture:
/// UI → TripRepository → TripService (Mock or Real API)
class TripRepository {
  TripRepository({TripService? tripService})
    : _tripService = tripService ?? MockTripService();

  final TripService _tripService;

  /// Retrieves a list of recent trips for the authenticated passenger.
  Future<List<Trip>> getRecentTrips({int limit = 5}) async {
    return _tripService.getRecentTrips(limit: limit);
  }

  /// Books a new ride and records it in the trip history.
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) async {
    return _tripService.bookRide(
      fromLocation: fromLocation,
      toLocation: toLocation,
      fare: fare,
      routeCode: routeCode,
    );
  }
}
