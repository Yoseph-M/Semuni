import '../models/driver_route.dart';
import '../services/mock/mock_driver_route_service.dart';

/// Repository for driver routes.
///
/// Mediates between the presentation layer and the driver route service layer.
///
/// Architecture:
/// UI → DriverRouteRepository → DriverRouteService (Mock or Real API)
class DriverRouteRepository {
  DriverRouteRepository({DriverRouteService? service})
    : _service = service ?? MockDriverRouteService();

  final DriverRouteService _service;

  /// Retrieves all assigned routes for the authenticated driver.
  Future<List<DriverRoute>> getAssignedRoutes() => _service.getAssignedRoutes();

  /// Retrieves a specific route by ID.
  Future<DriverRoute?> getRouteById(String id) => _service.getRouteById(id);
}
