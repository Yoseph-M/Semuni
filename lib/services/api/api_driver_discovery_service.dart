import '../../core/network/api_client.dart';
import '../../models/available_driver.dart';
import 'interfaces.dart';

/// Driver discovery against the backend (`GET /drivers/available`).
///
/// A passenger cannot name a driver from memory: trip creation takes the
/// driver's user id, and this endpoint is where a passenger obtains it, along
/// with the plate of the minibus they are boarding.
class ApiDriverDiscoveryService implements DriverDiscoveryService {
  ApiDriverDiscoveryService({required this.client});

  final ApiClient client;

  @override
  Future<List<AvailableDriver>> getAvailableDrivers() async {
    final response = await client.get('/drivers/available');
    return response.asMapList.map(_toModel).toList(growable: false);
  }

  @override
  Future<AvailableDriver?> findByLicense(String licenseNumber) async {
    final response = await client.get(
      '/drivers/by-license/${Uri.encodeComponent(licenseNumber.trim())}',
    );
    final data = response.asMap;
    if (data.isEmpty) return null;
    return _toModel(data);
  }

  static AvailableDriver _toModel(Map<String, dynamic> data) {
    return AvailableDriver(
      driverUserId: _string(data['driverUserId']) ?? '',
      fullName: _string(data['fullName']) ?? 'Driver',
      licenseNumber: _string(data['licenseNumber']),
      vehiclePlate: _string(data['vehiclePlate']),
      vehicleType: _string(data['vehicleType']),
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
