import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/core/network/api_exception.dart';

/// Contract tests for the single HTTP entry point every feature uses.
///
/// They run against a MockClient, so they assert exactly what the app sends and
/// how it interprets what comes back — including the failures that must never
/// reach a screen as a raw status code.
void main() {
  const baseUrl = 'http://backend.test';

  ApiClient clientWith(
    MockClient mock, {
    AuthSession? session,
    Duration? timeout,
  }) => ApiClient(
    httpClient: mock,
    session: session ?? AuthSession(tokenStore: InMemoryTokenStore()),
    baseUrl: baseUrl,
    timeout: timeout,
  );

  group('request shape', () {
    test('calls the versioned API prefix', () async {
      late Uri seen;
      final client = clientWith(
        MockClient((request) async {
          seen = request.url;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await client.get('/wallet');

      expect(seen.toString(), '$baseUrl/api/v1/wallet');
    });

    test('sends a request id and an idempotency key when asked', () async {
      late http.BaseRequest seen;
      final client = clientWith(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await client.post(
        '/payments/trip',
        body: {'tripId': 't1'},
        idempotencyKey: 'key-123',
      );

      expect(seen.headers['X-Request-Id'], isNotEmpty);
      expect(seen.headers['Idempotency-Key'], 'key-123');
      expect(seen.headers['Content-Type'], startsWith('application/json'));
    });

    test('attaches the bearer token from the shared session', () async {
      final session = AuthSession(tokenStore: InMemoryTokenStore());
      await session.begin(const AuthTokens(accessToken: 'access-abc'));

      late http.BaseRequest seen;
      final client = clientWith(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
        session: session,
      );

      await client.get('/trips');

      expect(seen.headers['Authorization'], 'Bearer access-abc');
    });

    test('sends no Authorization header when there is no session', () async {
      late http.BaseRequest seen;
      final client = clientWith(
        MockClient((request) async {
          seen = request;
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
      );

      await client.get('/routes');

      expect(seen.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('response handling', () {
    test('unwraps the data/meta envelope', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': {'balance': 12500},
              'meta': {'message': 'ok'},
            }),
            200,
          ),
        ),
      );

      final result = await client.get('/wallet');

      expect(result.asMap['balance'], 12500);
      expect(result.meta['message'], 'ok');
    });

    test('treats a bare payload as the data', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(jsonEncode([1, 2, 3]), 200),
        ),
      );

      final result = await client.get('/anything');

      expect(result.asList, [1, 2, 3]);
    });

    test('maps a list payload to a list of maps', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'data': [
                {'id': 'a'},
                {'id': 'b'},
              ],
            }),
            200,
          ),
        ),
      );

      final result = await client.get('/routes');

      expect(result.asMapList.map((row) => row['id']), ['a', 'b']);
    });
  });

  group('error mapping', () {
    test('carries the backend error code and a user-safe message', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'statusCode': 409,
              'code': ApiErrorCodes.idempotencyConflict,
              'message': 'This idempotency key was already used for a trip',
            }),
            409,
          ),
        ),
      );

      await expectLater(
        client.post('/payments/trip', body: const {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.conflict)
              .having((e) => e.code, 'code', ApiErrorCodes.idempotencyConflict)
              .having(
                (e) => e.userMessage,
                'userMessage',
                'This request was already sent with different details. Start a new request.',
              ),
        ),
      );
    });

    test('explains an insufficient balance in user terms', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': ApiErrorCodes.walletInsufficientBalance,
              'message': 'Insufficient wallet balance',
            }),
            400,
          ),
        ),
      );

      await expectLater(
        client.post('/payments/trip', body: const {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.userMessage,
            'userMessage',
            'Your wallet balance is too low for this payment. Top up and try again.',
          ),
        ),
      );
    });

    test('flattens class-validator message arrays', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 'VALIDATION_ERROR',
              'message': ['amount must be a positive number'],
            }),
            400,
          ),
        ),
      );

      await expectLater(
        client.post('/wallet/top-up', body: const {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'amount must be a positive number',
          ),
        ),
      );
    });

    test('a 401 clears the session and is flagged as expired', () async {
      final session = AuthSession(tokenStore: InMemoryTokenStore());
      await session.begin(const AuthTokens(accessToken: 'stale'));

      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({
              'code': 'AUTH_UNAUTHORIZED',
              'message': 'Unauthorized',
            }),
            401,
          ),
        ),
        session: session,
      );

      await expectLater(
        client.get('/wallet'),
        throwsA(
          isA<ApiException>().having((e) => e.isAuthExpired, 'isAuthExpired', true),
        ),
      );
      expect(session.isAuthenticated, isFalse);
    });

    test('an unreachable backend is retryable', () async {
      final client = clientWith(
        MockClient((request) async => throw Exception('connection refused')),
      );

      await expectLater(
        client.get('/wallet'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.network)
              .having((e) => e.isRetryable, 'isRetryable', true),
        ),
      );
    });

    test('a slow backend surfaces as a timeout, not a hang', () async {
      final client = clientWith(
        MockClient((request) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return http.Response(jsonEncode({'data': {}}), 200);
        }),
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        client.get('/wallet'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.timeout)
              .having((e) => e.isRetryable, 'isRetryable', true),
        ),
      );
    });

    test('a server error is retryable and never leaks a stack trace', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response(
            jsonEncode({'code': 'INTERNAL_ERROR', 'message': 'boom'}),
            500,
          ),
        ),
      );

      await expectLater(
        client.get('/wallet'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.kind, 'kind', ApiErrorKind.server)
              .having((e) => e.isRetryable, 'isRetryable', true)
              .having(
                (e) => e.userMessage,
                'userMessage',
                'Semuni is having trouble right now. Please try again shortly.',
              ),
        ),
      );
    });

    test('a non-JSON error page becomes an unexpected failure', () async {
      final client = clientWith(
        MockClient(
          (request) async => http.Response('<html>502 Bad Gateway</html>', 502),
        ),
      );

      await expectLater(
        client.get('/wallet'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiErrorKind.server)),
      );
    });
  });
}
