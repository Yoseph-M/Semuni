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

  /// Records a completed taxi journey in the trip history.
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) async {
    return _tripService.completeJourney(
      fromLocation: fromLocation,
      toLocation: toLocation,
      fare: fare,
      routeCode: routeCode,
    );
  }

  /// Books a new ride request for the passenger.
  ///
  /// Returns a [Trip] with [TripStatus.requested] representing the pending booking.
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  }) async {
    return _tripService.bookRide(
      fromLocation: fromLocation,
      toLocation: toLocation,
      estimatedFare: estimatedFare,
      routeCode: routeCode,
    );
  }
}
