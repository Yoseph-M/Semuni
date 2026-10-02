import 'package:flutter_test/flutter_test.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/core/network/api_exception.dart';
import 'package:smuni/services/api/api_auth_service.dart';

/// Opt-in smoke test against a **running** backend.
///
/// Every other test in this repository runs offline, on purpose. This one is
/// the exception that proves the client is wired to real HTTP: it registers
/// nobody itself, it signs a real account in and reads that account's wallet
/// through the same `ApiClient` the app uses.
///
/// Run it with the backend up:
///
///   cd backend && PORT=3000 npm run start:dev
///   flutter test test/integration/api_smoke_test.dart \
///     --dart-define=SMUNI_LIVE_BACKEND=true \
///     --dart-define=SMUNI_API_BASE=http://127.0.0.1:3000
///
/// The account it signs in with is created by the test itself (`smoke_*`), so
/// it depends on no seeded password. Without `SMUNI_LIVE_BACKEND=true` the test
/// is skipped, so it can never fail a normal `flutter test` run or a CI job with
/// no database.
void main() {
  const live = bool.fromEnvironment('SMUNI_LIVE_BACKEND');

  // A fresh identity per run: the same handle cannot be registered twice.
  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final username = 'smoke_$suffix';
  const password = 'SmokeTest#2026';

  group(
    'live backend smoke',
    () {
      test('registers, signs in and reads the wallet the server reports', () async {
        final session = AuthSession(tokenStore: InMemoryTokenStore());
        final client = ApiClient(session: session, timeout: const Duration(seconds: 20));
        final auth = ApiAuthService(client: client, session: session);

        // Registration is the one endpoint that must work unauthenticated.
        final registration = await client.post(
          '/auth/register',
          authenticated: false,
          body: {
            'username': username,
            'fullName': 'Smoke Test Passenger',
            'password': password,
            'role': 'PASSENGER',
          },
        );
        expect(registration.asMap['user'], isNotNull);

        final result = await auth.loginPassenger(
          username: username,
          password: password,
        );

        expect(
          result.isSuccess,
          isTrue,
          reason: result.errorMessage ?? 'login did not succeed',
        );
        expect(result.passenger, isNotNull);
        expect(session.isAuthenticated, isTrue);

        // The same authenticated client every feature service uses.
        final wallet = await client.get('/wallet');
        expect(wallet.asMap['balance'], isA<num>());
        expect(wallet.asMap['currency'], 'ETB');

        // And the token is actually accepted: an authenticated read of the
        // signed-in passenger's own profile.
        final me = await client.get('/passengers/me');
        expect(me.asMap['id'], result.passenger!.id);

        // A failure the UI must branch on, produced by the real backend.
        await expectLater(
          client.get('/trips/00000000-0000-0000-0000-000000000000'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              ApiErrorCodes.tripNotFound,
            ),
          ),
        );
      });

      test('rejects a wrong password with a user-facing message', () async {
        final session = AuthSession(tokenStore: InMemoryTokenStore());
        final auth = ApiAuthService(
          client: ApiClient(session: session),
          session: session,
        );

        final result = await auth.loginPassenger(
          username: username,
          password: 'definitely-not-the-password',
        );

        expect(result.isSuccess, isFalse);
        expect(result.errorMessage, isNotEmpty);
        expect(session.isAuthenticated, isFalse);
      });
    },
    skip: live
        ? false
        : 'live backend smoke test: pass --dart-define=SMUNI_LIVE_BACKEND=true',
  );
}
