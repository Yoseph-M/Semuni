import '../../models/available_driver.dart';

/// Discovering which minibus/driver a passenger is paying.
///
/// The backend exposes only ACTIVE drivers, and only the identity a passenger
/// needs to pick the vehicle they are sitting in.
abstract interface class DriverDiscoveryService {
  Future<List<AvailableDriver>> getAvailableDrivers();
}

/// Test-only stand-in. In production the router injects
/// `ApiDriverDiscoveryService`; this exists so widget tests can render the
/// picker without a backend.
class MockDriverDiscoveryService implements DriverDiscoveryService {
  MockDriverDiscoveryService({
    this.simulatedDelay = const Duration(milliseconds: 100),
    List<AvailableDriver>? drivers,
  }) : _drivers = drivers ?? const [
    AvailableDriver(
      driverUserId: 'mock-driver-1',
      fullName: 'Mock Driver',
      vehiclePlate: 'MOCK-0001',
      vehicleType: 'MINIBUS',
    ),
  ];

  final Duration simulatedDelay;
  final List<AvailableDriver> _drivers;

  @override
  Future<List<AvailableDriver>> getAvailableDrivers() async {
    await Future<void>.delayed(simulatedDelay);
    return List.unmodifiable(_drivers);
  }
}
