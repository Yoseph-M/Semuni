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
    this.routeCode,
    this.fareMinor = 0,
    this.paymentStatus = 'UNPAID',
    this.receiptNumber,
  });

  final String id;
  final String fromLocation;
  final String toLocation;
  final double amountPaid;
  final DateTime completedAt;
  final String driverName;
  final TripStatus status;
  final String? routeCode;

  /// Authoritative fare in minor units (santim), as stored on the backend.
  /// Zero when the trip did not come from the API (mock-era records).
  final int fareMinor;

  /// Raw backend payment status (`UNPAID`, `PAID`, …). The server owns this;
  /// the client only reflects it.
  final String paymentStatus;

  /// Receipt number once the trip has been paid.
  final String? receiptNumber;

  /// The fare to show, preferring the authoritative minor-unit value.
  double get fareEtb => fareMinor > 0 ? fareMinor / 100 : amountPaid;

  bool get isPaid => paymentStatus.toUpperCase() == 'PAID';

  @override
  String toString() =>
      'Trip(id: $id, from: $fromLocation, to: $toLocation, amount: $amountPaid, status: $status)';
}

/// Status of a passenger trip.
enum TripStatus { completed, cancelled, inProgress, requested }
