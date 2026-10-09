import '../../core/network/api_client.dart';
import '../../models/passenger_wallet_transaction.dart';
import '../../models/top_up_intent.dart';
import 'interfaces.dart';

/// The passenger wallet, as the backend owns it.
///
/// Balances are read from `GET /wallet` and money only moves through top-up
/// intents and trip payments. Nothing here can credit a wallet: the client has
/// no such capability, by design.
class ApiPassengerWalletService implements PassengerWalletService {
  ApiPassengerWalletService({required this.client});

  final ApiClient client;

  /// Current balance in ETB, from the server.
  @override
  Future<double> getBalance(String passengerId) async {
    final response = await client.get('/wallet');
    return _minorToEtb(response.asMap['balance']);
  }

  @override
  Future<List<PassengerWalletTransaction>> getTransactionHistory(
    String passengerId,
  ) async {
    final response = await client.get('/wallet/transactions');
    return response.asMapList.map(_toModel).toList(growable: false);
  }

  /// Step 1 of a top-up: record the intent. No balance changes yet.
  ///
  /// [idempotencyKey] belongs to the logical top-up, not to the HTTP attempt:
  /// retrying with the same key returns the same intent instead of creating a
  /// second one.
  @override
  Future<TopUpIntentView> initiateTopUp({
    required double amountEtb,
    required String idempotencyKey,
    String? provider,
  }) async {
    final amountMinor = (amountEtb * 100).round();
    if (amountMinor <= 0) {
      throw ArgumentError.value(amountEtb, 'amountEtb', 'must be positive');
    }

    final response = await client.post(
      '/wallet/top-up',
      idempotencyKey: idempotencyKey,
      body: {
        // The API speaks integer minor units; a fractional santim is not
        // representable in the ledger.
        'amount': amountMinor,
        'idempotencyKey': idempotencyKey,
        'provider': ?provider,
      },
    );

    final data = response.asMap;
    return TopUpIntentView(
      intentId: _string(data['intentId']) ?? '',
      amountMinor: (data['amount'] as num?)?.toInt() ?? amountMinor,
      currency: _string(data['currency']) ?? 'ETB',
      provider: _string(data['provider']) ?? '',
      status: _string(data['status']) ?? 'PENDING',
      providerReference: _string(data['providerReference']),
      checkoutUrl: _string(data['checkoutUrl']),
    );
  }

  /// Step 2 of a top-up: ask the backend to verify with the provider and
  /// credit the wallet. Returns the authoritative balance afterwards.
  @override
  Future<TopUpConfirmation> confirmTopUp(String intentId) async {
    final response = await client.post('/wallet/top-up/$intentId/confirm');
    final data = response.asMap;
    return TopUpConfirmation(
      intentId: _string(data['intentId']) ?? intentId,
      status: _string(data['status']) ?? 'SUCCESS',
      balanceMinor: (data['balance'] as num?)?.toInt() ?? 0,
      currency: _string(data['currency']) ?? 'ETB',
    );
  }

  /// Step 2, external-receipt path: hand the backend a receipt to verify.
  ///
  /// The backend resolves it through links.et and re-checks the amount,
  /// currency, owner and provider reference before crediting anything — at most
  /// once per receipt. Supplying a receipt is a request for verification, never
  /// a claim that the money arrived, so an unverifiable image settles nothing.
  @override
  Future<TopUpConfirmation> verifyReceipt({
    required String intentId,
    String? reference,
    String? url,
    String? imageBase64,
  }) async {
    final trimmedReference = reference?.trim();
    final trimmedUrl = url?.trim();
    final hasReference =
        trimmedReference != null && trimmedReference.isNotEmpty;
    final hasUrl = trimmedUrl != null && trimmedUrl.isNotEmpty;
    final hasImage = imageBase64 != null && imageBase64.isNotEmpty;

    if (!hasReference && !hasUrl && !hasImage) {
      throw ArgumentError(
        'Provide a receipt reference, a receipt URL or a receipt image.',
      );
    }

    final response = await client.post(
      '/wallet/top-up/$intentId/verify-receipt',
      body: {
        'reference': ?(hasReference ? trimmedReference : null),
        'url': ?(hasUrl ? trimmedUrl : null),
        'imageBase64': ?(hasImage ? imageBase64 : null),
      },
    );

    final data = response.asMap;
    return TopUpConfirmation(
      intentId: _string(data['intentId']) ?? intentId,
      status: _string(data['status']) ?? 'SUCCESS',
      balanceMinor: (data['balance'] as num?)?.toInt() ?? 0,
      currency: _string(data['currency']) ?? 'ETB',
      receiptReference: _string(data['receiptReference']),
    );
  }

  @override
  Future<PassengerWalletTransaction> payTaxiFare(
    String passengerId, {
    required double amount,
    required String description,
    String? referenceId,
  }) {
    throw StateError(
      'Taxi payment must use POST /payments/trip with a backend tripId; no local wallet debit is allowed.',
    );
  }

  @override
  Future<PassengerWalletTransaction> topUp(String passengerId, double amount) {
    throw StateError(
      'Use initiateTopUp() and confirmTopUp(); never credit a wallet locally.',
    );
  }

  static PassengerWalletTransaction _toModel(Map<String, dynamic> data) {
    final entryType = (_string(data['entryType']) ?? 'ADJUSTMENT')
        .toUpperCase();
    final direction = (_string(data['direction']) ?? '').toUpperCase();

    return PassengerWalletTransaction(
      id: _string(data['id']) ?? '',
      description: _string(data['description']) ?? 'Transaction',
      // Ledger amounts are positive in both directions; the sign is carried by
      // the direction, never by a negative amount.
      amount: _minorToEtb(data['amount']),
      type: switch (entryType) {
        'TOP_UP' => PassengerWalletTransactionType.topUp,
        'REFUND' => PassengerWalletTransactionType.refund,
        'TRIP_PAYMENT' => PassengerWalletTransactionType.payment,
        // Driver-side entries never appear in a passenger wallet, but an
        // adjustment still needs a category; direction decides the sign.
        _ => PassengerWalletTransactionType.payment,
      },
      createdAt:
          DateTime.tryParse(_string(data['createdAt']) ?? '') ?? DateTime.now(),
      referenceId: _string(data['referenceId']),
      creditOverride: switch (direction) {
        'CREDIT' => true,
        'DEBIT' => false,
        _ => null,
      },
    );
  }

  static double _minorToEtb(Object? minor) =>
      minor is num ? minor.toDouble() / 100 : 0;

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
