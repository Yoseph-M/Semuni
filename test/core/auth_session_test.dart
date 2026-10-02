import 'package:flutter_test/flutter_test.dart';

import 'package:smuni/core/auth/auth_session.dart';

/// A store that fails every operation, standing in for a locked keystore.
class _FailingStore implements TokenStore {
  @override
  Future<AuthTokens?> read() async => throw Exception('keystore unavailable');

  @override
  Future<void> write(AuthTokens tokens) async =>
      throw Exception('keystore unavailable');

  @override
  Future<void> clear() async => throw Exception('keystore unavailable');
}

void main() {
  group('AuthSession', () {
    test('is unauthenticated until tokens are recorded', () async {
      final session = AuthSession(tokenStore: InMemoryTokenStore());

      expect(session.isAuthenticated, isFalse);
      expect(session.accessToken, isNull);

      await session.begin(
        const AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
      );

      expect(session.isAuthenticated, isTrue);
      expect(session.accessToken, 'access-1');
      expect(session.canRefresh, isTrue);
    });

    test('restores a persisted session once', () async {
      final store = InMemoryTokenStore();
      await store.write(
        const AuthTokens(accessToken: 'access-2', refreshToken: 'refresh-2'),
      );

      final session = AuthSession(tokenStore: store);
      await session.restore();

      expect(session.accessToken, 'access-2');
      expect(session.refreshToken, 'refresh-2');

      // A second restore must not clobber a newer in-memory session.
      await session.begin(const AuthTokens(accessToken: 'access-3'));
      await session.restore();
      expect(session.accessToken, 'access-3');
    });

    test('clear() removes credentials from the store', () async {
      final store = InMemoryTokenStore();
      final session = AuthSession(tokenStore: store);
      await session.begin(const AuthTokens(accessToken: 'access-4'));

      await session.clear();

      expect(session.isAuthenticated, isFalse);
      expect(await store.read(), isNull);
    });

    test('expire() clears the session and announces it', () async {
      final session = AuthSession(tokenStore: InMemoryTokenStore());
      await session.begin(const AuthTokens(accessToken: 'access-5'));

      final events = <void>[];
      final subscription = session.onSessionExpired.listen(events.add);
      await session.expire();
      await Future<void>.delayed(Duration.zero);

      expect(session.isAuthenticated, isFalse);
      expect(events, hasLength(1));

      await subscription.cancel();
      await session.dispose();
    });

    test('expire() on an already-anonymous session stays quiet', () async {
      final session = AuthSession(tokenStore: InMemoryTokenStore());

      final events = <void>[];
      final subscription = session.onSessionExpired.listen(events.add);
      await session.expire();
      await Future<void>.delayed(Duration.zero);

      expect(events, isEmpty);

      await subscription.cancel();
      await session.dispose();
    });

    test('a failing token store leaves the app signed out, not broken', () async {
      final session = AuthSession(tokenStore: _FailingStore());

      await session.restore();

      expect(session.isAuthenticated, isFalse);
    });

    test('updateTokens() replaces the access token and keeps the refresh token', () async {
      final session = AuthSession(tokenStore: InMemoryTokenStore());
      await session.begin(
        const AuthTokens(accessToken: 'old', refreshToken: 'refresh-6'),
      );

      await session.updateTokens(
        const AuthTokens(accessToken: 'new', refreshToken: 'refresh-6'),
      );

      expect(session.accessToken, 'new');
      expect(session.refreshToken, 'refresh-6');
    });
  });
}
