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
}
