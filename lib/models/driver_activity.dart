/// Driver activity summary model.
///
/// Encapsulates daily operational metrics for a driver.
class DriverActivity {
  const DriverActivity({
    required this.completedRides,
    required this.totalEarnings,
    required this.averageFare,
  });

  /// Number of trips/rides completed today.
  final int completedRides;

  /// Total earnings accrued today in ETB.
  final double totalEarnings;

  /// Average fare per completed ride in ETB.
  final double averageFare;

  @override
  String toString() =>
      'DriverActivity(rides: $completedRides, earnings: $totalEarnings, avg: $averageFare)';
}
