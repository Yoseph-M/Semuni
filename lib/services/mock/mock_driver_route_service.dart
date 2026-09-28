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
/// Supplies realistic Ethiopian urban taxi routes (Addis Ababa corridors)
/// with realistic fares, stops, distance, and active status.
class MockDriverRouteService implements DriverRouteService {
  MockDriverRouteService({
    this.simulatedDelay = const Duration(milliseconds: 300),
    List<DriverRoute>? initialRoutes,
  }) : _routes = initialRoutes ?? _defaultRoutes;

  final Duration simulatedDelay;
  final List<DriverRoute> _routes;

  static const List<DriverRoute> _defaultRoutes = [
    DriverRoute(
      id: 'route_01',
      name: 'Bole ⇄ Piazza',
      routeCode: 'ET-RT-01',
      startLocation: 'Bole Medhanialem',
      endLocation: 'Piazza (Churchill Ave)',
      fare: 25.00,
      isActive: true,
      distanceKm: 9.8,
      estimatedDuration: '30–40 min',
      intermediateStops: [
        'Olympia',
        'Meskel Square',
        'Stadium',
        'Tewodros Square',
      ],
      operatingHours: '06:00 AM – 10:00 PM',
    ),
    DriverRoute(
      id: 'route_02',
      name: 'Megenagna ⇄ Tor Hailoch',
      routeCode: 'ET-RT-04',
      startLocation: 'Megenagna (Zefmesh)',
      endLocation: 'Tor Hailoch',
      fare: 30.00,
      isActive: true,
      distanceKm: 12.2,
      estimatedDuration: '40–50 min',
      intermediateStops: ['Haya Hulet', 'Urael', 'Mexico', 'St. Lideta'],
      operatingHours: '05:30 AM – 09:30 PM',
    ),
    DriverRoute(
      id: 'route_03',
      name: 'Merkato ⇄ Saris',
      routeCode: 'ET-RT-09',
      startLocation: 'Merkato (Military Tera)',
      endLocation: 'Saris (Abo)',
      fare: 20.00,
      isActive: false,
      distanceKm: 8.5,
      estimatedDuration: '25–35 min',
      intermediateStops: ['Sebategna', 'Autobus Tera', 'Gofa Camp', 'Kera'],
      operatingHours: '06:00 AM – 09:00 PM',
    ),
    DriverRoute(
      id: 'route_04',
      name: '4 Kilo ⇄ Kality',
      routeCode: 'ET-RT-15',
      startLocation: '4 Kilo (AAU)',
      endLocation: 'Kality (Total)',
      fare: 35.00,
      isActive: false,
      distanceKm: 16.0,
      estimatedDuration: '50–60 min',
      intermediateStops: ['Piazza', 'Mexico', 'Gotera', 'Saris'],
      operatingHours: '06:00 AM – 08:30 PM',
    ),
  ];

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
