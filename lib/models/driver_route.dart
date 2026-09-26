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
  });

  final String id;
  final String name;
  final String startLocation;
  final String endLocation;

  /// Standard route fare in ETB.
  final double fare;

  /// Whether this route is currently active/assigned.
  final bool isActive;

  @override
  String toString() =>
      'DriverRoute(id: $id, name: $name, from: $startLocation, to: $endLocation)';
}
