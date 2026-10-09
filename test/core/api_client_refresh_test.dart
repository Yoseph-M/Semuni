import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/core/network/api_exception.dart';

/// The access token is short-lived; the refresh token is single-use and
/// rotated. These tests pin down what the client does when a request meets an
/// expired access token: exchange, replay once, and never loop.
void main() {
  const baseUrl = 'http://backend.test';

  ApiClient clientWith(MockClient mock, {required AuthSession session}) =>
      ApiClient(httpClient: mock, session: session, baseUrl: baseUrl);

  http.Response envelope(Map<String, dynamic> data, [int status = 200]) =>
      http.Response(jsonEncode({'data': data, 'meta': {}}), status);

  Future<AuthSession> signedInSession() async {
    final session = AuthSession(tokenStore: InMemoryTokenStore());
    await session.begin(
      const AuthTokens(
        accessToken: 'expired-access',
        refreshToken: 'refresh-1',
      ),
    );
    return session;
  }

  test(
    'exchanges an expired access token once and replays the request',
    () async {
      final session = await signedInSession();
      var refreshCalls = 0;
      var protectedCalls = 0;

      final client = clientWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            refreshCalls += 1;
            expect(request.headers.containsKey('Authorization'), isFalse);
            expect(
              (jsonDecode(request.body)
                  as Map<String, dynamic>)['refreshToken'],
              'refresh-1',
            );
            return envelope({
              'accessToken': 'fresh-access',
              'refreshToken': 'refresh-2',
            });
          }

          protectedCalls += 1;
          final authorization = request.headers['Authorization'];
          if (authorization == 'Bearer expired-access') {
            return http.Response(
              jsonEncode({
                'code': ApiErrorCodes.authTokenExpired,
                'message': 'Access token expired',
              }),
              401,
            );
          }
          expect(authorization, 'Bearer fresh-access');
          return envelope({'ok': true});
        }),
        session: session,
      );

      final result = await client.get('/wallet');

      expect(result.asMap['ok'], isTrue);
      expect(refreshCalls, 1, reason: 'the token is exchanged exactly once');
      expect(protectedCalls, 2, reason: 'original request + one replay');
      expect(session.accessToken, 'fresh-access');
      expect(session.refreshToken, 'refresh-2', reason: 'rotation is stored');
    },
  );

  test('refreshes once for several requests that expire together', () async {
    final session = await signedInSession();
    var refreshCalls = 0;

    final client = clientWith(
      MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls += 1;
          // A slow refresh widens the window two concurrent 401s can race in.
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return envelope({
            'accessToken': 'fresh-access',
            'refreshToken': 'refresh-2',
          });
        }
        if (request.headers['Authorization'] == 'Bearer expired-access') {
          return http.Response(
            jsonEncode({'code': 'AUTH_TOKEN_EXPIRED', 'message': 'expired'}),
            401,
          );
        }
        return envelope({'ok': true});
      }),
      session: session,
    );

    await Future.wait([client.get('/wallet'), client.get('/trips')]);

    expect(refreshCalls, 1, reason: 'single-flight refresh');
  });

  test(
    'clears the session when the refresh token itself is rejected',
    () async {
      final session = await signedInSession();
      final expiredEvents = <void>[];
      session.onSessionExpired.listen(expiredEvents.add);

      final client = clientWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response(
              jsonEncode({
                'code': 'AUTH_REFRESH_TOKEN_INVALID',
                'message': 'Invalid refresh token',
              }),
              401,
            );
          }
          return http.Response(
            jsonEncode({'code': 'AUTH_TOKEN_EXPIRED', 'message': 'expired'}),
            401,
          );
        }),
        session: session,
      );

      await expectLater(
        client.get('/wallet'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.isAuthExpired,
            'isAuthExpired',
            isTrue,
          ),
        ),
      );

      expect(session.isAuthenticated, isFalse);
      expect(session.accessToken, isNull);
      expect(expiredEvents, hasLength(1));
    },
  );

  test(
    'keeps the session when the refresh could not reach the backend',
    () async {
      final session = await signedInSession();

      final client = clientWith(
        MockClient((request) async {
          if (request.url.path.endsWith('/auth/refresh')) {
            return http.Response('unavailable', 503);
          }
          return http.Response(
            jsonEncode({'code': 'AUTH_TOKEN_EXPIRED', 'message': 'expired'}),
            401,
          );
        }),
        session: session,
      );

      await expectLater(client.get('/wallet'), throwsA(isA<ApiException>()));

      // A transient failure must not sign the user out; the tokens may be fine.
      expect(session.accessToken, 'expired-access');
      expect(session.refreshToken, 'refresh-1');
    },
  );

  test('expires the session when there is no refresh token to use', () async {
    final session = AuthSession(tokenStore: InMemoryTokenStore());
    await session.begin(const AuthTokens(accessToken: 'expired-access'));
    var protectedCalls = 0;

    final client = clientWith(
      MockClient((request) async {
        protectedCalls += 1;
        expect(request.url.path.endsWith('/auth/refresh'), isFalse);
        return http.Response(
          jsonEncode({'code': 'AUTH_TOKEN_EXPIRED', 'message': 'expired'}),
          401,
        );
      }),
      session: session,
    );

    await expectLater(client.get('/trips'), throwsA(isA<ApiException>()));

    expect(protectedCalls, 1);
    expect(session.isAuthenticated, isFalse);
  });
}
