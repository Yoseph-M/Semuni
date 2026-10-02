import '../models/trip.dart';
import '../services/mock/mock_trip_service.dart';

class TripRepository {
  TripRepository({TripService? tripService})
    : _tripService = tripService ?? MockTripService();

  final TripService _tripService;

  Future<List<Trip>> getRecentTrips({int limit = 5}) =>
      _tripService.getRecentTrips(limit: limit);

  Future<Trip> getTrip(String tripId) => _tripService.getTrip(tripId);

  /// Creates the trip the passenger is about to pay for.
  ///
  /// The fare is the backend's: no amount is sent from the client, so there is
  /// nothing to tamper with.
  Future<Trip> createTrip({
    required String driverId,
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    required String origin,
    required String destination,
    String? vehicleId,
    String? vehicleType,
  }) =>
      _tripService.createTrip(
        driverId: driverId,
        routeId: routeId,
        originStopId: originStopId,
        destinationStopId: destinationStopId,
        origin: origin,
        destination: destination,
        vehicleId: vehicleId,
        vehicleType: vehicleType,
      );

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
