import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The credentials issued by `POST /api/v1/auth/login`.
class AuthTokens {
  const AuthTokens({required this.accessToken, this.refreshToken});

  final String accessToken;

  /// Used to obtain a new access token. Rotated by the backend on every refresh,
  /// and replayed use revokes the whole session chain — so it is written to
  /// secure storage and never logged.
  final String? refreshToken;

  bool get canRefresh => refreshToken != null && refreshToken!.isNotEmpty;
}

/// Where credentials live between launches.
///
/// An interface rather than a direct dependency, for two reasons:
///
///   * tests inject [InMemoryTokenStore] and never touch platform channels;
///   * the storage mechanism can change without touching [AuthSession], the
///     client, or any feature code.
abstract interface class TokenStore {
  Future<AuthTokens?> read();
  Future<void> write(AuthTokens tokens);
  Future<void> clear();
}

/// Non-persistent store: credentials live only as long as the process.
///
/// This is what widget and unit tests use. It is also a safe fallback — an app
/// that forgets a session on restart is inconvenient, never insecure.
class InMemoryTokenStore implements TokenStore {
  AuthTokens? _tokens;

  @override
  Future<AuthTokens?> read() async => _tokens;

  @override
  Future<void> write(AuthTokens tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}

/// Platform keystore/keychain-backed storage for real devices.
///
/// Refresh tokens are bearer credentials: plaintext preferences (or a file in
/// the app sandbox) would let anything that can read app data impersonate the
/// user until the token is revoked.
class SecureTokenStore implements TokenStore {
  SecureTokenStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const _accessKey = 'smuni.accessToken';
  static const _refreshKey = 'smuni.refreshToken';

  final FlutterSecureStorage _storage;

  @override
  Future<AuthTokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    if (access == null || access.isEmpty) return null;
    final refresh = await _storage.read(key: _refreshKey);
    return AuthTokens(accessToken: access, refreshToken: refresh);
  }

  @override
  Future<void> write(AuthTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.accessToken);
    if (tokens.canRefresh) {
      await _storage.write(key: _refreshKey, value: tokens.refreshToken);
    } else {
      await _storage.delete(key: _refreshKey);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// The single holder of the current credentials.
///
/// Owned by the app (see `app.dart`) and shared by [ApiClient] and the auth
/// service, so exactly one place knows the access token. Feature repositories
/// never see a token, a refresh call, or a 401 — they only see data or an
/// [ApiException].
class AuthSession {
  AuthSession({TokenStore? tokenStore})
    : _store = tokenStore ?? SecureTokenStore();

  final TokenStore _store;

  AuthTokens? _tokens;
  final _sessionExpired = StreamController<void>.broadcast();

  /// Emits when the backend rejects the current credentials with 401, so the UI
  /// can route back to sign-in. Deliberately an event rather than an exception
  /// bubbling out of a random screen.
  Stream<void> get onSessionExpired => _sessionExpired.stream;

  String? get accessToken => _tokens?.accessToken;

  String? get refreshToken => _tokens?.refreshToken;

  bool get isAuthenticated => _tokens != null;

  bool get canRefresh => _tokens?.canRefresh ?? false;

  /// Loads persisted credentials at startup. Safe to call more than once.
  Future<void> restore() async {
    if (_tokens != null) return;
    try {
      _tokens = await _store.read();
    } on Object {
      // A keystore that cannot be read (locked device, removed key) is the same
      // as having no session: the user signs in again.
      _tokens = null;
    }
  }

  /// Records a successful sign-in and persists the credentials.
  Future<void> begin(AuthTokens tokens) async {
    _tokens = tokens;
    await _store.write(tokens);
  }

  /// Replaces the access token after a refresh, keeping the refresh token when
  /// the backend did not rotate it.
  Future<void> updateTokens(AuthTokens tokens) => begin(tokens);

  /// Signs out locally. The caller decides whether to also notify the backend.
  Future<void> clear() async {
    _tokens = null;
    await _store.clear();
  }

  /// The backend rejected our credentials: drop them and tell the UI.
  Future<void> expire() async {
    final hadSession = _tokens != null;
    await clear();
    if (hadSession && !_sessionExpired.isClosed) {
      _sessionExpired.add(null);
    }
  }

  Future<void> dispose() async {
    await _sessionExpired.close();
  }
}
