import '../../models/passenger_route.dart';

/// Abstract service contract for passenger route discovery.
///
/// Architecture:
/// UI → PassengerRouteRepository → PassengerRouteService (Mock or Real API)
abstract interface class PassengerRouteService {
  /// Retrieves all stations on the SMUNI taxi network.
  Future<List<TaxiStation>> getStations();

  /// Retrieves all available passenger routes.
  Future<List<PassengerRoute>> getAllRoutes();

  /// Searches routes where the destination matches [query].
  ///
  /// [query] is matched case-insensitively against station names and labels.
  Future<List<PassengerRoute>> searchByDestination(String query);

  /// Returns all routes that serve [stationId] as a destination.
  Future<List<PassengerRoute>> getRoutesToStation(String stationId);
}

/// Mock implementation of [PassengerRouteService].
///
/// Provides realistic Addis Ababa taxi route data for the SMUNI
/// passenger map/discovery screen.
///
/// Simulates a small network delay consistent with the rest of the app.
class MockPassengerRouteService implements PassengerRouteService {
  MockPassengerRouteService({
    this.simulatedDelay = const Duration(milliseconds: 350),
  });

  final Duration simulatedDelay;

  // -------------------------------------------------------------------------
  // Mock station data — Addis Ababa key taxi stops
  // -------------------------------------------------------------------------

  static const List<TaxiStation> _stations = [
    TaxiStation(
      id: 'bole',
      name: 'Bole',
      label: 'Bole',
      mapX: 0.72,
      mapY: 0.60,
      isHub: true,
    ),
    TaxiStation(
      id: 'piazza',
      name: 'Piazza',
      label: 'Piazza',
      mapX: 0.28,
      mapY: 0.22,
      isHub: true,
    ),
    TaxiStation(
      id: 'mexico',
      name: 'Mexico',
      label: 'Mexico',
      mapX: 0.42,
      mapY: 0.45,
      isHub: false,
    ),
    TaxiStation(
      id: 'saris',
      name: 'Saris',
      label: 'Saris',
      mapX: 0.20,
      mapY: 0.80,
      isHub: false,
    ),
    TaxiStation(
      id: 'megenagna',
      name: 'Megenagna',
      label: 'Megenagna',
      mapX: 0.68,
      mapY: 0.28,
      isHub: true,
    ),
    TaxiStation(
      id: 'cmc',
      name: 'CMC',
      label: 'CMC',
      mapX: 0.80,
      mapY: 0.14,
      isHub: false,
    ),
    TaxiStation(
      id: 'torhailoch',
      name: 'Tor Hailoch',
      label: 'Tor Hailoch',
      mapX: 0.35,
      mapY: 0.72,
      isHub: false,
    ),
    TaxiStation(
      id: 'ayat',
      name: 'Ayat',
      label: 'Ayat',
      mapX: 0.88,
      mapY: 0.40,
      isHub: false,
    ),
    TaxiStation(
      id: 'merkato',
      name: 'Merkato',
      label: 'Merkato',
      mapX: 0.18,
      mapY: 0.42,
      isHub: true,
    ),
    TaxiStation(
      id: 'kaliti',
      name: 'Kality',
      label: 'Kality',
      mapX: 0.50,
      mapY: 0.92,
      isHub: false,
    ),
  ];

  // -------------------------------------------------------------------------
  // Mock route data — realistic Addis Ababa taxi corridors
  // -------------------------------------------------------------------------

  static const List<PassengerRoute> _routes = [
    // Route 1: Bole → Piazza
    PassengerRoute(
      id: 'pr_01',
      name: 'Bole → Piazza',
      startStation: 'bole',
      endStation: 'piazza',
      startLabel: 'Bole Medhanialem',
      endLabel: 'Piazza (Churchill Ave)',
      fare: 25.00,
      isAvailable: true,
      routeCode: 'ET-RT-01',
      estimatedDuration: '30–40 min',
      distanceKm: 9.8,
      intermediateStops: [
        'Olympia',
        'Meskel Square',
        'Stadium',
        'Tewodros Square',
      ],
      operatingHours: '06:00 AM – 10:00 PM',
      instructions: 'Board at Bole Medhanialem roundabout. Ask for "Piazza".',
    ),

    // Route 2: Mexico → Piazza
    PassengerRoute(
      id: 'pr_02',
      name: 'Mexico → Piazza',
      startStation: 'mexico',
      endStation: 'piazza',
      startLabel: 'Mexico Square',
      endLabel: 'Piazza (Churchill Ave)',
      fare: 15.00,
      isAvailable: true,
      routeCode: 'ET-RT-02',
      estimatedDuration: '15–20 min',
      distanceKm: 4.2,
      intermediateStops: ['St. Lideta', 'Tewodros Square'],
      operatingHours: '05:30 AM – 10:00 PM',
      instructions: 'Board at Mexico Square junction. "Piazza" minibuses depart frequently.',
    ),

    // Route 3: Megenagna → Tor Hailoch
    PassengerRoute(
      id: 'pr_03',
      name: 'Megenagna → Tor Hailoch',
      startStation: 'megenagna',
      endStation: 'torhailoch',
      startLabel: 'Megenagna (Zefmesh)',
      endLabel: 'Tor Hailoch',
      fare: 30.00,
      isAvailable: true,
      routeCode: 'ET-RT-04',
      estimatedDuration: '40–50 min',
      distanceKm: 12.2,
      intermediateStops: ['Haya Hulet', 'Urael', 'Mexico', 'St. Lideta'],
      operatingHours: '05:30 AM – 09:30 PM',
      instructions:
          'Board at Megenagna circle. Ask for "Tor Hailoch" or "Merkato".',
    ),

    // Route 4: Merkato → Saris
    PassengerRoute(
      id: 'pr_04',
      name: 'Merkato → Saris',
      startStation: 'merkato',
      endStation: 'saris',
      startLabel: 'Merkato (Military Tera)',
      endLabel: 'Saris (Abo)',
      fare: 20.00,
      isAvailable: true,
      routeCode: 'ET-RT-09',
      estimatedDuration: '25–35 min',
      distanceKm: 8.5,
      intermediateStops: ['Sebategna', 'Autobus Tera', 'Gofa Camp', 'Kera'],
      operatingHours: '06:00 AM – 09:00 PM',
      instructions:
          'Board at Merkato Military Tera. Blue-and-white minibuses only.',
    ),

    // Route 5: Bole → Megenagna
    PassengerRoute(
      id: 'pr_05',
      name: 'Bole → Megenagna',
      startStation: 'bole',
      endStation: 'megenagna',
      startLabel: 'Bole Medhanialem',
      endLabel: 'Megenagna (Zefmesh)',
      fare: 15.00,
      isAvailable: true,
      routeCode: 'ET-RT-06',
      estimatedDuration: '20–30 min',
      distanceKm: 6.5,
      intermediateStops: ['Bole Atlas', 'Haya Hulet'],
      operatingHours: '06:00 AM – 10:30 PM',
      instructions: 'Board near Bole Medhanialem church. "Megenagna" is written on board.',
    ),

    // Route 6: Megenagna → CMC
    PassengerRoute(
      id: 'pr_06',
      name: 'Megenagna → CMC',
      startStation: 'megenagna',
      endStation: 'cmc',
      startLabel: 'Megenagna (Zefmesh)',
      endLabel: 'CMC Michael',
      fare: 12.00,
      isAvailable: true,
      routeCode: 'ET-RT-07',
      estimatedDuration: '15–20 min',
      distanceKm: 5.0,
      intermediateStops: ['Gerji', 'CMC Michael'],
      operatingHours: '06:00 AM – 10:00 PM',
      instructions: 'Board at Megenagna circle north exit. Ask for "CMC".',
    ),

    // Route 7: Megenagna → Ayat
    PassengerRoute(
      id: 'pr_07',
      name: 'Megenagna → Ayat',
      startStation: 'megenagna',
      endStation: 'ayat',
      startLabel: 'Megenagna (Zefmesh)',
      endLabel: 'Ayat',
      fare: 20.00,
      isAvailable: false,
      routeCode: 'ET-RT-08',
      estimatedDuration: '30–40 min',
      distanceKm: 10.0,
      intermediateStops: ['Gerji', 'CMC', 'Ayat 1'],
      operatingHours: '06:00 AM – 09:00 PM',
      instructions: 'Limited service. Confirm availability before boarding.',
    ),

    // Route 8: Tor Hailoch → Saris
    PassengerRoute(
      id: 'pr_08',
      name: 'Tor Hailoch → Saris',
      startStation: 'torhailoch',
      endStation: 'saris',
      startLabel: 'Tor Hailoch',
      endLabel: 'Saris (Abo)',
      fare: 15.00,
      isAvailable: true,
      routeCode: 'ET-RT-10',
      estimatedDuration: '20–25 min',
      distanceKm: 6.0,
      intermediateStops: ['Kera', 'Gofa'],
      operatingHours: '06:00 AM – 09:30 PM',
      instructions: 'Board at Tor Hailoch roundabout south side.',
    ),

    // Route 9: Mexico → Merkato
    PassengerRoute(
      id: 'pr_09',
      name: 'Mexico → Merkato',
      startStation: 'mexico',
      endStation: 'merkato',
      startLabel: 'Mexico Square',
      endLabel: 'Merkato (Military Tera)',
      fare: 10.00,
      isAvailable: true,
      routeCode: 'ET-RT-11',
      estimatedDuration: '10–15 min',
      distanceKm: 3.0,
      intermediateStops: ['Golagol', 'Abay Mado'],
      operatingHours: '05:30 AM – 10:00 PM',
      instructions: 'Very frequent service. Ask for "Merkato".',
    ),

    // Route 10: Piazza → Kality
    PassengerRoute(
      id: 'pr_10',
      name: 'Piazza → Kality',
      startStation: 'piazza',
      endStation: 'kaliti',
      startLabel: 'Piazza (Churchill Ave)',
      endLabel: 'Kality (Total)',
      fare: 35.00,
      isAvailable: false,
      routeCode: 'ET-RT-15',
      estimatedDuration: '50–60 min',
      distanceKm: 16.0,
      intermediateStops: ['Mexico', 'Gotera', 'Saris', 'Kera'],
      operatingHours: '06:00 AM – 08:30 PM',
      instructions: 'Limited service hours. Check return times carefully.',
    ),
  ];

  @override
  Future<List<TaxiStation>> getStations() async {
    await Future<void>.delayed(simulatedDelay);
    return List.unmodifiable(_stations);
  }

  @override
  Future<List<PassengerRoute>> getAllRoutes() async {
    await Future<void>.delayed(simulatedDelay);
    return List.unmodifiable(_routes);
  }

  @override
  Future<List<PassengerRoute>> searchByDestination(String query) async {
    await Future<void>.delayed(simulatedDelay);
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    return _routes.where((r) {
      return r.endStation.toLowerCase().contains(q) ||
          r.endLabel.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Future<List<PassengerRoute>> getRoutesToStation(String stationId) async {
    await Future<void>.delayed(simulatedDelay);
    return _routes.where((r) => r.endStation == stationId).toList();
  }
}
