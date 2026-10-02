import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/services/api/api_passenger_wallet_service.dart';

/// Wallet reads and the two-step top-up. The client must never be able to
/// credit a balance locally, so the tests focus on the exact HTTP surface.
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

  test('reads the balance from the server in minor units', () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope({
          'id': 'wallet-uuid',
          'balance': 12500,
          'currency': 'ETB',
          'status': 'ACTIVE',
        }),
      ),
    );

    final balance = await ApiPassengerWalletService(
      client: client,
    ).getBalance('passenger-1');

    expect(balance, 125.0);
  });

  test('maps ledger direction to credit/debit, not the entry type alone',
      () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope([
          {
            'id': 'entry-1',
            'entryType': 'TOP_UP',
            'direction': 'CREDIT',
            'amount': 5000,
            'description': 'Wallet top-up',
            'createdAt': '2026-10-01T10:00:00.000Z',
          },
          {
            'id': 'entry-2',
            'entryType': 'TRIP_PAYMENT',
            'direction': 'DEBIT',
            'amount': 8500,
            'description': 'Trip payment',
            'referenceId': 'trip-uuid-1',
            'createdAt': '2026-10-01T11:00:00.000Z',
          },
          {
            'id': 'entry-3',
            'entryType': 'ADJUSTMENT',
            'direction': 'DEBIT',
            'amount': 100,
            'description': 'Adjustment',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
        ]),
      ),
    );

    final history = await ApiPassengerWalletService(
      client: client,
    ).getTransactionHistory('passenger-1');

    expect(history, hasLength(3));
    expect(history[0].amount, 50.0);
    expect(history[0].isCredit, isTrue);
    expect(history[1].amount, 85.0, reason: 'the amount stays positive');
    expect(history[1].isCredit, isFalse, reason: 'the direction carries the sign');
    expect(history[2].isCredit, isFalse);
  });

  test('initiateTopUp sends integer santim and a client key', () async {
    late http.Request seen;
    final client = clientWith(
      MockClient((request) async {
        seen = request;
        return envelope({
          'intentId': 'intent-uuid-1',
          'amount': 5000,
          'currency': 'ETB',
          'provider': 'MOCK',
          'status': 'PENDING',
          'providerReference': 'MOCK-TOPUP-key-1',
          'checkoutUrl': null,
        }, 201);
      }),
    );

    final intent = await ApiPassengerWalletService(client: client).initiateTopUp(
      amountEtb: 50.0,
      idempotencyKey: 'topup-key-1',
    );

    expect(seen.url.path, '/api/v1/wallet/top-up');
    expect(seen.headers['Idempotency-Key'], 'topup-key-1');
    final body = jsonDecode(seen.body) as Map<String, dynamic>;
    expect(body['amount'], 5000);
    expect(body['idempotencyKey'], 'topup-key-1');
    expect(body.containsKey('provider'), isFalse);

    expect(intent.amountMinor, 5000);
    expect(intent.isPending, isTrue);
    expect(intent.requiresExternalCheckout, isFalse);
  });

  test('a provider-hosted checkout URL is carried to the UI', () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope({
          'intentId': 'intent-uuid-2',
          'amount': 10000,
          'currency': 'ETB',
          'provider': 'TELEBIRR',
          'status': 'PENDING',
          'checkoutUrl': 'https://checkout.telebirr.example/abc',
        }, 201),
      ),
    );

    final intent = await ApiPassengerWalletService(client: client).initiateTopUp(
      amountEtb: 100.0,
      idempotencyKey: 'topup-key-2',
    );

    expect(intent.requiresExternalCheckout, isTrue);
    expect(intent.checkoutUrl, contains('telebirr'));
  });

  test('confirmTopUp returns the authoritative post-credit balance', () async {
    late http.Request seen;
    final client = clientWith(
      MockClient((request) async {
        seen = request;
        return envelope({
          'intentId': 'intent-uuid-1',
          'status': 'SUCCESS',
          'balance': 15000,
          'currency': 'ETB',
        });
      }),
    );

    final confirmation = await ApiPassengerWalletService(
      client: client,
    ).confirmTopUp('intent-uuid-1');

    expect(seen.url.path, '/api/v1/wallet/top-up/intent-uuid-1/confirm');
    expect(confirmation.status, 'SUCCESS');
    expect(confirmation.balanceEtb, 150.0);
  });
}
