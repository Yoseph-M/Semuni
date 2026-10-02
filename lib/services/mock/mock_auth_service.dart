import '../../models/driver.dart';
import '../../models/passenger.dart';
import '../api/auth_service.dart';

// The interface and its result type live with the production implementation;
// re-exported here so existing test imports keep working.
export '../api/auth_service.dart';

/// No-network fallback for widget tests / offline UI builds.
///
/// Intentionally rejects every login attempt. If you want the app to actually
/// sign in, run the NestJS backend and use `ApiAuthService`; identities live in
/// Postgres, and no test should ever pass because a fake user existed.
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
  Future<Passenger?> refreshPassenger() async => null;

  @override
  Future<Driver?> refreshDriver() async => null;

  @override
  Future<void> logout() async {}
}
