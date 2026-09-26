import '../../models/driver.dart';
import '../../models/passenger.dart';

/// Result of an authentication attempt.
class AuthResult {
  const AuthResult._({
    required this.isSuccess,
    this.passenger,
    this.driver,
    this.errorMessage,
  });

  /// Successful passenger login.
  factory AuthResult.passengerSuccess(Passenger passenger) {
    return AuthResult._(isSuccess: true, passenger: passenger);
  }

  /// Successful driver login.
  factory AuthResult.driverSuccess(Driver driver) {
    return AuthResult._(isSuccess: true, driver: driver);
  }

  /// Failed login.
  factory AuthResult.failure(String message) {
    return AuthResult._(isSuccess: false, errorMessage: message);
  }

  final bool isSuccess;

  /// Non-null on successful passenger login.
  final Passenger? passenger;

  /// Non-null on successful driver login.
  final Driver? driver;

  final String? errorMessage;

  bool get isPassenger => passenger != null;
  bool get isDriver => driver != null;
}

/// MOCK authentication service.
///
/// ⚠️ This is a frontend-only mock implementation.
/// Replace this class with a real API-backed service when the backend is ready.
///
/// The repository layer calls this service, and the UI calls the repository.
/// To connect to a real backend: implement [AuthService] interface, create
/// a concrete [ApiAuthService], and inject it into [AuthRepository].
abstract interface class AuthService {
  /// Attempts to authenticate a passenger.
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  });

  /// Attempts to authenticate a driver.
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  });

  /// Logs out the current user.
  Future<void> logout();
}

/// Mock implementation of [AuthService].
///
/// Hardcoded credentials for frontend development.
/// Passenger: yosef / password
/// Driver: abel / password
class MockAuthService implements AuthService {
  /// Simulated network delay — makes the mock feel realistic.
  static const Duration _simulatedDelay = Duration(milliseconds: 800);

  static const Passenger _mockPassenger = Passenger(
    id: 'p_001',
    name: 'Yosef Mekonnen',
    username: 'yosef',
    phone: '+251911234567',
    walletBalance: 1250.00,
  );

  static const Driver _mockDriver = Driver(
    id: 'd_001',
    name: 'Abel Girma',
    username: 'abel',
    phone: '+251922345678',
    accountBalance: 4850.00,
    todayEarnings: 1250.00,
    licenseNumber: 'ET-DL-2021-00456',
    vehiclePlate: 'AA-3-12345',
  );

  @override
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(_simulatedDelay);

    if (username.trim().toLowerCase() == 'yosef' && password == 'password') {
      return AuthResult.passengerSuccess(_mockPassenger);
    }

    return AuthResult.failure('Incorrect username or password.');
  }

  @override
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(_simulatedDelay);

    if (username.trim().toLowerCase() == 'abel' && password == 'password') {
      return AuthResult.driverSuccess(_mockDriver);
    }

    return AuthResult.failure('Incorrect username or password.');
  }

  @override
  Future<void> logout() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Nothing to clear in mock — real implementation would clear tokens/session.
  }
}
