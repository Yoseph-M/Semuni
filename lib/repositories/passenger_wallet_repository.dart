import '../models/passenger_wallet_transaction.dart';
import '../models/top_up_intent.dart';
import '../services/mock/mock_passenger_wallet_service.dart';
import 'auth_repository.dart';

/// The passenger's wallet, read from and written through the backend.
///
/// There is deliberately no local credit or debit: a balance shown here is a
/// value the server reported, and it changes only when the server says so.
class PassengerWalletRepository {
  PassengerWalletRepository({
    PassengerWalletService? service,
    required this.authRepository,
  }) : _service = service ?? MockPassengerWalletService();

  final PassengerWalletService _service;
  final AuthRepository authRepository;

  /// Authoritative balance in ETB, from `GET /wallet`.
  Future<double> getBalance() async {
    final passenger = authRepository.currentPassenger;
    if (passenger == null) {
      throw StateError('No authenticated passenger');
    }
    return _service.getBalance(passenger.id);
  }

  Future<List<PassengerWalletTransaction>> getTransactionHistory() async {
    final passenger = authRepository.currentPassenger;
    if (passenger == null) {
      throw StateError('No authenticated passenger');
    }
    return _service.getTransactionHistory(passenger.id);
  }

  /// Starts a top-up: creates the intent and returns the provider details.
  /// No balance changes until [confirmTopUp] succeeds.
  Future<TopUpIntentView> initiateTopUp({
    required double amountEtb,
    required String idempotencyKey,
    String? provider,
  }) {
    return _service.initiateTopUp(
      amountEtb: amountEtb,
      idempotencyKey: idempotencyKey,
      provider: provider,
    );
  }

  /// Confirms the top-up; the backend verifies the provider and credits once.
  Future<TopUpConfirmation> confirmTopUp(String intentId) =>
      _service.confirmTopUp(intentId);
}
