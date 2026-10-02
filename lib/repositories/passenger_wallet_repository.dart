import '../models/passenger_wallet_transaction.dart';
import '../services/mock/mock_passenger_wallet_service.dart';
import 'auth_repository.dart';

class PassengerWalletRepository {
  PassengerWalletRepository({
    PassengerWalletService? service,
    required this.authRepository,
  }) : _service = service ?? MockPassengerWalletService();

  final PassengerWalletService _service;
  final AuthRepository authRepository;

  Future<List<PassengerWalletTransaction>> getTransactionHistory() async {
    final passenger =
        authRepository.currentPassenger ?? AuthRepository.defaultMockPassenger;
    return _service.getTransactionHistory(passenger.id);
  }

  Future<void> topUp(double amount) async {
    final passenger =
        authRepository.currentPassenger ?? AuthRepository.defaultMockPassenger;
    final tx = await _service.topUp(passenger.id, amount);

    // Update the balance in AuthRepository
    authRepository.addPassengerBalance(tx.amount);
  }

  /// Pays a taxi fare from the passenger wallet.
  ///
  /// Validates that the passenger has sufficient balance before charging.
  /// Throws [InsufficientBalanceException] if balance is too low.
  /// Returns the created [PassengerWalletTransaction] on success.
  Future<PassengerWalletTransaction> payTaxiFare({
    required double amount,
    required String fromLabel,
    required String toLabel,
    String? routeId,
  }) async {
    final passenger =
        authRepository.currentPassenger ?? AuthRepository.defaultMockPassenger;

    if (passenger.walletBalance < amount) {
      throw InsufficientBalanceException(
        available: passenger.walletBalance,
        required: amount,
      );
    }

    final description = 'Taxi Fare · $fromLabel → $toLabel';
    final tx = await _service.payTaxiFare(
      passenger.id,
      amount: amount,
      description: description,
      referenceId: routeId,
    );

    // Deduct the balance in AuthRepository
    authRepository.deductPassengerBalance(amount);
    return tx;
  }
}

/// Thrown when the passenger wallet balance is insufficient for a payment.
class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException({
    required this.available,
    required this.required,
  });

  final double available;
  final double required;

  double get shortfall => required - available;

  @override
  String toString() =>
      'InsufficientBalanceException(available: $available, required: $required)';
}
