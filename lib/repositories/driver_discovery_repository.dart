import '../services/api/interfaces.dart';
import '../models/available_driver.dart';

/// Which minibus/driver a passenger is paying. Backed by the API in
/// production; the mock is for widget tests.
class DriverDiscoveryRepository {
  DriverDiscoveryRepository({DriverDiscoveryService? service})
    : _service = service ?? const _EmptyDriverDiscoveryService();

  final DriverDiscoveryService _service;

  Future<List<AvailableDriver>> getAvailableDrivers() =>
      _service.getAvailableDrivers();

  Future<AvailableDriver?> findByLicense(String licenseNumber) =>
      _service.findByLicense(licenseNumber);
}

class _EmptyDriverDiscoveryService implements DriverDiscoveryService {
  const _EmptyDriverDiscoveryService();

  @override
  Future<List<AvailableDriver>> getAvailableDrivers() async => const [];

  @override
  Future<AvailableDriver?> findByLicense(String licenseNumber) async => null;
}
