/// Passenger trip model.
///
/// Represents a completed or historical trip taken by a passenger.
class Trip {
  const Trip({
    required this.id,
    required this.fromLocation,
    required this.toLocation,
    required this.amountPaid,
    required this.completedAt,
    required this.driverName,
    required this.status,
  });

  final String id;
  final String fromLocation;
  final String toLocation;
  final double amountPaid;
  final DateTime completedAt;
  final String driverName;
  final TripStatus status;

  @override
  String toString() =>
      'Trip(id: $id, from: $fromLocation, to: $toLocation, amount: $amountPaid)';
}

/// Status of a passenger trip.
enum TripStatus { completed, cancelled, inProgress }
