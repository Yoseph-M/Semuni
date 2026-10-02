import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:smuni/core/auth/auth_session.dart';
import 'package:smuni/core/network/api_client.dart';
import 'package:smuni/core/network/api_exception.dart';
import 'package:smuni/services/api/payment_service.dart';

/// Paying a trip: one idempotent request, and reconciliation for the times the
/// answer does not arrive.
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

  test('sends tripId and a stable idempotency key, then parses the receipt',
      () async {
    late http.BaseRequest seen;
    final client = clientWith(
      MockClient((request) async {
        seen = request;
        return envelope({
          'paymentId': 'payment-uuid-1',
          'tripId': 'trip-uuid-1',
          'amount': 8500,
          'currency': 'ETB',
          'status': 'SUCCESS',
          'receiptNumber': 'SEM-2026-000042',
        });
      }),
    );

    final payment = await ApiPaymentService(client: client).payTrip(
      tripId: 'trip-uuid-1',
      idempotencyKey: 'flutter-pay-abc',
    );

    expect(seen.url.path, '/api/v1/payments/trip');
    expect(seen.method, 'POST');
    expect(seen.headers['Idempotency-Key'], 'flutter-pay-abc');
    final body = jsonDecode((seen as http.Request).body) as Map<String, dynamic>;
    expect(body['tripId'], 'trip-uuid-1');
    expect(body['idempotencyKey'], 'flutter-pay-abc');

    expect(payment.paymentId, 'payment-uuid-1');
    expect(payment.amountEtb, 85.0);
    expect(payment.isSuccess, isTrue);
    expect(payment.receiptNumber, 'SEM-2026-000042');
  });

  test('surfaces an insufficient balance as a machine-readable code', () async {
    final client = clientWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'code': 'WALLET_INSUFFICIENT_BALANCE',
            'message': 'Insufficient wallet balance',
          }),
          402,
        ),
      ),
    );

    await expectLater(
      ApiPaymentService(client: client).payTrip(
        tripId: 'trip-uuid-1',
        idempotencyKey: 'flutter-pay-abc',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', ApiErrorCodes.walletInsufficientBalance)
            .having((e) => e.userMessage, 'userMessage', contains('too low')),
      ),
    );
  });

  test('finds an existing payment for a trip when reconciling', () async {
    final client = clientWith(
      MockClient(
        (request) async => envelope([
          {
            'id': 'payment-uuid-other',
            'tripId': 'trip-uuid-other',
            'amount': 5000,
            'currency': 'ETB',
            'status': 'SUCCESS',
          },
          {
            'id': 'payment-uuid-1',
            'tripId': 'trip-uuid-1',
            'amount': 8500,
            'currency': 'ETB',
            'status': 'SUCCESS',
            'receiptNumber': 'SEM-2026-000043',
          },
        ]),
      ),
    );

    final service = ApiPaymentService(client: client);
    final found = await service.findTripPayment('trip-uuid-1');
    expect(found, isNotNull);
    expect(found!.paymentId, 'payment-uuid-1');
    expect(found.receiptNumber, 'SEM-2026-000043');

    expect(await service.findTripPayment('trip-not-paid'), isNull);
  });
}
