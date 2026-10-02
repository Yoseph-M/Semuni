import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/models/driver_transaction.dart';
import 'package:smuni/models/driver_withdrawal.dart';
import 'package:smuni/services/api/api_driver_dashboard_service.dart';
import 'package:smuni/services/api/api_driver_discovery_service.dart';

/// Driver earnings/transactions and the withdrawal contract: explicit
/// destination, integer minor units, one idempotency key.
void main() {
  const baseUrl = 'http://backend.test';

  ApiClient clientWith(MockClient mock) => ApiClient(
    httpClient: mock,
    session: AuthSession(tokenStore: InMemoryTokenStore()),
    baseUrl: baseUrl,
  );

  http.Response envelope(Object? data, [int status = 200]) => http.Response(
    jsonEncode({'data': data, 'meta': {}}),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  test('parses the earnings summary the server computed', () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope({
          'completedRides': 4,
          'totalEarnings': 340.0,
          'todayEarnings': 340.0,
          'averageFare': 85.0,
          'walletBalance': 680.0,
        }),
      ),
    );

    final activity = await ApiDriverDashboardService(
      client: client,
    ).getTodayActivity();

    expect(activity.completedRides, 4);
    expect(activity.totalEarnings, 340.0);
    expect(activity.averageFare, 85.0);
  });

  test('parses driver transactions with their type', () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope([
          {
            'id': 'entry-1',
            'description': 'Trip earnings',
            'amount': 85.0,
            'type': 'payment',
            'createdAt': '2026-10-02T08:00:00.000Z',
            'passengerName': 'Development Passenger',
          },
          {
            'id': 'entry-2',
            'description': 'Withdrawal',
            'amount': 200.0,
            'type': 'withdrawal',
            'createdAt': '2026-10-02T09:00:00.000Z',
            'passengerName': 'Withdrawal',
          },
        ]),
      ),
    );

    final transactions = await ApiDriverDashboardService(
      client: client,
    ).getRecentTransactions();

    expect(transactions, hasLength(2));
    expect(transactions.first.amount, 85.0);
    expect(transactions.first.type, DriverTransactionType.payment);
    expect(transactions.last.type, DriverTransactionType.withdrawal);
  });

  test('requestWithdrawal sends destinationType and an idempotency key',
      () async {
    late http.Request seen;
    final client = clientWith(
      MockClient((request) async {
        seen = request;
        return envelope({
          'id': 'withdrawal-uuid-1',
          'userId': 'driver-user-uuid',
          'amount': 30000,
          'currency': 'ETB',
          'status': 'PENDING',
          'destinationType': 'BANK',
          'destination': 'Commercial Bank of Ethiopia',
          'destinationAccount': '1000123456789',
          'provider': 'MOCK',
          'createdAt': '2026-10-03T10:00:00.000Z',
        }, 201);
      }),
    );

    final withdrawal = await ApiDriverDashboardService(
      client: client,
    ).requestWithdrawal(
      amountEtb: 300.0,
      destinationType: WithdrawalDestinationType.bank,
      destination: 'Commercial Bank of Ethiopia',
      destinationAccount: '1000123456789',
      idempotencyKey: 'withdraw-key-1',
    );

    expect(seen.url.path, '/api/v1/drivers/me/withdrawals');
    expect(seen.headers['Idempotency-Key'], 'withdraw-key-1');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['amount'], 30000, reason: 'integer santim, not 300');
    expect(body['destinationType'], 'BANK');
    expect(body['destinationAccount'], '1000123456789');
    expect(body['idempotencyKey'], 'withdraw-key-1');
    expect(body.containsKey('method'), isFalse,
        reason: 'the legacy generic method must not be sent');

    expect(withdrawal.status, 'PENDING');
    expect(withdrawal.amountEtb, 300.0);
    expect(withdrawal.destinationType, WithdrawalDestinationType.bank);
  });

  test('discovery returns only the identity a passenger needs', () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope([
          {
            'driverUserId': 'driver-user-uuid',
            'fullName': 'Development Driver',
            'vehiclePlate': 'DEV-12345',
            'vehicleType': 'MINIBUS',
          },
        ]),
      ),
    );

    final drivers = await ApiDriverDiscoveryService(
      client: client,
    ).getAvailableDrivers();

    expect(drivers, hasLength(1));
    expect(drivers.single.driverUserId, 'driver-user-uuid');
    expect(drivers.single.vehiclePlate, 'DEV-12345');
    expect(drivers.single.displayLabel, 'Development Driver · DEV-12345');
  });
}