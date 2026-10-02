import '../models/trip.dart';
import '../services/mock/mock_trip_service.dart';

class TripRepository {
  TripRepository({TripService? tripService})
      : _tripService = tripService ?? MockTripService();

  final TripService _tripService;

  Future<List<Trip>> getRecentTrips({int limit = 5}) =>
      _tripService.getRecentTrips(limit: limit);

  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) =>
      _tripService.completeJourney(
        fromLocation: fromLocation,
        toLocation: toLocation,
        fare: fare,
        routeCode: routeCode,
      );

  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  }) =>
      _tripService.bookRide(
        fromLocation: fromLocation,
        toLocation: toLocation,
        estimatedFare: estimatedFare,
        routeCode: routeCode,
      );
}
