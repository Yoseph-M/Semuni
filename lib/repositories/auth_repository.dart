import '../models/driver.dart';
import '../models/passenger.dart';
import '../services/mock/mock_auth_service.dart';

/// Authentication repository.
///
/// The UI layer never calls [AuthService] directly.
/// All authentication operations go through this repository.
///
/// Architecture:
///   UI → AuthRepository → AuthService (Mock or Real API)
///
/// To connect to a real backend: inject a real [AuthService] implementation.
class AuthRepository {
  AuthRepository({AuthService? authService})
    : _authService = authService ?? MockAuthService();

  final AuthService _authService;

  /// Holds the currently authenticated passenger (if any).
  Passenger? _currentPassenger;

  /// Holds the currently authenticated driver (if any).
  Driver? _currentDriver;

  /// The currently authenticated passenger, or null if not logged in.
  Passenger? get currentPassenger => _currentPassenger;

  /// The currently authenticated driver, or null if not logged in.
  Driver? get currentDriver => _currentDriver;

  /// True if any user (passenger or driver) is authenticated.
  bool get isAuthenticated =>
      _currentPassenger != null || _currentDriver != null;

  /// Authenticates a passenger.
  ///
  /// Returns an [AuthResult] describing the outcome.
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  }) async {
    final result = await _authService.loginPassenger(
      username: username,
      password: password,
    );

    if (result.isSuccess && result.passenger != null) {
      _currentPassenger = result.passenger;
      _currentDriver = null; // Ensure only one role is active.
    }

    return result;
  }

  /// Authenticates a driver.
  ///
  /// Returns an [AuthResult] describing the outcome.
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  }) async {
    final result = await _authService.loginDriver(
      username: username,
      password: password,
    );

    if (result.isSuccess && result.driver != null) {
      _currentDriver = result.driver;
      _currentPassenger = null; // Ensure only one role is active.
    }

    return result;
  }

  /// Logs out the current user and clears state.
  Future<void> logout() async {
    await _authService.logout();
    _currentPassenger = null;
    _currentDriver = null;
  }
}
