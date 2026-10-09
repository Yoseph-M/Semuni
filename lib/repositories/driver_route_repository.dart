import '../services/api/interfaces.dart';
import '../models/driver_route.dart';

class DriverRouteRepository {
  DriverRouteRepository({DriverRouteService? service})
    : _service = service ?? const _EmptyDriverRouteService();

  final DriverRouteService _service;

  Future<List<DriverRoute>> getAssignedRoutes() => _service.getAssignedRoutes();
  Future<DriverRoute?> getRouteById(String id) => _service.getRouteById(id);
}

class _EmptyDriverRouteService implements DriverRouteService {
  const _EmptyDriverRouteService();

  @override
  Future<List<DriverRoute>> getAssignedRoutes() async => const [];

  @override
  Future<DriverRoute?> getRouteById(String id) async => null;
}
