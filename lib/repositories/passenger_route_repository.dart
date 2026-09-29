import '../models/passenger_route.dart';
import '../services/mock/mock_passenger_route_service.dart';

/// Repository for passenger route discovery operations.
///
/// Mediates between the presentation layer and the route service layer.
///
/// Architecture:
/// UI → PassengerRouteRepository → PassengerRouteService (Mock or Real API)
class PassengerRouteRepository {
  PassengerRouteRepository({PassengerRouteService? service})
    : _service = service ?? MockPassengerRouteService();

  final PassengerRouteService _service;

  /// Retrieves all stations on the SMUNI taxi network.
  Future<List<TaxiStation>> getStations() => _service.getStations();

  /// Retrieves all available passenger routes.
  Future<List<PassengerRoute>> getAllRoutes() => _service.getAllRoutes();

  /// Searches routes where the destination matches [query].
  ///
  /// Returns an empty list when [query] is blank.
  Future<List<PassengerRoute>> searchByDestination(String query) =>
      _service.searchByDestination(query);

  /// Returns all routes that serve [stationId] as a destination.
  Future<List<PassengerRoute>> getRoutesToStation(String stationId) =>
      _service.getRoutesToStation(stationId);
}
