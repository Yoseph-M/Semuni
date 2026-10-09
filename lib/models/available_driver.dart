/// A driver a passenger may board and pay.
///
/// This is deliberately a thin, non-sensitive view of an ACTIVE driver: enough
/// to identify the minibus the passenger is riding in. It carries no licence,
/// wallet or earnings data — a passenger has no business seeing those.
class AvailableDriver {
  const AvailableDriver({
    required this.driverUserId,
    required this.fullName,
    this.licenseNumber,
    this.vehiclePlate,
    this.vehicleType,
  });

  /// The driver's **user** id.
  ///
  /// This is the identifier `POST /trips` expects as `driverId`; the driver
  /// profile id is a different UUID and is not accepted there.
  final String driverUserId;

  final String fullName;
  final String? licenseNumber;

  /// Plate of the minibus assigned to the driver, when one exists.
  final String? vehiclePlate;

  final String? vehicleType;

  /// Label for a picker row, e.g. `"Abebe T. · DEV-12345"`.
  String get displayLabel {
    final plate = vehiclePlate;
    return plate == null || plate.isEmpty ? fullName : '$fullName · $plate';
  }

  @override
  String toString() => 'AvailableDriver($driverUserId, $fullName)';
}
