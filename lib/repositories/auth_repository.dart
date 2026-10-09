import '../core/auth/auth_session.dart';
import '../models/driver.dart';
import '../models/passenger.dart';
import '../services/api/api_auth_service.dart';

/// Authentication repository.
///
/// The UI layer never calls [AuthService] directly.
/// All authentication operations go through this repository.
///
/// Architecture:
///   UI → AuthRepository → AuthService → ApiClient → NestJS
///
/// The default implementation is [ApiAuthService], which authenticates against
/// the real NestJS backend and keeps the issued tokens in the shared
/// [AuthSession]. `MockAuthService` is an offline stub used only for widget
/// tests and must be injected explicitly. No credentials are hardcoded here —
/// the database is the single source of truth for identities.
class AuthRepository {
  AuthRepository({AuthService? authService, AuthSession? session})
    : _authService =
          authService ?? ApiAuthService(session: session ?? AuthSession());

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

  /// Restores the session persisted by a previous launch, if any.
  ///
  /// Called once at startup, before the first screen is chosen: the returned
  /// identity decides whether the app opens on a home screen or the login
  /// screen. Returns null when the user must sign in.
  Future<AuthResult?> restoreSession() async {
    final result = await _authService.restoreSession();
    if (result == null) return null;

    _currentPassenger = result.passenger;
    _currentDriver = result.driver;
    return result;
  }

  /// Re-reads the signed-in passenger from the backend.
  ///
  /// This — not local arithmetic — is how a balance changes after a payment or
  /// a top-up: the server is the only writer. Returns the fresh passenger, or
  /// null when it could not be loaded (the previous profile is kept).
  Future<Passenger?> refreshPassengerProfile() async {
    final passenger = await _authService.refreshPassenger();
    if (passenger != null) {
      _currentPassenger = passenger;
    }
    return passenger;
  }

  /// Re-reads the signed-in driver from the backend.
  Future<Driver?> refreshDriverProfile() async {
    final driver = await _authService.refreshDriver();
    if (driver != null) {
      _currentDriver = driver;
    }
    return driver;
  }

  /// Logs out the current user and clears state.
  Future<void> logout() async {
    await _authService.logout();
    _currentPassenger = null;
    _currentDriver = null;
  }

  /// Sets the currently active passenger (useful for tests or mock setup).
  void setCurrentPassenger(Passenger? passenger) {
    _currentPassenger = passenger;
  }
}
