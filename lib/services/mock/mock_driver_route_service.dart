import '../../models/driver_route.dart';

/// Abstract service contract for retrieving driver route data.
///
/// Architecture:
/// UI → DriverRouteRepository → DriverRouteService (Mock or Real API)
abstract interface class DriverRouteService {
  /// Retrieves all routes assigned to the authenticated driver.
  Future<List<DriverRoute>> getAssignedRoutes();

  /// Retrieves a specific route by its identifier.
  Future<DriverRoute?> getRouteById(String id);
}

/// Mock implementation of [DriverRouteService].
///
/// Supplies generic placeholder routes and stops so the UI can be exercised
/// without a real backend, without preloading real corridor data or
/// hardcoded fare values. Replace with an API service when ready.
class MockDriverRouteService implements DriverRouteService {
  MockDriverRouteService({
    this.simulatedDelay = const Duration(milliseconds: 300),
    List<DriverRoute>? initialRoutes,
  }) : _routes = initialRoutes ?? _defaultRoutes();

  final Duration simulatedDelay;
  final List<DriverRoute> _routes;

  static List<DriverRoute> _defaultRoutes() {
    return List<DriverRoute>.generate(4, (i) {
      final n = i + 1;
      return DriverRoute(
        id: 'route_$n',
        name: 'Assigned Route $n',
        startLocation: 'Stop A$n',
        endLocation: 'Stop Z$n',
        fare: 0.00,
        isActive: i < 2,
        routeCode: '',
        distanceKm: null,
        estimatedDuration: null,
        intermediateStops: List<String>.generate(
          3,
          (j) => 'Intermediate ${String.fromCharCode(65 + j)}$n',
        ),
        operatingHours: null,
      );
    }, growable: false);
  }

  @override
  Future<List<DriverRoute>> getAssignedRoutes() async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    return List.unmodifiable(_routes);
  }

  @override
  Future<DriverRoute?> getRouteById(String id) async {
    if (simulatedDelay > Duration.zero) {
      await Future<void>.delayed(simulatedDelay);
    }
    try {
      return _routes.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }
}
