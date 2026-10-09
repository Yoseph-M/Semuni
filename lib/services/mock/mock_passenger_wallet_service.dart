import '../../core/network/api_exception.dart';
import '../../models/passenger_wallet_transaction.dart';
import '../../models/top_up_intent.dart';
import '../api/interfaces.dart';

export '../api/interfaces.dart' show PassengerWalletService;

class MockPassengerWalletService implements PassengerWalletService {
  MockPassengerWalletService({
    this.simulatedDelay = const Duration(milliseconds: 800),
    this.balanceEtb = 1250.00,
  });

  final Duration simulatedDelay;

  /// Balance the mock reports and mutates locally. Tests only.
  double balanceEtb;

  @override
  Future<double> getBalance(String passengerId) async {
    await Future.delayed(simulatedDelay);
    return balanceEtb;
  }

  @override
  Future<TopUpIntentView> initiateTopUp({
    required double amountEtb,
    required String idempotencyKey,
    String? provider,
  }) async {
    await Future.delayed(simulatedDelay);
    return TopUpIntentView(
      intentId: 'mock-intent-$idempotencyKey',
      amountMinor: (amountEtb * 100).round(),
      currency: 'ETB',
      provider: provider ?? 'MOCK',
      status: 'PENDING',
    );
  }

  @override
  Future<TopUpConfirmation> confirmTopUp(String intentId) async {
    await Future.delayed(simulatedDelay);
    return TopUpConfirmation(
      intentId: intentId,
      status: 'SUCCESS',
      balanceMinor: (balanceEtb * 100).round(),
      currency: 'ETB',
    );
  }

  /// Test double for the links.et receipt path. The real implementation is the
  /// backend's: it verifies the receipt upstream before crediting anything.
  @override
  Future<TopUpConfirmation> verifyReceipt({
    required String intentId,
    String? reference,
    String? url,
    String? imageBase64,
  }) async {
    await Future.delayed(simulatedDelay);
    return TopUpConfirmation(
      intentId: intentId,
      status: 'SUCCESS',
      balanceMinor: (balanceEtb * 100).round(),
      currency: 'ETB',
      receiptReference: reference ?? url ?? 'mock-receipt',
    );
  }

  final List<PassengerWalletTransaction> _transactions = [
    PassengerWalletTransaction(
      id: 'tx_p_1',
      description: 'Initial Bonus',
      amount: 1000.00,
      type: PassengerWalletTransactionType.topUp,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
    ),
    PassengerWalletTransaction(
      id: 'tx_p_2',
      description: 'Top Up - CBE Birr',
      amount: 250.00,
      type: PassengerWalletTransactionType.topUp,
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
    ),
  ];

  @override
  Future<List<PassengerWalletTransaction>> getTransactionHistory(
    String passengerId,
  ) async {
    await Future.delayed(simulatedDelay);
    // In a real app we'd filter by passengerId, but for mock we return all.
    // Return sorted by date descending.
    final sorted = List<PassengerWalletTransaction>.from(_transactions)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  @override
  Future<PassengerWalletTransaction> topUp(
    String passengerId,
    double amount,
  ) async {
    await Future.delayed(simulatedDelay);
    if (amount <= 0) {
      throw Exception('Top up amount must be greater than zero.');
    }
    balanceEtb += amount;
    final newTx = PassengerWalletTransaction(
      id: 'tx_p_${DateTime.now().millisecondsSinceEpoch}',
      description: 'Top Up',
      amount: amount,
      type: PassengerWalletTransactionType.topUp,
      createdAt: DateTime.now(),
    );
    _transactions.add(newTx);
    return newTx;
  }

  @override
  Future<PassengerWalletTransaction> payTaxiFare(
    String passengerId, {
    required double amount,
    required String description,
    String? referenceId,
  }) async {
    await Future.delayed(simulatedDelay);
    if (amount <= 0) {
      throw Exception('Payment amount must be greater than zero.');
    }
    if (balanceEtb < amount) {
      throw ApiException(
        kind: ApiErrorKind.badRequest,
        message: 'Insufficient balance.',
        code: ApiErrorCodes.walletInsufficientBalance,
      );
    }
    balanceEtb -= amount;
    final newTx = PassengerWalletTransaction(
      id: 'tx_p_${DateTime.now().millisecondsSinceEpoch}',
      description: description,
      amount: amount,
      type: PassengerWalletTransactionType.payment,
      createdAt: DateTime.now(),
      referenceId: referenceId,
    );
    _transactions.add(newTx);
    return newTx;
  }
}
