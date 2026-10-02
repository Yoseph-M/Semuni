import '../../core/network/api_client.dart';
import '../../models/trip.dart';
import '../mock/mock_trip_service.dart';

/// Trips against the NestJS backend.
///
/// A trip is the financial unit the backend prices and settles: the client
/// sends authoritative identifiers (route and stop UUIDs) plus the driver it is
/// riding with, and the server recalculates and stores the fare. No client-side
/// fare is trusted, and no trip is fabricated locally.
class ApiTripService implements TripService {
  ApiTripService({required this.client});

  final ApiClient client;

  @override
  Future<List<Trip>> getRecentTrips({int limit = 5}) async {
    final response = await client.get('/trips');
    return response.asMapList.take(limit).map(_toModel).toList(growable: false);
  }

  /// Loads one trip, so the payer can re-read the authoritative state (for
  /// example after a payment timeout) instead of guessing.
  @override
  Future<Trip> getTrip(String tripId) async {
    final response = await client.get('/trips/$tripId');
    return _toModel(response.asMap);
  }

  /// Creates a trip from backend identifiers.
  ///
  /// [origin] and [destination] are required by the API as descriptive labels
  /// of the chosen stops; the server ignores them for identity and stores its
  /// own stop-name snapshots. [driverId] is the driver's **user** id, which is
  /// what `GET /drivers/available` returns.
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
    final response = await client.post(
      '/trips',
      body: {
        'driverId': driverId,
        'routeId': routeId,
        'originStopId': originStopId,
        'destinationStopId': destinationStopId,
        'origin': origin,
        'destination': destination,
        'vehicleId': ?vehicleId,
        'vehicleType': ?vehicleType,
      },
    );
    return _toModel(response.asMap);
  }

  @override
  Future<Trip> completeJourney({
    required String fromLocation,
    required String toLocation,
    required double fare,
    String? routeCode,
  }) {
    throw StateError(
      'completeJourney has no backend equivalent; create a trip with '
      'createTrip() and pay it through /payments/trip.',
    );
  }

  @override
  Future<Trip> bookRide({
    required String fromLocation,
    required String toLocation,
    required double estimatedFare,
    String? routeCode,
  }) {
    throw StateError(
      'bookRide is mock-only; create a trip with createTrip().',
    );
  }

  static Trip _toModel(Map<String, dynamic> data) {
    final status = (_string(data['status']) ?? 'PENDING').toUpperCase();
    final fareMinor = (data['fareAmount'] as num?)?.toInt() ?? 0;
    // List responses carry `amountPaid` (ETB) for convenience; single-trip
    // responses do not, so the minor-unit fare is the fallback.
    final rawAmountPaid = data['amountPaid'];
    final amountPaid = rawAmountPaid is num
        ? rawAmountPaid.toDouble()
        : fareMinor / 100;

    return Trip(
      id: _string(data['id']) ?? '',
      fromLocation: _string(data['origin']) ?? '',
      toLocation: _string(data['destination']) ?? '',
      amountPaid: amountPaid,
      completedAt:
          DateTime.tryParse(
            _string(data['completedAt']) ?? _string(data['createdAt']) ?? '',
          ) ??
          DateTime.now(),
      driverName: _string(data['driverName']) ?? 'Driver',
      status: switch (status) {
        'COMPLETED' => TripStatus.completed,
        'CANCELLED' => TripStatus.cancelled,
        'IN_PROGRESS' => TripStatus.inProgress,
        _ => TripStatus.requested,
      },
      routeCode: _string(data['routeCode']),
      fareMinor: fareMinor,
      paymentStatus: (_string(data['paymentStatus']) ?? 'UNPAID').toUpperCase(),
      receiptNumber: _string(data['receiptNumber']),
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
