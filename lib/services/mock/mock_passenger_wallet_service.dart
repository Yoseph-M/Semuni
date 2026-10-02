import '../../models/passenger_wallet_transaction.dart';

abstract class PassengerWalletService {
  Future<List<PassengerWalletTransaction>> getTransactionHistory(
    String passengerId,
  );
  Future<PassengerWalletTransaction> topUp(String passengerId, double amount);
}

class MockPassengerWalletService implements PassengerWalletService {
  MockPassengerWalletService({
    this.simulatedDelay = const Duration(milliseconds: 800),
  });

  final Duration simulatedDelay;

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
}
