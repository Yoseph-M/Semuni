import 'package:flutter_test/flutter_test.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/services/api/api_auth_service.dart';
import 'package:smuni/services/api/api_driver_discovery_service.dart';
import 'package:smuni/services/api/api_passenger_route_service.dart';
import 'package:smuni/services/api/api_passenger_wallet_service.dart';
import 'package:smuni/services/api/api_trip_service.dart';
import 'package:smuni/services/api/payment_service.dart';

/// Opt-in end-to-end smoke test against a **running** backend and database.
///
/// It walks the real money path with the same services the app uses:
///
///   register → login → routes → fare quote → drivers → top-up (MOCK provider)
///   → confirm (wallet credited by the backend) → create trip → pay trip
///   → wallet debited → trip PAID → payment idempotency
///
/// Run it with the backend up (never against production data):
///
///   cd backend && PORT=3100 npm run start:dev
///   flutter test test/integration/api_flows_smoke_test.dart \
///     --dart-define=SMUNI_LIVE_BACKEND=true \
///     --dart-define=SMUNI_API_BASE=http://127.0.0.1:3100 \
///     --dart-define=SMUNI_SMOKE_DRIVER_PASSWORD='the seeded driver password'
///
/// The driver account must be ACTIVE (an admin approves drivers); the seed
/// creates it PENDING. Without SMUNI_LIVE_BACKEND=true this test is skipped,
/// so it can never fail a normal `flutter test` run.
void main() {
  const live = bool.fromEnvironment('SMUNI_LIVE_BACKEND');
  const driverPassword = String.fromEnvironment('SMUNI_SMOKE_DRIVER_PASSWORD');

  final suffix = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final passengerUsername = 'flows_$suffix';
  const passengerPassword = 'SmokeFlow#2026';

  group(
    'live passenger financial flow',
    () {
      late AuthSession session;
      late ApiClient client;
      late ApiAuthService auth;
      late ApiPassengerRouteService routes;
      late ApiDriverDiscoveryService drivers;
      late ApiPassengerWalletService wallet;
      late ApiTripService trips;
      late ApiPaymentService payments;
      late double startBalance;

      setUpAll(() async {
        session = AuthSession(tokenStore: InMemoryTokenStore());
        client = ApiClient(
          session: session,
          timeout: const Duration(seconds: 30),
        );
        auth = ApiAuthService(client: client, session: session);
        routes = ApiPassengerRouteService(client: client);
        drivers = ApiDriverDiscoveryService(client: client);
        wallet = ApiPassengerWalletService(client: client);
        trips = ApiTripService(client: client);
        payments = ApiPaymentService(client: client);

        await client.post(
          '/auth/register',
          authenticated: false,
          body: {
            'username': passengerUsername,
            'fullName': 'Flow Smoke Passenger',
            'password': passengerPassword,
            'role': 'PASSENGER',
          },
        );
        final login = await auth.loginPassenger(
          username: passengerUsername,
          password: passengerPassword,
        );
        expect(
          login.isSuccess,
          isTrue,
          reason: login.errorMessage ?? 'passenger login failed',
        );
      });

      test(
        'quote → top-up → trip → payment moves real backend state',
        () async {
          // ── Discovery ──────────────────────────────────────────────────────
          final allRoutes = await routes.getAllRoutes();
          final route = allRoutes.firstWhere(
            (r) => r.stops.length >= 2,
            orElse: () => throw StateError(
              'No seeded route has stops on this backend. Run `npm run seed:dev`.',
            ),
          );
          expect(route.id, isNotEmpty);
          expect(route.stops.first.id, isNotEmpty);
          expect(route.startStation, isNotEmpty);

          final quote = await routes.quoteFare(
            routeId: route.id,
            originStopId: route.stops.first.id,
            destinationStopId: route.stops.last.id,
          );
          expect(
            quote.fareMinor,
            greaterThan(0),
            reason: 'an ACTIVE tariff with a rule for this route is required',
          );

          final availableDrivers = await drivers.getAvailableDrivers();
          expect(
            availableDrivers,
            isNotEmpty,
            reason: 'No ACTIVE driver. Register/seed a driver and approve it (admin) before running this test.',
          );
          final driver = availableDrivers.first;

          // ── Top up through the MOCK provider ───────────────────────────────
          startBalance = await wallet.getBalance('self');
          final topUpKey = 'smoke-topup-$suffix';
          final intent = await wallet.initiateTopUp(
            amountEtb: 100,
            idempotencyKey: topUpKey,
          );
          expect(intent.status, 'PENDING');

          final confirmation = await wallet.confirmTopUp(intent.intentId);
          expect(confirmation.status, 'SUCCESS');
          expect(
            confirmation.balanceEtb,
            closeTo(startBalance + 100, 0.01),
            reason: 'the backend credited the wallet exactly once',
          );

          // ── Trip creation: the server prices it ────────────────────────────
          final trip = await trips.createTrip(
            driverId: driver.driverUserId,
            routeId: route.id,
            originStopId: route.stops.first.id,
            destinationStopId: route.stops.last.id,
            origin: route.stops.first.name,
            destination: route.stops.last.name,
          );
          expect(trip.id, isNotEmpty);
          expect(
            trip.fareMinor,
            quote.fareMinor,
            reason: 'the stored fare is the server quote, not a client value',
          );
          expect(trip.isPaid, isFalse);

          // ── Payment ────────────────────────────────────────────────────────
          final paymentKey = 'smoke-pay-$suffix';
          final payment = await payments.payTrip(
            tripId: trip.id,
            idempotencyKey: paymentKey,
          );
          expect(payment.status, 'SUCCESS');
          expect(payment.amountMinor, trip.fareMinor);
          expect(payment.receiptNumber, isNotEmpty);

          // Replaying the same key returns the same payment, without charging.
          final replay = await payments.payTrip(
            tripId: trip.id,
            idempotencyKey: paymentKey,
          );
          expect(replay.paymentId, payment.paymentId);

          // ── Authoritative state afterwards ─────────────────────────────────
          final paidTrip = await trips.getTrip(trip.id);
          expect(paidTrip.isPaid, isTrue);
          expect(paidTrip.fareMinor, trip.fareMinor);

          final balanceAfter = await wallet.getBalance('self');
          expect(
            balanceAfter,
            closeTo(startBalance + 100 - trip.fareEtb, 0.01),
            reason: 'the wallet moved by exactly the trip fare',
          );

          final history = await wallet.getTransactionHistory('self');
          expect(
            history.any((tx) => tx.referenceId == trip.id && !tx.isCredit),
            isTrue,
            reason: 'the ledger holds the trip debit',
          );

          final found = await payments.findTripPayment(trip.id);
          expect(found?.paymentId, payment.paymentId);
        },
        timeout: const Timeout(Duration(minutes: 3)),
      );
    },
    skip: live
        ? (driverPassword.isEmpty
              ? 'set --dart-define=SMUNI_SMOKE_DRIVER_PASSWORD'
              : false)
        : 'live smoke: pass --dart-define=SMUNI_LIVE_BACKEND=true',
  );
}
