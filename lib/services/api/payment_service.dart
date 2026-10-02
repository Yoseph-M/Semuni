import '../../core/network/api_client.dart';

/// The backend's record of a settled (or attempted) trip payment.
class TripPayment {
  const TripPayment({
    required this.paymentId,
    required this.tripId,
    required this.amountMinor,
    required this.currency,
    required this.status,
    this.receiptNumber,
  });

  final String paymentId;
  final String tripId;

  /// Amount actually charged, in minor units (santim).
  final int amountMinor;

  final String currency;

  /// `PENDING`, `SUCCESS`, `FAILED` or `REFUNDED`.
  final String status;

  /// Receipt allocated by the backend on success.
  final String? receiptNumber;

  double get amountEtb => amountMinor / 100;

  bool get isSuccess => status == 'SUCCESS';

  @override
  String toString() =>
      'TripPayment($paymentId, trip $tripId, $amountMinor $currency, $status)';
}

/// Trip settlement.
///
/// Paying a trip is a single idempotent request: the wallet transfer, ledger
/// entries, payment record and trip status all move together inside the
/// backend's transaction. The client's only jobs are to send a stable
/// idempotency key and to believe the server's answer.
abstract interface class PaymentService {
  /// Pays for [tripId]. [idempotencyKey] must be generated once per logical
  /// payment and reused for every retry of it — a timeout is not a failure.
  Future<TripPayment> payTrip({
    required String tripId,
    required String idempotencyKey,
  });

  /// Finds the payment a trip already has, if any.
  ///
  /// Used to reconcile an ambiguous outcome (a timed-out request that may have
  /// succeeded) before telling the user anything.
  Future<TripPayment?> findTripPayment(String tripId);
}

class ApiPaymentService implements PaymentService {
  ApiPaymentService({required this.client});

  final ApiClient client;

  @override
  Future<TripPayment> payTrip({
    required String tripId,
    required String idempotencyKey,
  }) async {
    final response = await client.post(
      '/payments/trip',
      idempotencyKey: idempotencyKey,
      body: {'tripId': tripId, 'idempotencyKey': idempotencyKey},
    );
    return _toModel(response.asMap);
  }

  @override
  Future<TripPayment?> findTripPayment(String tripId) async {
    final response = await client.get('/payments');
    for (final payment in response.asMapList) {
      if (payment['tripId'] == tripId) return _toModel(payment);
    }
    return null;
  }

  static TripPayment _toModel(Map<String, dynamic> data) {
    return TripPayment(
      // Creation responses call it `paymentId`; the list endpoint returns the
      // full record whose id field is `id`.
      paymentId: _string(data['paymentId']) ?? _string(data['id']) ?? '',
      tripId: _string(data['tripId']) ?? '',
      amountMinor: (data['amount'] as num?)?.toInt() ?? 0,
      currency: _string(data['currency']) ?? 'ETB',
      status: (_string(data['status']) ?? 'FAILED').toUpperCase(),
      receiptNumber: _string(data['receiptNumber']),
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
