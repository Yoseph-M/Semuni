import '../../models/driver.dart';
import '../../models/passenger.dart';
import '../api/auth_service.dart';

// The interface and its result type live with the production implementation;
// re-exported here so existing test imports keep working.
export '../api/auth_service.dart';

/// Offline-capable auth service for widget tests and mock-first builds.
///
/// Accepts a small fixed set of known credentials so the full-app test suite
/// can exercise navigation flows without a running NestJS backend.
///
/// Credentials:
///   Passenger — yosef / password
///   Driver    — abel  / password
///
/// Any other combination returns a failure, matching the real backend's behaviour
/// for unknown users. Production builds must inject [ApiAuthService] instead.
class MockAuthService implements AuthService {
  MockAuthService({this.simulatedDelay = const Duration(milliseconds: 150)});

  final Duration simulatedDelay;

  // Mutable balance to allow withdrawal to reflect correctly in tests.
  double _driverBalance = 4250.00;

  static const String _driverUsername = 'abel';
  static const String _passengerUsername = 'yosef';
  static const String _password = 'password';

  @override
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(simulatedDelay);
    if (username.trim() == _passengerUsername && password == _password) {
      return AuthResult.passengerSuccess(
        Passenger(
          id: 'pax_mock_001',
          name: 'Yosef Mulugeta',
          username: _passengerUsername,
          phone: '+251912345678',
          walletBalance: 1250.00,
        ),
      );
    }
    return AuthResult.failure('Incorrect username or password.');
  }

  @override
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(simulatedDelay);
    if (username.trim() == _driverUsername && password == _password) {
      return AuthResult.driverSuccess(
        Driver(
          id: 'drv_mock_001',
          name: 'Abel Tesfaye',
          username: _driverUsername,
          phone: '+251987654321',
          accountBalance: _driverBalance,
          todayEarnings: 320.00,
          licenseNumber: 'AA-DL-12345',
          vehiclePlate: 'AA-3-12345',
        ),
      );
    }
    return AuthResult.failure('Incorrect username or password.');
  }

  /// Always null: this stub holds no persisted credentials, and widget tests
  /// start from the login screen on purpose.
  @override
  Future<AuthResult?> restoreSession() async => null;

  @override
  Future<Passenger?> refreshPassenger() async => null;

  @override
  Future<Driver?> refreshDriver() async {
    await Future<void>.delayed(simulatedDelay);
    // Returns the current driver state (with possibly updated balance).
    return Driver(
      id: 'drv_mock_001',
      name: 'Abel Tesfaye',
      username: _driverUsername,
      phone: '+251987654321',
      accountBalance: _driverBalance,
      todayEarnings: 320.00,
      licenseNumber: 'AA-DL-12345',
      vehiclePlate: 'AA-3-12345',
    );
  }

  @override
  Future<void> logout() async {
    await Future<void>.delayed(simulatedDelay);
  }

  /// Deducts [amount] from the driver's mock balance.
  ///
  /// Call this after a successful withdrawal to keep the balance consistent
  /// between the Withdraw screen and Driver Home after [refreshDriverProfile].
  void deductDriverBalance(double amount) {
    if (amount > 0 && amount <= _driverBalance) {
      _driverBalance -= amount;
    }
  }
}
