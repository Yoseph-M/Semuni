import '../../models/driver.dart';
import '../../models/passenger.dart';

/// Result of an authentication attempt.
///
/// A sign-in failure is an expected outcome, not an exception: the UI already
/// has a place to show "incorrect username or password", and throwing would
/// make callers responsible for catching something that is not exceptional.
class AuthResult {
  const AuthResult._({
    required this.isSuccess,
    this.passenger,
    this.driver,
    this.errorMessage,
    this.isConnectionFailure = false,
  });

  /// Successful passenger login.
  factory AuthResult.passengerSuccess(Passenger passenger) {
    return AuthResult._(isSuccess: true, passenger: passenger);
  }

  /// Successful driver login.
  factory AuthResult.driverSuccess(Driver driver) {
    return AuthResult._(isSuccess: true, driver: driver);
  }

  /// Failed login. [message] is already safe to display.
  factory AuthResult.failure(String message, {bool isConnectionFailure = false}) {
    return AuthResult._(
      isSuccess: false,
      errorMessage: message,
      isConnectionFailure: isConnectionFailure,
    );
  }

  final bool isSuccess;

  /// Non-null on successful passenger login.
  final Passenger? passenger;

  /// Non-null on successful driver login.
  final Driver? driver;

  /// Non-null when [isSuccess] is false.
  final String? errorMessage;

  /// True when the attempt failed because the backend was unreachable or timed
  /// out — the UI can offer "Try again" rather than "check your password".
  final bool isConnectionFailure;

  bool get isPassenger => passenger != null;
  bool get isDriver => driver != null;
}

/// Public interface all auth implementations must satisfy.
///
/// The UI layer never talks to this interface directly; use `AuthRepository`.
///
/// Implementations shipped:
///   * `ApiAuthService` — production: authenticates against the NestJS backend
///     and stores the issued tokens in the shared `AuthSession`.
///   * `MockAuthService` — offline stub used by widget tests. Rejects every
///     attempt on purpose, so a test can never accidentally depend on a fake
///     identity.
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

  /// Re-reads the signed-in passenger profile, including the authoritative
  /// wallet balance. Returns null when the profile cannot be loaded.
  Future<Passenger?> refreshPassenger();

  /// Re-reads the signed-in driver profile, including the wallet balance.
  Future<Driver?> refreshDriver();

  /// Ends the session locally and, when possible, revokes it server-side.
  Future<void> logout();
}
