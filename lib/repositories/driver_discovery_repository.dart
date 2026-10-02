import '../models/available_driver.dart';
import '../services/mock/mock_driver_discovery_service.dart';

/// Which minibus/driver a passenger is paying. Backed by the API in
/// production; the mock is for widget tests.
class DriverDiscoveryRepository {
  DriverDiscoveryRepository({DriverDiscoveryService? service})
    : _service = service ?? MockDriverDiscoveryService();

  final DriverDiscoveryService _service;

  Future<List<AvailableDriver>> getAvailableDrivers() =>
      _service.getAvailableDrivers();
}
