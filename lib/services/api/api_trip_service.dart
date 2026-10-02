import '../../core/network/api_client.dart';
import '../../models/trip.dart';
import '../mock/mock_trip_service.dart';

class ApiTripService implements TripService {
  ApiTripService({required this.client});

  final ApiClient client;

  @override
  Future<List<Trip>> getRecentTrips({int limit = 5}) async {
    final response = await client.get('/trips');
    return response.asMapList.take(limit).map(_toModel).toList(growable: false);
  }

  Future<Trip> createTrip({
    required String driverId,
    required String routeId,
    required String originStopId,
    required String destinationStopId,
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
        if (vehicleId != null) 'vehicleId': vehicleId,
        if (vehicleType != null) 'vehicleType': vehicleType,
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
      'completeJourney requires an authoritative backend trip; use createTrip().',
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
      'bookRide requires an authoritative backend trip; use createTrip().',
    );
  }

  static Trip _toModel(Map<String, dynamic> data) {
    final status = (_string(data['status']) ?? 'PENDING').toUpperCase();
    final rawAmountPaid = data['amountPaid'];
    final amountPaid = rawAmountPaid is num
        ? rawAmountPaid.toDouble()
        : ((data['fareAmount'] as num?)?.toDouble() ?? 0) / 100;

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
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
