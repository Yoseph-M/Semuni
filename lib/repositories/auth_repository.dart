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

  /// Logs out the current user and clears state.
  Future<void> logout() async {
    await _authService.logout();
    _currentPassenger = null;
    _currentDriver = null;
  }

  /// Default mock passenger for testing or direct navigation without prior login.
  static const Passenger defaultMockPassenger = Passenger(
    id: 'p_001',
    name: 'Yosef Mekonnen',
    username: 'yosef',
    phone: '+251911234567',
    walletBalance: 1250.00,
  );

  /// Available wallet balance for the authenticated passenger (or default mock passenger).
  double get passengerWalletBalance =>
      _currentPassenger?.walletBalance ?? defaultMockPassenger.walletBalance;

  /// Sets the currently active passenger (useful for tests or mock setup).
  void setCurrentPassenger(Passenger? passenger) {
    _currentPassenger = passenger;
  }

  /// Deducts [amount] from the current passenger's wallet balance if sufficient.
  ///
  /// Returns `true` if deduction succeeded, or `false` if balance was insufficient.
  ///
  /// DEPRECATED for production use: a wallet balance is owned by the backend and
  /// read with `GET /wallet`. This exists only so the still-mock wallet service
  /// keeps working, and is deleted with it — no real API path may mutate a
  /// balance locally and call the money spent.
  @Deprecated(
    'Balance changes belong to the backend (GET /wallet). Mock-only path.',
  )
  bool deductPassengerBalance(double amount) {
    final activePassenger = _currentPassenger ?? defaultMockPassenger;
    if (activePassenger.walletBalance < amount) {
      return false;
    }
    _currentPassenger = activePassenger.copyWith(
      walletBalance: activePassenger.walletBalance - amount,
    );
    return true;
  }

  /// Adds [amount] to the current passenger's wallet balance.
  ///
  /// DEPRECATED for production use — see [deductPassengerBalance]. A top-up is
  /// only real once the backend confirms the provider payment and credits the
  /// wallet itself.
  @Deprecated(
    'Balance changes belong to the backend (top-up intent → confirm → GET /wallet).',
  )
  void addPassengerBalance(double amount) {
    final activePassenger = _currentPassenger ?? defaultMockPassenger;
    _currentPassenger = activePassenger.copyWith(
      walletBalance: activePassenger.walletBalance + amount,
    );
  }
}
