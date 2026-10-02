import '../../core/network/api_client.dart';
import '../../models/passenger_route.dart';
import '../mock/mock_passenger_route_service.dart';

class ApiPassengerRouteService implements PassengerRouteService {
  ApiPassengerRouteService({required this.client});

  final ApiClient client;

  Future<List<Map<String, dynamic>>> _fetchRawRoutes() async {
    final response = await client.get('/routes');
    return response.asMapList;
  }

  Future<List<Map<String, dynamic>>> _fetchRouteQuotes(
    List<Map<String, dynamic>> routes,
  ) async {
    return Future.wait(
      routes.map((route) async {
        final stops = _sortedStops(route['stops']);
        if (stops.length < 2) {
          return <String, dynamic>{'routeId': route['id'], 'fare': 0.0};
        }

        try {
          final quote = await client.post(
            '/fares/calculate',
            body: {
              'routeId': route['id'],
              'originStopId': stops.first['id'],
              'destinationStopId': stops.last['id'],
            },
          );
          return <String, dynamic>{
            'routeId': route['id'],
            'fare': (quote.asMap['fare'] as num?)?.toDouble() ?? 0.0,
          };
        } catch (_) {
          return <String, dynamic>{'routeId': route['id'], 'fare': 0.0};
        }
      }),
    );
  }

  @override
  Future<List<TaxiStation>> getStations() async {
    final routes = await _fetchRawRoutes();
    final stops = <String, Map<String, dynamic>>{};

    for (final route in routes) {
      for (final stop in _sortedStops(route['stops'])) {
        final id = _string(stop['id']);
        if (id != null) stops[id] = stop;
      }
    }

    final values = stops.values.toList(growable: false);
    final coordinates = values
        .map(
          (s) => (
            lat: (s['latitude'] as num?)?.toDouble(),
            lon: (s['longitude'] as num?)?.toDouble(),
          ),
        )
        .where((p) => p.lat != null && p.lon != null)
        .toList(growable: false);

    final minLat = coordinates.isEmpty
        ? null
        : coordinates.map((p) => p.lat!).reduce((a, b) => a < b ? a : b);
    final maxLat = coordinates.isEmpty
        ? null
        : coordinates.map((p) => p.lat!).reduce((a, b) => a > b ? a : b);
    final minLon = coordinates.isEmpty
        ? null
        : coordinates.map((p) => p.lon!).reduce((a, b) => a < b ? a : b);
    final maxLon = coordinates.isEmpty
        ? null
        : coordinates.map((p) => p.lon!).reduce((a, b) => a > b ? a : b);

    return List.generate(values.length, (index) {
      final stop = values[index];
      final lat = (stop['latitude'] as num?)?.toDouble();
      final lon = (stop['longitude'] as num?)?.toDouble();

      final mapX = lon != null &&
              minLon != null &&
              maxLon != null &&
              maxLon > minLon
          ? (lon - minLon) / (maxLon - minLon)
          : (index % 5) / 4.0;

      final mapY = lat != null &&
              minLat != null &&
              maxLat != null &&
              maxLat > minLat
          ? 1 - (lat - minLat) / (maxLat - minLat)
          : (index ~/ 5) /
              ((values.length / 5).ceil().clamp(1, 100).toDouble());

      return TaxiStation(
        id: _string(stop['id']) ?? 'stop-$index',
        name: _string(stop['name']) ?? 'Stop',
        label: _string(stop['name']) ?? 'Stop',
        mapX: mapX.clamp(0.0, 1.0).toDouble(),
        mapY: mapY.clamp(0.0, 1.0).toDouble(),
        isHub: index == 0 || index % 5 == 0,
      );
    });
  }

  @override
  Future<List<PassengerRoute>> getAllRoutes() async {
    final raw = await _fetchRawRoutes();
    final quotes = await _fetchRouteQuotes(raw);
    final fareByRoute = <String, double>{
      for (final quote in quotes)
        if (_string(quote['routeId']) != null)
          _string(quote['routeId'])!:
              (quote['fare'] as num?)?.toDouble() ?? 0.0,
    };

    return raw
        .map(
          (route) => _toModel(
            route,
            fareByRoute[_string(route['id'])] ?? 0.0,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PassengerRoute>> searchByDestination(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const [];

    final routes = await getAllRoutes();
    return routes
        .where(
          (route) =>
              route.endLabel.toLowerCase().contains(normalized) ||
              route.endStation.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  @override
  Future<List<PassengerRoute>> getRoutesToStation(String stationId) async {
    final routes = await getAllRoutes();
    return routes
        .where(
          (route) =>
              route.endStation == stationId ||
              route.startStation == stationId,
        )
        .toList(growable: false);
  }

  @override
  Future<List<PassengerRoute>> searchRoutes({
    required String fromQuery,
    required String toQuery,
  }) async {
    final from = fromQuery.trim().toLowerCase();
    final to = toQuery.trim().toLowerCase();
    final routes = await getAllRoutes();

    return routes.where((route) {
      final fromMatch = from.isEmpty ||
          route.startLabel.toLowerCase().contains(from) ||
          route.startStation.toLowerCase().contains(from);
      final toMatch = to.isEmpty ||
          route.endLabel.toLowerCase().contains(to) ||
          route.endStation.toLowerCase().contains(to);
      return fromMatch && toMatch;
    }).toList(growable: false);
  }

  PassengerRoute _toModel(
    Map<String, dynamic> route,
    double fare,
  ) {
    final stops = _sortedStops(route['stops']);
    final origin = stops.isNotEmpty
        ? (_string(stops.first['name']) ?? _string(route['origin']) ?? 'Origin')
        : (_string(route['origin']) ?? 'Origin');
    final destination = stops.isNotEmpty
        ? (_string(stops.last['name']) ??
            _string(route['destination']) ??
            'Destination')
        : (_string(route['destination']) ?? 'Destination');

    return PassengerRoute(
      id: _string(route['id']) ?? '',
      name: _string(route['name']) ?? (origin + ' → ' + destination),
      startStation:
          stops.isNotEmpty ? (_string(stops.first['id']) ?? '') : '',
      endStation:
          stops.isNotEmpty ? (_string(stops.last['id']) ?? '') : '',
      startLabel: origin,
      endLabel: destination,
      fare: fare,
      isAvailable:
          (_string(route['status']) ?? 'ACTIVE') == 'ACTIVE' && fare > 0,
      routeCode: _string(route['code']),
      intermediateStops: stops.length > 2
          ? stops
              .sublist(1, stops.length - 1)
              .map((s) => _string(s['name']) ?? 'Stop')
              .toList(growable: false)
          : const [],
    );
  }

  static List<Map<String, dynamic>> _sortedStops(Object? raw) {
    if (raw is! List) return const [];

    final stops = raw.whereType<Map<String, dynamic>>().toList();
    stops.sort(
      (a, b) => ((a['sequence'] as num?) ?? 0)
          .compareTo((b['sequence'] as num?) ?? 0),
    );
    return stops;
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
