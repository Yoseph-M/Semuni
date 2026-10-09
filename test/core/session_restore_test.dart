import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/services/api/api_auth_service.dart';

/// Startup restoration is the difference between "you are still signed in" and
/// "sign in again" after a restart, so it is tested as a contract:
///
///   * no stored credentials  → nothing is requested, the user signs in;
///   * valid credentials      → the profile comes back from the backend;
///   * an expired access token → refreshed with the stored refresh token;
///   * rejected credentials   → the session is cleared;
///   * an unreachable backend → the session is kept, but not trusted.
void main() {
  const baseUrl = 'http://backend.test';

  const passengerProfile = {
    'id': 'pax-1',
    'username': 'passenger',
    'fullName': 'Test Passenger',
    'phone': '+251911000001',
    'wallet': {'balance': 12500, 'currency': 'ETB'},
  };

  const driverProfile = {
    'id': 'drv-user-1',
    'username': 'driver',
    'fullName': 'Test Driver',
    'phone': '+251911000002',
    'accountBalance': 4250,
    'licenseNumber': 'AA-DL-1',
    'vehiclePlate': 'AA-3-12345',
  };

  (
    AuthSession,
    ApiAuthService,
    List<String>,
    _ScriptedTokenStore,
  )
  serviceWithStore(
    Future<AuthTokens?> Function() readTokens,
    Future<http.Response> Function(http.Request request) handler,
  ) {
    final store = _ScriptedTokenStore(readTokens);
    final session = AuthSession(tokenStore: store);
    final paths = <String>[];
    final client = ApiClient(
      session: session,
      baseUrl: baseUrl,
      httpClient: MockClient((request) {
        paths.add(request.url.path);
        return handler(request);
      }),
    );
    return (
      session,
      ApiAuthService(client: client, session: session),
      paths,
      store,
    );
  }

  http.Response ok(Object body) => http.Response(jsonEncode(body), 200);

  test('no stored credentials: nothing is requested', () async {
    final (session, auth, paths, _) = serviceWithStore(
      () async => null,
      (request) async => ok({'data': {}}),
    );

    final restored = await auth.restoreSession();

    expect(restored, isNull);
    expect(session.isAuthenticated, isFalse);
    expect(paths, isEmpty);
  });

  test('a stored passenger session is restored from the backend', () async {
    final (session, auth, paths, _) = serviceWithStore(
      () async => const AuthTokens(
        accessToken: 'access-1',
        refreshToken: 'refresh-1',
      ),
      (request) async => switch (request.url.path) {
        '/api/v1/auth/me' => ok({
          'data': {'id': 'pax-1', 'role': 'PASSENGER'},
        }),
        '/api/v1/passengers/me' => ok({'data': passengerProfile}),
        _ => http.Response('not found', 404),
      },
    );

    final restored = await auth.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.isPassenger, isTrue);
    expect(restored.passenger!.id, 'pax-1');
    expect(restored.passenger!.walletBalance, 125.0);
    expect(session.isAuthenticated, isTrue);
    expect(paths, ['/api/v1/auth/me', '/api/v1/passengers/me']);
  });

  test('a stored driver session is restored from the backend', () async {
    final (_, auth, paths, _) = serviceWithStore(
      () async => const AuthTokens(
        accessToken: 'access-2',
        refreshToken: 'refresh-2',
      ),
      (request) async => switch (request.url.path) {
        '/api/v1/auth/me' => ok({
          'data': {'id': 'drv-user-1', 'role': 'DRIVER'},
        }),
        '/api/v1/drivers/me' => ok({'data': driverProfile}),
        '/api/v1/drivers/me/earnings' => ok({
          'data': {'todayEarnings': 320.0},
        }),
        _ => http.Response('not found', 404),
      },
    );

    final restored = await auth.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.isDriver, isTrue);
    expect(restored.driver!.id, 'drv-user-1');
    expect(restored.driver!.todayEarnings, 320.0);
    expect(paths, [
      '/api/v1/auth/me',
      '/api/v1/drivers/me',
      '/api/v1/drivers/me/earnings',
    ]);
  });

  test('an expired access token is refreshed, then the profile loads', () async {
    final (session, auth, paths, store) = serviceWithStore(
      () async => const AuthTokens(
        accessToken: 'expired',
        refreshToken: 'refresh-3',
      ),
      (request) async {
        if (request.url.path == '/api/v1/auth/refresh') {
          return ok({
            'data': {
              'accessToken': 'access-3',
              'refreshToken': 'refresh-3-rotated',
            },
          });
        }
        if (request.headers['Authorization'] == 'Bearer expired') {
          return http.Response(
            jsonEncode({'code': 'AUTH_TOKEN_EXPIRED', 'message': 'expired'}),
            401,
          );
        }
        if (request.url.path == '/api/v1/auth/me') {
          return ok({
            'data': {'id': 'pax-1', 'role': 'PASSENGER'},
          });
        }
        return ok({'data': passengerProfile});
      },
    );

    final restored = await auth.restoreSession();

    expect(restored, isNotNull);
    expect(restored!.isPassenger, isTrue);
    // The rotated pair replaces the expired one, in memory and in storage: a
    // restart after a refresh must find the new tokens, not the spent ones.
    expect(session.accessToken, 'access-3');
    expect(session.refreshToken, 'refresh-3-rotated');
    expect(store.written?.accessToken, 'access-3');
    expect(store.written?.refreshToken, 'refresh-3-rotated');
    expect(paths, [
      '/api/v1/auth/me',
      '/api/v1/auth/refresh',
      '/api/v1/auth/me',
      '/api/v1/passengers/me',
    ]);
  });

  test('rejected credentials restore nothing and clear the session', () async {
    final (session, auth, _, _) = serviceWithStore(
      () async => const AuthTokens(
        accessToken: 'revoked',
        refreshToken: 'revoked-refresh',
      ),
      (request) async => request.url.path == '/api/v1/auth/refresh'
          ? http.Response(
              jsonEncode({'code': 'AUTH_TOKEN_INVALID', 'message': 'no'}),
              401,
            )
          : http.Response(
              jsonEncode({'code': 'AUTH_UNAUTHORIZED', 'message': 'no'}),
              401,
            ),
    );

    final restored = await auth.restoreSession();

    expect(restored, isNull);
    expect(session.isAuthenticated, isFalse);
    expect(session.refreshToken, isNull);
  });

  test('an unreachable backend keeps credentials but grants no session', () async {
    final (session, auth, _, _) = serviceWithStore(
      () async => const AuthTokens(
        accessToken: 'access-4',
        refreshToken: 'refresh-4',
      ),
      (request) async => throw Exception('connection refused'),
    );

    final restored = await auth.restoreSession();

    expect(restored, isNull);
    // The tokens survived, so the next launch with connectivity can restore.
    expect(session.accessToken, 'access-4');
  });

  test('a role the app cannot serve is not restored', () async {
    final (session, auth, _, _) = serviceWithStore(
      () async => const AuthTokens(accessToken: 'access-5'),
      (request) async => ok({
        'data': {'id': 'admin-1', 'role': 'ADMIN'},
      }),
    );

    final restored = await auth.restoreSession();

    expect(restored, isNull);
    expect(session.isAuthenticated, isFalse);
  });
}

/// A token store whose `read()` is scripted, so a test can decide what a
/// previous launch left behind.
class _ScriptedTokenStore implements TokenStore {
  _ScriptedTokenStore(this._read);

  final Future<AuthTokens?> Function() _read;

  /// The most recent tokens [write] was given, so a test can assert what a
  /// restart would find.
  AuthTokens? written;

  @override
  Future<AuthTokens?> read() => _read();

  @override
  Future<void> write(AuthTokens tokens) async => written = tokens;

  @override
  Future<void> clear() async => written = null;
}
