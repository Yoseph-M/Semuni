import '../services/api/interfaces.dart';
import '../models/trip.dart';

class TripRepository {
  TripRepository({TripService? tripService})
    : _tripService = tripService ?? const _EmptyTripService();

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
  }) => _tripService.createTrip(
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
  }) => _tripService.completeJourney(
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
  }) => _tripService.bookRide(
    fromLocation: fromLocation,
    toLocation: toLocation,
    estimatedFare: estimatedFare,
    routeCode: routeCode,
  );
}

class _EmptyTripService implements TripService {
  const _EmptyTripService();

  @override
  Future<List<Trip>> getRecentTrips({int limit = 5}) async => const [];

  @override
  Future<Trip> getTrip(String tripId) async =>
      throw StateError('No trip service configured');

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
  }) async => throw StateError('No trip service configured');

  @override
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) async => throw StateError('No trip service configured');

  @override
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  }) async => throw StateError('No trip service configured');
}
