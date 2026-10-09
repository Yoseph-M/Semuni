import '../../core/auth/auth_session.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../models/driver.dart';
import '../../models/passenger.dart';
import 'auth_service.dart';

// The interface and its result type ship with the implementation they describe,
// so a caller importing this file gets a usable API surface.
export 'auth_service.dart';

/// Production authentication against the NestJS backend.
///
/// Flow, per sign-in:
///   1. `POST /auth/login` with `{ username, password, role }` — no credentials
///      are known to this class; Postgres is the only source of identity.
///   2. Store the issued tokens in the shared [AuthSession], so every later
///      request from [ApiClient] is authenticated without any feature code
///      handling tokens.
///   3. Hydrate the profile (`GET /passengers/me` or `GET /drivers/me`), which
///      carries the authoritative wallet balance. The client never invents one.
class ApiAuthService implements AuthService {
  ApiAuthService({ApiClient? client, AuthSession? session})
    : _client = client ?? ApiClient(session: session),
      _session = session ?? (client?.session ?? AuthSession());

  final ApiClient _client;
  final AuthSession _session;

  @override
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  }) => _login(username: username, password: password, isPassenger: true);

  @override
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  }) => _login(username: username, password: password, isPassenger: false);

  /// Restores the credentials a previous launch left in secure storage.
  ///
  /// Order matters: load the tokens first, then ask the backend who they belong
  /// to (`GET /auth/me`), then hydrate that role's profile. Nothing is assumed
  /// from storage alone — the backend is the authority on whether the session is
  /// still valid, so a revoked or expired session can never reach a signed-in
  /// screen.
  @override
  Future<AuthResult?> restoreSession() async {
    await _session.restore();
    if (!_session.isAuthenticated) return null;

    final role = await _fetchSessionRole();
    if (role == null) return null;

    if (role != 'PASSENGER' && role != 'DRIVER') {
      await _session.clear();
      return null;
    }

    final result = await _hydrateProfile(isPassenger: role == 'PASSENGER');
    return result.isSuccess ? result : null;
  }

  /// Asks the backend which role the stored access token belongs to.
  ///
  /// Returns null when the session cannot be verified. If the backend actually
  /// rejected the credentials, [ApiClient] has already cleared them; if the
  /// failure was transient (offline, backend down) the tokens are deliberately
  /// kept so a later launch can restore, and the user simply signs in now.
  Future<String?> _fetchSessionRole() async {
    try {
      final response = await _client.get('/auth/me');
      return _stringOrNull(response.asMap['role'])?.toUpperCase();
    } on ApiException {
      return null;
    }
  }

  @override
  Future<Passenger?> refreshPassenger() async {
    try {
      final profile = await _client.get('/passengers/me');
      return _passengerFromJson(profile.asMap);
    } on ApiException {
      // The caller decides what to do; a failed refresh must not sign anyone
      // out or wipe the currently displayed profile.
      return null;
    }
  }

  @override
  Future<Driver?> refreshDriver() async {
    try {
      final profile = await _client.get('/drivers/me');
      final earnings = await _tryFetchTodayEarnings();
      return _driverFromJson(profile.asMap, earnings);
    } on ApiException {
      return null;
    }
  }

  @override
  Future<void> logout() async {
    // Revoke server-side when we can (the refresh-token chain is invalidated
    // there), but never block sign-out on it: a user who taps "log out" must
    // end up logged out even with no connection.
    final refreshToken = _session.refreshToken;
    if (_session.isAuthenticated && refreshToken != null) {
      try {
        await _client.post(
          '/auth/logout',
          body: {'refreshToken': refreshToken},
        );
      } on ApiException {
        // Ignored on purpose — local sign-out proceeds regardless.
      }
    }
    await _session.clear();
  }

  Future<AuthResult> _login({
    required String username,
    required String password,
    required bool isPassenger,
  }) async {
    final trimmedUsername = username.trim();
    if (trimmedUsername.isEmpty || password.isEmpty) {
      return AuthResult.failure('Enter a username and password.');
    }

    try {
      final login = await _client.post(
        '/auth/login',
        authenticated: false,
        body: {
          'username': trimmedUsername,
          'password': password,
          'role': isPassenger ? 'PASSENGER' : 'DRIVER',
        },
      );

      final data = login.asMap;
      final accessToken = _stringOrNull(
        data['accessToken'] ?? data['access_token'],
      );
      if (accessToken == null) {
        return AuthResult.failure('The backend did not issue an access token.');
      }

      await _session.begin(
        AuthTokens(
          accessToken: accessToken,
          refreshToken: _stringOrNull(
            data['refreshToken'] ?? data['refresh_token'],
          ),
        ),
      );
    } on ApiException catch (error) {
      return AuthResult.failure(
        error.userMessage,
        isConnectionFailure: error.isRetryable,
      );
    }

    return _hydrateProfile(isPassenger: isPassenger);
  }

  /// Loads the signed-in user's profile with the freshly stored token.
  Future<AuthResult> _hydrateProfile({required bool isPassenger}) async {
    try {
      final profile = await _client.get(
        isPassenger ? '/passengers/me' : '/drivers/me',
      );
      final data = profile.asMap;

      if (isPassenger) {
        return AuthResult.passengerSuccess(_passengerFromJson(data));
      }

      final earnings = await _tryFetchTodayEarnings();
      return AuthResult.driverSuccess(_driverFromJson(data, earnings));
    } on ApiException catch (error) {
      // The session is useless without a profile: drop it so the next attempt
      // starts clean instead of carrying half a login.
      await _session.clear();
      return AuthResult.failure(
        error.userMessage,
        isConnectionFailure: error.isRetryable,
      );
    }
  }

  Future<double?> _tryFetchTodayEarnings() async {
    try {
      final response = await _client.get('/drivers/me/earnings');
      final value = response.asMap['todayEarnings'];
      return value is num ? value.toDouble() : null;
    } on ApiException {
      // Earnings are a dashboard nicety; a failure here must not fail sign-in.
      return null;
    }
  }

  static String? _stringOrNull(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  static Passenger _passengerFromJson(Map<String, dynamic> data) {
    final wallet = data['wallet'];
    final balanceMinor = wallet is Map ? (wallet['balance'] as num?) : null;
    final handle = _stringOrNull(data['username']) ?? '';
    return Passenger(
      id: _stringOrNull(data['id']) ?? _stringOrNull(data['userId']) ?? '',
      name: _stringOrNull(data['fullName']) ?? 'Passenger',
      username: handle.isNotEmpty ? handle : (_stringOrNull(data['id']) ?? ''),
      phone: _stringOrNull(data['phone']) ?? '',
      // Minor units (santim) from the backend; ETB for display only.
      walletBalance: (balanceMinor ?? 0) / 100.0,
    );
  }

  static Driver _driverFromJson(
    Map<String, dynamic> data,
    double? todayEarnings,
  ) {
    final handle = _stringOrNull(data['username']) ?? '';
    return Driver(
      id: _stringOrNull(data['id']) ?? _stringOrNull(data['userId']) ?? '',
      name: _stringOrNull(data['fullName']) ?? 'Driver',
      username: handle.isNotEmpty ? handle : (_stringOrNull(data['id']) ?? ''),
      phone: _stringOrNull(data['phone']) ?? '',
      accountBalance: ((data['accountBalance'] as num?) ?? 0).toDouble(),
      todayEarnings: todayEarnings ?? 0.0,
      licenseNumber: _stringOrNull(data['licenseNumber']) ?? '',
      vehiclePlate: _stringOrNull(data['vehiclePlate']) ?? '',
    );
  }
}
