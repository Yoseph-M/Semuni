import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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

/// Public interface all auth implementations must satisfy.
///
/// The UI layer never talks to this interface directly; use [AuthRepository].
///
/// Implementations shipped:
///   * [ApiAuthService] — production implementation hitting the real
///     NestJS backend. Credentials live in Postgres only. This is the
///     default used by the app.
///   * [MockAuthService] — offline, frontend-only stub used for widget
///     tests. Rejects every attempt; credentials MUST come from the DB.
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

/// Default backend host.
///
/// Override in CI/flavor builds via the `SMUNI_API_BASE` environment or
/// Dart-define variable (not needed during local dev).
class _Endpoints {
  static const String defaultBase = String.fromEnvironment(
    'SMUNI_API_BASE',
    defaultValue: 'http://localhost:3000',
  );
  static const String apiPrefix = '/api/v1';
}

/// Real HTTP-backed auth implementation.
///
/// Flow:
///   1. POST /api/v1/auth/login with {phone, password, role}.
///   2. Receive {accessToken, refreshToken}.
///   3. GET /api/v1/passengers/me or /api/v1/drivers/me with Bearer token
///      to hydrate the full profile + wallet balance.
///
/// Hardcoded credentials are intentionally absent from this class.
/// The database is the single source of truth for who can log in.
class ApiAuthService implements AuthService {
  ApiAuthService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _Endpoints.defaultBase;

  final http.Client _client;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final pathSeg = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$_baseUrl${_Endpoints.apiPrefix}$pathSeg')
        .replace(queryParameters: query);
  }

  static String _roleName(bool isPassenger) =>
      isPassenger ? 'PASSENGER' : 'DRIVER';

  static Map<String, dynamic> _parseJson(String body) {
    return json.decode(body) as Map<String, dynamic>;
  }

  static String _messageOr(Map<String, dynamic> json, String fallback) {
    final meta = json['meta'];
    if (meta is Map) {
      final m = meta['message'];
      if (m is String && m.isNotEmpty) return m;
    }
    final msg = json['message'];
    if (msg is String && msg.isNotEmpty) return msg;
    if (msg is List && msg.isNotEmpty) return msg.join(', ');
    return fallback;
  }

  @override
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  }) async {
    return _login(username: username, password: password, isPassenger: true);
  }

  @override
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  }) async {
    return _login(username: username, password: password, isPassenger: false);
  }

  @override
  Future<void> logout() async {
    // Access tokens are stateless; nothing to call server-side for logout.
    // Caller (AuthRepository) clears the in-memory passenger/driver state.
  }

  Future<AuthResult> _login({
    required String username,
    required String password,
    required bool isPassenger,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return AuthResult.failure('Enter a username and password.');
    }

    final loginPayload = <String, String>{
      'username': username.trim(),
      'password': password,
      'role': _roleName(isPassenger),
    };

    late final http.Response loginRes;
    try {
      loginRes = await _client
          .post(
            _uri('/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(loginPayload),
          )
          .timeout(const Duration(seconds: 12));
    } on TimeoutException {
      return AuthResult.failure(
        'Connection timed out. Is the backend running?',
      );
    } on Object catch (e) {
      return AuthResult.failure(
        'Could not reach the backend (${e.runtimeType}). Is the backend running on ${_Endpoints.defaultBase}?',
      );
    }

    if (loginRes.statusCode < 200 || loginRes.statusCode >= 300) {
      late final String message;
      try {
        final parsed = _parseJson(loginRes.body);
        message = _messageOr(parsed, 'Invalid username or password.');
      } on Object {
        message = 'Invalid username or password. (HTTP ${loginRes.statusCode})';
      }
      return AuthResult.failure(message);
    }

    final String accessToken;
    try {
      final parsed = _parseJson(loginRes.body);
      final data = parsed['data'] as Map<String, dynamic>;
      accessToken =
          (data['accessToken'] ?? data['access_token'] ?? '') as String;
    } on Object {
      return AuthResult.failure('Unexpected response from /auth/login.');
    }

    if (accessToken.isEmpty) {
      return AuthResult.failure('Server did not issue an access token.');
    }

    final profilePath = isPassenger ? '/passengers/me' : '/drivers/me';
    late final http.Response profileRes;
    try {
      profileRes = await _client
          .get(
            _uri(profilePath),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      return AuthResult.failure('Timed out loading profile.');
    } on Object catch (e) {
      return AuthResult.failure('Failed to load profile (${e.runtimeType}).');
    }

    if (profileRes.statusCode < 200 || profileRes.statusCode >= 300) {
      return AuthResult.failure(
        'Failed to load profile. (HTTP ${profileRes.statusCode})',
      );
    }

    try {
      final parsed = _parseJson(profileRes.body);
      final data = parsed['data'] as Map<String, dynamic>;
      if (isPassenger) {
        return AuthResult.passengerSuccess(_passengerFromJson(data));
      }
      final earnings = await _tryFetchEarnings(accessToken);
      return AuthResult.driverSuccess(_driverFromJson(data, earnings));
    } on Object catch (e) {
      return AuthResult.failure('Invalid profile response: ${e.runtimeType}');
    }
  }

  Future<Map<String, double>?> _tryFetchEarnings(String accessToken) async {
    try {
      final r = await _client
          .get(
            _uri('/drivers/me/earnings'),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(const Duration(seconds: 8));
      if (r.statusCode < 200 || r.statusCode >= 300) return null;
      final parsed = _parseJson(r.body);
      final data = parsed['data'] as Map<String, dynamic>;
      return {
        'todayEarnings': (data['todayEarnings'] as num?)?.toDouble() ?? 0.0,
      };
    } on Object {
      return null;
    }
  }

  static Passenger _passengerFromJson(Map<String, dynamic> data) {
    final wallet = data['wallet'] as Map<String, dynamic>?;
    final balanceSantim = wallet?['balance'] as int? ?? 0;
    final phone = (data['phone'] ?? '') as String;
    final handle = (data['username'] ?? '') as String;
    final username = handle.isNotEmpty ? handle : (data['id'] ?? '') as String;
    return Passenger(
      id: (data['id'] ?? data['userId'] ?? '') as String,
      name: (data['fullName'] ?? 'Passenger') as String,
      username: username,
      phone: phone,
      walletBalance: balanceSantim / 100.0,
    );
  }

  static Driver _driverFromJson(
    Map<String, dynamic> data,
    Map<String, double>? earnings,
  ) {
    final phone = (data['phone'] ?? '') as String;
    final handle = (data['username'] ?? '') as String;
    final username = handle.isNotEmpty ? handle : (data['id'] ?? '') as String;
    return Driver(
      id: (data['id'] ?? data['userId'] ?? '') as String,
      name: (data['fullName'] ?? 'Driver') as String,
      username: username,
      phone: phone,
      accountBalance: ((data['accountBalance'] as num?)?.toDouble()) ?? 0.0,
      todayEarnings: earnings?['todayEarnings'] ?? 0.0,
      licenseNumber: (data['licenseNumber'] ?? '') as String,
      vehiclePlate: (data['vehiclePlate'] ?? '') as String,
    );
  }
}

/// No-network fallback for widget tests / offline UI builds.
///
/// Intentionally rejects every login attempt. If you want the app to
/// actually log in, run the real NestJS backend, create an account with
/// `POST /api/v1/auth/register`, and use [ApiAuthService].
class MockAuthService implements AuthService {
  const MockAuthService();

  @override
  Future<AuthResult> loginPassenger({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return AuthResult.failure(
      'Mock auth disabled. Start the backend and use ApiAuthService.',
    );
  }

  @override
  Future<AuthResult> loginDriver({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return AuthResult.failure(
      'Mock auth disabled. Start the backend and use ApiAuthService.',
    );
  }

  @override
  Future<void> logout() async {}
}
