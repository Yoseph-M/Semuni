/// Driver route model.
///
/// Represents a taxi route that a driver is assigned to operate on.
class DriverRoute {
  const DriverRoute({
    required this.id,
    required this.name,
    required this.startLocation,
    required this.endLocation,
    required this.fare,
    required this.isActive,
    this.routeCode,
    this.distanceKm,
    this.estimatedDuration,
    this.intermediateStops = const [],
    this.operatingHours,
  });

  final String id;
  final String name;
  final String startLocation;
  final String endLocation;

  /// Standard route fare in ETB.
  final double fare;

  /// Whether this route is currently active/assigned.
  final bool isActive;

  /// Official transport route identifier code (e.g. "ET-RT-01").
  final String? routeCode;

  /// Total distance in kilometers.
  final double? distanceKm;

  /// Estimated transit duration (e.g. "30–40 min").
  final String? estimatedDuration;

  /// Ordered list of intermediate stops / stations along this route.
  final List<String> intermediateStops;

  /// Standard daily operating hours (e.g. "06:00 AM – 10:00 PM").
  final String? operatingHours;

  DriverRoute copyWith({
    String? id,
    String? name,
    String? startLocation,
    String? endLocation,
    double? fare,
    bool? isActive,
    String? routeCode,
    double? distanceKm,
    String? estimatedDuration,
    List<String>? intermediateStops,
    String? operatingHours,
  }) {
    return DriverRoute(
      id: id ?? this.id,
      name: name ?? this.name,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      fare: fare ?? this.fare,
      isActive: isActive ?? this.isActive,
      routeCode: routeCode ?? this.routeCode,
      distanceKm: distanceKm ?? this.distanceKm,
      estimatedDuration: estimatedDuration ?? this.estimatedDuration,
      intermediateStops: intermediateStops ?? this.intermediateStops,
      operatingHours: operatingHours ?? this.operatingHours,
    );
  }

  @override
  String toString() =>
      'DriverRoute(id: $id, name: $name, from: $startLocation, to: $endLocation, active: $isActive)';
}
