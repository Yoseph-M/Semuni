import '../../core/network/api_client.dart';
import '../../models/driver_route.dart';
import '../mock/mock_driver_route_service.dart';

class ApiDriverRouteService implements DriverRouteService {
  ApiDriverRouteService({required this.client});

  final ApiClient client;

  @override
  Future<List<DriverRoute>> getAssignedRoutes() async {
    final response = await client.get('/drivers/me/routes');
    return response.asMapList.map(_toModel).toList(growable: false);
  }

  @override
  Future<DriverRoute?> getRouteById(String id) async {
    final response = await client.get('/routes/$id');
    return _toModel(response.asMap);
  }

  static DriverRoute _toModel(Map<String, dynamic> data) {
    final rawStops = data['stops'];
    final stops = rawStops is List
        ? rawStops.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    stops.sort(
      (a, b) =>
          ((a['sequence'] as num?) ?? 0).compareTo((b['sequence'] as num?) ?? 0),
    );

    final origin = stops.isNotEmpty
        ? (_string(stops.first['name']) ??
            _string(data['origin']) ??
            '')
        : (_string(data['origin']) ?? '');
    final destination = stops.isNotEmpty
        ? (_string(stops.last['name']) ??
            _string(data['destination']) ??
            '')
        : (_string(data['destination']) ?? '');

    return DriverRoute(
      id: _string(data['id']) ?? '',
      name: _string(data['name']) ?? '$origin → $destination',
      startLocation: origin,
      endLocation: destination,
      fare: 0.0,
      isActive: (_string(data['status']) ?? 'ACTIVE') == 'ACTIVE',
      routeCode: _string(data['code']),
      intermediateStops: stops.length > 2
          ? stops
              .sublist(1, stops.length - 1)
              .map((s) => _string(s['name']) ?? 'Stop')
              .toList(growable: false)
          : const [],
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
