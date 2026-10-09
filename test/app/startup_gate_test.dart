import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smuni/app/app.dart';
import 'package:smuni/app/startup_screen.dart';
import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/features/auth/screens/login_screen.dart';
import 'package:smuni/models/passenger.dart';
import 'package:smuni/services/mock/mock_auth_service.dart';
import 'package:smuni/services/mock/mock_trip_service.dart';

/// Regression test for the startup session gate.
///
/// The gate used to swap the app between two differently shaped [MaterialApp]s
/// in the same position: while restoring it built one with `home:`, and after
/// restoring it built one with `initialRoute` + `onGenerateRoute`. The navigator
/// element survived that swap holding a route whose content was created from the
/// old `home` closure, so the next rebuild of that route threw
/// `Null check operator used on a null value` (`widget.home!` on a now-null
/// home).
///
/// That is a crash on every launch with stored credentials — the first thing a
/// real device does — so the transition is pinned here: the gate shows the
/// startup screen while the answer is unknown, then the login screen, and the
/// whole tree can rebuild afterwards without an exception.
void main() {
  /// A token store that reports a stored session, so the restore path runs.
  AuthSession sessionWithStoredTokens() => AuthSession(
    tokenStore: _StoredTokens(
      const AuthTokens(accessToken: 'access-1', refreshToken: 'refresh-1'),
    ),
  );

  testWidgets('the gate shows the startup screen, then the login screen', (
    tester,
  ) async {
    // The restore is held open so "while the answer is unknown" is a real
    // state the test can observe, not a race against a mock that answers in the
    // same microtask.
    final auth = _GatedRestoreService();

    await tester.pumpWidget(
      SmuniApp(
        services: SmuniServices(authService: auth),
        authSession: sessionWithStoredTokens(),
      ),
    );

    expect(find.byType(StartupScreen), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);

    // The backend says there is no session worth restoring.
    auth.complete(null);

    await tester.pumpAndSettle();
    expect(find.byType(StartupScreen), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);

    // Rebuild the entire tree (a rotation / resize is the cheapest way to force
    // it): the route on screen must survive it without the stale-route crash.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a restored session opens the passenger home, not the login', (
    tester,
  ) async {
    final auth = _GatedRestoreService();

    await tester.pumpWidget(
      SmuniApp(
        services: SmuniServices(
          authService: auth,
          // Offline trips, so the home screen's list is deterministic.
          tripService: MockTripService(simulatedDelay: Duration.zero),
        ),
        authSession: sessionWithStoredTokens(),
      ),
    );
    expect(find.byType(StartupScreen), findsOneWidget);

    // A passenger session comes back, as it would after a successful restore.
    auth.complete(
      AuthResult.passengerSuccess(
        const Passenger(
          id: 'pax-1',
          name: 'Yosef Mulugeta',
          username: 'yosef',
          phone: '+251911000001',
          walletBalance: 1250.0,
        ),
      ),
    );

    // Bounded pumps rather than pumpAndSettle: the home dashboard keeps an
    // animation running, so "settled" is not a state this tree reaches.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(StartupScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('Wallet Balance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// Restores only when the test says so, so the gate can be observed.
class _GatedRestoreService extends MockAuthService {
  final Completer<AuthResult?> _answer = Completer<AuthResult?>();

  void complete(AuthResult? result) => _answer.complete(result);

  @override
  Future<AuthResult?> restoreSession() => _answer.future;
}

/// A [TokenStore] that always reports the same tokens.
class _StoredTokens implements TokenStore {
  _StoredTokens(this.tokens);

  AuthTokens? tokens;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens tokens) async => this.tokens = tokens;

  @override
  Future<void> clear() async => tokens = null;
}
