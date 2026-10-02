import '../models/passenger_route.dart';
import '../services/mock/mock_passenger_route_service.dart';

class PassengerRouteRepository {
  PassengerRouteRepository({PassengerRouteService? service, this.apiService})
      : _service = service;

  final PassengerRouteService? _service;
  final PassengerRouteService? apiService;

  PassengerRouteService get service =>
      _service ?? apiService ?? MockPassengerRouteService();

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
}
