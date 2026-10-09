import 'package:flutter_test/flutter_test.dart';

import 'package:smuni/models/available_driver.dart';
import 'package:smuni/models/driver_activity.dart';
import 'package:smuni/models/driver_withdrawal.dart';
import 'package:smuni/models/fare_quote.dart';
import 'package:smuni/models/passenger.dart';
import 'package:smuni/models/top_up_intent.dart';
import 'package:smuni/models/trip.dart';
import 'package:smuni/repositories/auth_repository.dart';
import 'package:smuni/repositories/driver_dashboard_repository.dart';
import 'package:smuni/repositories/driver_discovery_repository.dart';
import 'package:smuni/repositories/passenger_route_repository.dart';
import 'package:smuni/repositories/passenger_wallet_repository.dart';
import 'package:smuni/repositories/payment_repository.dart';
import 'package:smuni/repositories/trip_repository.dart';
import 'package:smuni/services/api/payment_service.dart';
import 'package:smuni/services/mock/mock_driver_dashboard_service.dart';
import 'package:smuni/services/mock/mock_driver_discovery_service.dart';
import 'package:smuni/services/mock/mock_passenger_route_service.dart';
import 'package:smuni/services/mock/mock_passenger_wallet_service.dart';
import 'package:smuni/services/mock/mock_trip_service.dart';

/// Repositories must forward to whatever implementation was injected: the app
/// injects API-backed services, while tests inject fakes/mocks. Nothing in a
/// repository may reach past its injected service.
void main() {
  test('TripRepository forwards creation to the injected service', () async {
    final service = _FakeTripService();
    final repository = TripRepository(tripService: service);

    final trip = await repository.createTrip(
      driverId: 'driver-user-1',
      routeId: 'route-1',
      originStopId: 'stop-1',
      destinationStopId: 'stop-2',
      origin: 'Bole',
      destination: 'Piazza',
    );

    expect(service.createdWith, 'driver-user-1');
    expect(trip.fareMinor, 8500);
  });

  test(
    'PassengerRouteRepository forwards quotes to the injected service',
    () async {
      final service = _FakeRouteService();
      final repository = PassengerRouteRepository(service: service);

      final quote = await repository.quoteFare(
        routeId: 'route-1',
        originStopId: 'stop-1',
        destinationStopId: 'stop-2',
      );

      expect(service.quotedRoute, 'route-1');
      expect(quote.fareMinor, 8500);
    },
  );

  test('PaymentRepository forwards the idempotency key', () async {
    final service = _FakePaymentService();
    final repository = PaymentRepository(service: service);

    await repository.payTrip(tripId: 'trip-1', idempotencyKey: 'key-1');
    expect(service.seenTrip, 'trip-1');
    expect(service.seenKey, 'key-1');

    final found = await repository.findTripPayment('trip-1');
    expect(found, isNotNull);
    expect(found!.status, 'SUCCESS');
  });

  test(
    'DriverDashboardRepository forwards the withdrawal destination',
    () async {
      final service = _FakeDriverDashboardService();
      final repository = DriverDashboardRepository(service: service);

      final withdrawal = await repository.requestWithdrawal(
        amountEtb: 120.0,
        destinationType: WithdrawalDestinationType.mobileMoney,
        destination: 'Telebirr',
        destinationAccount: '+251911234567',
        idempotencyKey: 'wd-key-1',
      );

      expect(
        service.seenDestinationType,
        WithdrawalDestinationType.mobileMoney,
      );
      expect(service.seenAccount, '+251911234567');
      expect(withdrawal.status, 'PENDING');
    },
  );

  test('PassengerWalletRepository forwards top-up intents', () async {
    final service = _FakeWalletService();
    final auth = AuthRepository();
    auth.setCurrentPassenger(
      const Passenger(
        id: 'passenger-1',
        name: 'Passenger',
        username: 'passenger',
        phone: '+251911000000',
        walletBalance: 0,
      ),
    );
    final repository = PassengerWalletRepository(
      service: service,
      authRepository: auth,
    );

    final intent = await repository.initiateTopUp(
      amountEtb: 50.0,
      idempotencyKey: 'topup-key-1',
    );

    expect(service.seenTopUpKey, 'topup-key-1');
    expect(intent.intentId, 'intent-1');

    final balance = await repository.getBalance();
    expect(balance, 125.0);
  });

  test('DriverDiscoveryRepository forwards to the injected service', () async {
    final service = _FakeDriverDiscoveryService();
    final drivers = await DriverDiscoveryRepository(service: service)
        .getAvailableDrivers();

    expect(drivers.single.driverUserId, 'driver-1');
  });

  test('mocks remain available for tests', () async {
    // The same interfaces accept the shipped mocks, so widget tests keep
    // working without a backend.
    expect(
      await TripRepository(tripService: MockTripService()).getRecentTrips(),
      isNotEmpty,
    );
    expect(
      await PassengerRouteRepository(service: MockPassengerRouteService())
          .getAllRoutes(),
      isNotEmpty,
    );
    expect(
      await DriverDashboardRepository(service: MockDriverDashboardService())
          .getTodayActivity(),
      isA<DriverActivity>(),
    );
    expect(
      await DriverDiscoveryRepository(service: MockDriverDiscoveryService())
          .getAvailableDrivers(),
      isNotEmpty,
    );
    expect(
      await PassengerWalletRepository(
        service: MockPassengerWalletService(),
        authRepository: AuthRepository(),
      ).confirmTopUp('intent-1'),
      isA<TopUpConfirmation>(),
    );
  });
}

// ─── Fakes ──────────────────────────────────────────────────────────────────

class _FakeTripService implements TripService {
  String? createdWith;

  @override
  Future<Trip> createTrip({
    required String driverId,
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    required String origin,
    required String destination,
    String? vehicleId,
    String? vehicleType,
  }) async {
    createdWith = driverId;
    return Trip(
      id: 'trip-1',
      fromLocation: origin,
      toLocation: destination,
      amountPaid: 85.0,
      completedAt: DateTime.now(),
      driverName: 'Driver',
      status: TripStatus.requested,
      fareMinor: 8500,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

class _FakeRouteService implements PassengerRouteService {
  String? quotedRoute;

  @override
  Future<FareQuote> quoteFare({
    required String routeId,
    required String originStopId,
    required String destinationStopId,
    String? vehicleType,
  }) async {
    quotedRoute = routeId;
    return FareQuote(
      fareMinor: 8500,
      currency: 'ETB',
      routeId: routeId,
      originStopId: originStopId,
      destinationStopId: destinationStopId,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

class _FakePaymentService implements PaymentService {
  String? seenTrip;
  String? seenKey;

  @override
  Future<TripPayment> payTrip({
    required String tripId,
    required String idempotencyKey,
  }) async {
    seenTrip = tripId;
    seenKey = idempotencyKey;
    return const TripPayment(
      paymentId: 'payment-1',
      tripId: 'trip-1',
      amountMinor: 8500,
      currency: 'ETB',
      status: 'SUCCESS',
    );
  }

  @override
  Future<TripPayment?> findTripPayment(String tripId) async =>
      const TripPayment(
        paymentId: 'payment-1',
        tripId: 'trip-1',
        amountMinor: 8500,
        currency: 'ETB',
        status: 'SUCCESS',
      );
}

class _FakeDriverDashboardService implements DriverDashboardService {
  WithdrawalDestinationType? seenDestinationType;
  String? seenAccount;

  @override
  Future<DriverWithdrawal> requestWithdrawal({
    required double amountEtb,
    required WithdrawalDestinationType destinationType,
    String? destination,
    String? destinationAccount,
    String? provider,
    required String idempotencyKey,
  }) async {
    seenDestinationType = destinationType;
    seenAccount = destinationAccount;
    return DriverWithdrawal(
      id: 'wd-1',
      amountMinor: (amountEtb * 100).round(),
      currency: 'ETB',
      status: 'PENDING',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

class _FakeWalletService implements PassengerWalletService {
  String? seenTopUpKey;

  @override
  Future<double> getBalance(String passengerId) async => 125.0;

  @override
  Future<TopUpIntentView> initiateTopUp({
    required double amountEtb,
    required String idempotencyKey,
    String? provider,
  }) async {
    seenTopUpKey = idempotencyKey;
    return const TopUpIntentView(
      intentId: 'intent-1',
      amountMinor: 5000,
      currency: 'ETB',
      provider: 'MOCK',
      status: 'PENDING',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used');
}

class _FakeDriverDiscoveryService implements DriverDiscoveryService {
  @override
  Future<List<AvailableDriver>> getAvailableDrivers() async => const [
    AvailableDriver(driverUserId: 'driver-1', fullName: 'Driver'),
  ];

  @override
  Future<AvailableDriver?> findByLicense(String licenseNumber) async => null;
}
