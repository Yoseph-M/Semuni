import '../../core/network/api_client.dart';
import '../../models/fare_quote.dart';
import '../../models/passenger_route.dart';
import '../mock/mock_passenger_route_service.dart';

/// Route discovery against the NestJS backend.
///
/// Everything identity-related comes from the API: route ids, stop ids (which
/// fare quotes and trips require), names for display, and coordinates. Route
/// names are never used as identity, and fares are read from the fare engine,
/// never invented here.
///
/// Fares arrive in minor units (santim) and are converted once, at the edge,
/// into ETB for display — `PassengerRoute.fare` is an ETB amount.
class ApiPassengerRouteService implements PassengerRouteService {
  ApiPassengerRouteService({required this.client});

  final ApiClient client;

  Future<List<Map<String, dynamic>>> _fetchRawRoutes() async {
    final response = await client.get('/routes');
    return response.asMapList;
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
        .map((s) => (lat: _number(s['latitude']), lon: _number(s['longitude'])))
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
      final lat = _number(stop['latitude']);
      final lon = _number(stop['longitude']);

      // Coordinates are projected into 0..1 for the schematic map canvas. When
      // a stop has none, it is laid out on a deterministic grid instead of
      // being dropped, so every backend stop remains selectable.
      final mapX = lon != null && minLon != null && maxLon != null && maxLon > minLon
          ? (lon - minLon) / (maxLon - minLon)
          : (index % 5) / 4.0;

      final mapY = lat != null && minLat != null && maxLat != null && maxLat > minLat
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
    // Quoted in santim; the model displays ETB, so convert once here.
    final fareEtbByRoute = <String, double>{
      for (final quote in quotes)
        if (_string(quote['routeId']) != null)
          _string(quote['routeId'])!:
              ((quote['fareMinor'] as num?)?.toDouble() ?? 0) / 100,
    };

    return raw
        .map(
          (route) => _toModel(route, fareEtbByRoute[_string(route['id'])] ?? 0),
        )
        .toList(growable: false);
  }

  @override
  Future<FareQuote> quoteFare({
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    String? vehicleType,
  }) async {
    final response = await client.post(
      '/fares/calculate',
      body: {
        'routeId': routeId,
        'originStopId': originStopId,
        'destinationStopId': destinationStopId,
        'vehicleType': ?vehicleType,
      },
    );
    return _quoteFromJson(response.asMap);
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
              route.endStation == stationId || route.startStation == stationId,
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

  /// Quotes the full route (first → last stop) for each route, for display.
  ///
  /// A route whose journey cannot be quoted right now (no active tariff rule,
  /// too few stops) is reported as ETB 0 and shown as unavailable rather than
  /// inventing a price. The authoritative quote for a chosen segment is fetched
  /// again in the payment flow.
  Future<List<Map<String, dynamic>>> _fetchRouteQuotes(
    List<Map<String, dynamic>> routes,
  ) async {
    return Future.wait(
      routes.map((route) async {
        final stops = _sortedStops(route['stops']);
        final routeId = _string(route['id']);
        if (stops.length < 2 || routeId == null) {
          return <String, dynamic>{'routeId': routeId, 'fareMinor': 0};
        }

        final originId = _string(stops.first['id']);
        final destinationId = _string(stops.last['id']);
        if (originId == null || destinationId == null) {
          return <String, dynamic>{'routeId': routeId, 'fareMinor': 0};
        }

        try {
          final quote = await quoteFare(
            routeId: routeId,
            originStopId: originId,
            destinationStopId: destinationId,
          );
          return <String, dynamic>{
            'routeId': routeId,
            'fareMinor': quote.fareMinor,
          };
        } catch (_) {
          // A missing/ambiguous tariff for one route must not blank the whole
          // discovery list.
          return <String, dynamic>{'routeId': routeId, 'fareMinor': 0};
        }
      }),
    );
  }

  static FareQuote _quoteFromJson(Map<String, dynamic> data) {
    final fare = data['fare'];
    return FareQuote(
      // The fare engine speaks minor units; a fractional value would be a
      // backend bug, so it is not silently rounded here.
      fareMinor: fare is num ? fare.toInt() : 0,
      currency: _string(data['currency']) ?? 'ETB',
      routeId: _string(data['routeId']) ?? '',
      originStopId: _string(data['originStopId']) ?? '',
      destinationStopId: _string(data['destinationStopId']) ?? '',
      routeName: _string(data['routeName']),
      originStopName: _string(data['originStopName']),
      destinationStopName: _string(data['destinationStopName']),
      tariffId: _string(data['tariffId']),
      tariffVersion: _string(data['tariffVersion']),
      tariffRuleId: _string(data['tariffRuleId']),
    );
  }

  PassengerRoute _toModel(Map<String, dynamic> route, double fareEtb) {
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
      name: _string(route['name']) ?? '$origin → $destination',
      startStation: stops.isNotEmpty ? (_string(stops.first['id']) ?? '') : '',
      endStation: stops.isNotEmpty ? (_string(stops.last['id']) ?? '') : '',
      startLabel: origin,
      endLabel: destination,
      fare: fareEtb,
      // A price of zero means "no official fare published", not "free ride":
      // the route is shown but cannot be paid.
      isAvailable: (_string(route['status']) ?? 'ACTIVE') == 'ACTIVE' && fareEtb > 0,
      routeCode: _string(route['code']),
      intermediateStops: stops.length > 2
          ? stops
              .sublist(1, stops.length - 1)
              .map((s) => _string(s['name']) ?? 'Stop')
              .toList(growable: false)
          : const [],
      stops: stops
          .map(
            (s) => RouteStop(
              id: _string(s['id']) ?? '',
              name: _string(s['name']) ?? 'Stop',
              sequence: (_number(s['sequence']) ?? 0).toInt(),
              latitude: _number(s['latitude']),
              longitude: _number(s['longitude']),
            ),
          )
          .where((s) => s.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  /// Sorts stops by sequence, tolerating the string-encoded numerics TypeORM
  /// can produce.
  static List<Map<String, dynamic>> _sortedStops(Object? raw) {
    if (raw is! List) return const [];

    final stops = raw.whereType<Map<String, dynamic>>().toList();
    stops.sort(
      (a, b) => (_number(a['sequence']) ?? 0).compareTo(
        _number(b['sequence']) ?? 0,
      ),
    );
    return stops;
  }

  /// Reads a number that may arrive as a JSON number or a string (PostgreSQL
  /// `decimal` columns are serialized as strings).
  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
