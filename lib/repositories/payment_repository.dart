import '../services/api/payment_service.dart';

/// Trip payments. The source of truth is the backend's payment record.
class PaymentRepository {
  /// [service] must be injected; there is no mock fallback, because a payment
  /// path that can silently do nothing is worse than one that refuses to run.
  PaymentRepository({required this.service});

  final PaymentService service;

  /// Pays [tripId] exactly once for a given [idempotencyKey].
  Future<TripPayment> payTrip({
    required String tripId,
    required String idempotencyKey,
  }) => service.payTrip(tripId: tripId, idempotencyKey: idempotencyKey);

  /// Reconciles an ambiguous payment outcome by asking the backend what
  /// actually happened to the trip.
  Future<TripPayment?> findTripPayment(String tripId) =>
      service.findTripPayment(tripId);
}
