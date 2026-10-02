import '../models/driver_route.dart';
import '../services/mock/mock_driver_route_service.dart';

class DriverRouteRepository {
  DriverRouteRepository({DriverRouteService? service})
      : _service = service ?? MockDriverRouteService();

  final DriverRouteService _service;

  Future<List<DriverRoute>> getAssignedRoutes() => _service.getAssignedRoutes();
  Future<DriverRoute?> getRouteById(String id) => _service.getRouteById(id);
}
