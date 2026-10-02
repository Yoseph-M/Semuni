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
    final passenger = authRepository.currentPassenger;
    if (passenger == null) {
      throw StateError('No authenticated passenger');
    }
    return _service.getTransactionHistory(passenger.id);
  }

  Future<void> topUp(double amount) {
    throw StateError(
      'Use an API-backed top-up flow (initiate intent → provider checkout → confirm).',
    );
  }

  Future<PassengerWalletTransaction> payTaxiFare({
    required double amount,
    required String fromLabel,
    required String toLabel,
    String? routeId,
  }) {
    throw StateError(
      'Use an API-backed trip payment flow. Local wallet debit is disabled.',
    );
  }
}

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
