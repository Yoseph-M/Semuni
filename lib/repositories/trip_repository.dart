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
}
