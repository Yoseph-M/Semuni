import '../services/api/interfaces.dart';
import '../models/fare_quote.dart';
import '../models/passenger_route.dart';

class PassengerRouteRepository {
  /// [service] is required in production wiring (`app.dart` injects the
  /// API-backed implementation). The mock fallback exists for the screens'
  /// legacy default construction in tests and is never used when the app wires
  /// its dependencies.
  PassengerRouteRepository({PassengerRouteService? service})
    : service = service ?? const _EmptyPassengerRouteService();

  final PassengerRouteService service;

  Future<List<TaxiStation>> getStations() => service.getStations();
  Future<List<PassengerRoute>> getAllRoutes() => service.getAllRoutes();
  Future<List<PassengerRoute>> searchByDestination(String query) =>
      service.searchByDestination(query);
  Future<List<PassengerRoute>> getRoutesToStation(String stationId) =>
      service.getRoutesToStation(stationId);
  Future<List<PassengerRoute>> searchRoutes({
    required String fromQuery,
    required String toQuery,
  }) => service.searchRoutes(fromQuery: fromQuery, toQuery: toQuery);

  /// The official price of a segment, from the backend's fare engine.
  Future<FareQuote> quoteFare({
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    String? vehicleType,
  }) => service.quoteFare(
    routeId: routeId,
    originStopId: originStopId,
    destinationStopId: destinationStopId,
    vehicleType: vehicleType,
  );
}

class _EmptyPassengerRouteService implements PassengerRouteService {
  const _EmptyPassengerRouteService();

  @override
  Future<List<TaxiStation>> getStations() async => const [];

  @override
  Future<List<PassengerRoute>> getAllRoutes() async => const [];

  @override
  Future<List<PassengerRoute>> searchByDestination(String query) async =>
      const [];

  @override
  Future<List<PassengerRoute>> getRoutesToStation(String stationId) async =>
      const [];

  @override
  Future<List<PassengerRoute>> searchRoutes({
    required String fromQuery,
    required String toQuery,
  }) async => const [];

  @override
  Future<FareQuote> quoteFare({
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    String? vehicleType,
  }) async => throw StateError('No route service configured');
}
