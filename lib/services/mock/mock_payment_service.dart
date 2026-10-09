import '../../core/network/api_exception.dart';
import '../api/payment_service.dart';
import 'mock_passenger_wallet_service.dart';
import 'mock_trip_service.dart';

class MockPaymentService implements PaymentService {
  MockPaymentService({
    required this.tripService,
    required this.walletService,
    this.simulatedDelay = const Duration(milliseconds: 600),
  });

  final MockTripService tripService;
  final MockPassengerWalletService walletService;
  final Duration simulatedDelay;

  final Map<String, TripPayment> _payments = {};

  @override
  Future<TripPayment> payTrip({
    required String tripId,
    required String idempotencyKey,
  }) async {
    await Future.delayed(simulatedDelay);

    // Check if idempotency key already processed
    for (final payment in _payments.values) {
      if (payment.paymentId == idempotencyKey) {
        return payment;
      }
    }

    final trip = await tripService.getTrip(tripId);
    if (trip.isPaid) {
      throw ApiException(
        kind: ApiErrorKind.conflict,
        message: 'This trip is already paid.',
        code: ApiErrorCodes.tripAlreadyPaid,
      );
    }

    // Try paying via wallet. Will throw ApiException if insufficient balance.
    await walletService.payTaxiFare(
      'passenger_1',
      amount: trip.fareEtb,
      description: 'Taxi Fare: ${trip.fromLocation} to ${trip.toLocation}',
      referenceId: trip.id,
    );

    // Update trip status
    tripService.markTripPaid(trip.id, 'rcpt_$idempotencyKey');

    final payment = TripPayment(
      paymentId: idempotencyKey,
      tripId: trip.id,
      amountMinor: (trip.fareEtb * 100).round(),
      currency: 'ETB',
      status: 'SUCCESS',
      receiptNumber: 'rcpt_$idempotencyKey',
    );

    _payments[trip.id] = payment;
    return payment;
  }

  @override
  Future<TripPayment?> findTripPayment(String tripId) async {
    await Future.delayed(simulatedDelay);
    return _payments[tripId];
  }
}
