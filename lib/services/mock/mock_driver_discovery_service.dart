import '../../models/available_driver.dart';
import '../api/interfaces.dart';

export '../api/interfaces.dart' show DriverDiscoveryService;

/// Test-only stand-in. In production the router injects
/// `ApiDriverDiscoveryService`; this exists so widget tests can render the
/// picker without a backend.
class MockDriverDiscoveryService implements DriverDiscoveryService {
  MockDriverDiscoveryService({
    this.simulatedDelay = const Duration(milliseconds: 100),
    List<AvailableDriver>? drivers,
  }) : _drivers =
           drivers ??
           const [
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

  @override
  Future<AvailableDriver?> findByLicense(String licenseNumber) async {
    await Future<void>.delayed(simulatedDelay);
    for (final driver in _drivers) {
      if (driver.licenseNumber?.toLowerCase() ==
          licenseNumber.trim().toLowerCase()) {
        return driver;
      }
    }
    return null;
  }
}
