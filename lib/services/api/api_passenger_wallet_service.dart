import '../../core/network/api_client.dart';
import '../../models/passenger_wallet_transaction.dart';
import '../mock/mock_passenger_wallet_service.dart';

class ApiPassengerWalletService implements PassengerWalletService {
  ApiPassengerWalletService({required this.client});

  final ApiClient client;

  @override
  Future<List<PassengerWalletTransaction>> getTransactionHistory(
    String passengerId,
  ) async {
    final response = await client.get('/wallet/transactions');
    return response.asMapList.map(_toModel).toList(growable: false);
  }

  Future<double> getBalance(String passengerId) async {
    final response = await client.get('/wallet');
    return ((response.asMap['balance'] as num?) ?? 0) / 100.0;
  }

  Future<TopUpIntentView> initiateTopUp({
    required double amount,
    required String idempotencyKey,
    String? provider,
  }) async {
    final minor = (amount * 100).round();
    final response = await client.post(
      '/wallet/top-up',
      idempotencyKey: idempotencyKey,
      body: {
        'amount': minor,
        'idempotencyKey': idempotencyKey,
        if (provider != null) 'provider': provider,
      },
    );

    final data = response.asMap;
    return TopUpIntentView(
      intentId: _string(data['intentId']) ?? '',
      amountMinor: (data['amount'] as num?)?.toInt() ?? minor,
      provider: _string(data['provider']) ?? '',
      status: _string(data['status']) ?? 'PENDING',
      checkoutUrl: _string(data['checkoutUrl']),
    );
  }

  Future<double> confirmTopUp(String intentId) async {
    final response = await client.post('/wallet/top-up/$intentId/confirm');
    return ((response.asMap['balance'] as num?) ?? 0) / 100.0;
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
  Future<PassengerWalletTransaction> topUp(
    String passengerId,
    double amount,
  ) {
    throw StateError(
      'Use initiateTopUp() and confirmTopUp(); never credit a wallet locally.',
    );
  }

  static PassengerWalletTransaction _toModel(Map<String, dynamic> data) {
    final entryType =
        (_string(data['entryType']) ?? 'ADJUSTMENT').toUpperCase();

    return PassengerWalletTransaction(
      id: _string(data['id']) ?? '',
      description: _string(data['description']) ?? 'Transaction',
      amount: ((data['amount'] as num?) ?? 0) / 100.0,
      type: switch (entryType) {
        'TOP_UP' => PassengerWalletTransactionType.topUp,
        'REFUND' => PassengerWalletTransactionType.refund,
        _ => PassengerWalletTransactionType.payment,
      },
      createdAt:
          DateTime.tryParse(_string(data['createdAt']) ?? '') ?? DateTime.now(),
      referenceId: _string(data['referenceId']),
    );
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

class TopUpIntentView {
  const TopUpIntentView({
    required this.intentId,
    required this.amountMinor,
    required this.provider,
    required this.status,
    this.checkoutUrl,
  });

  final String intentId;
  final int amountMinor;
  final String provider;
  final String status;
  final String? checkoutUrl;

  bool get isPending => status == 'PENDING';
}
