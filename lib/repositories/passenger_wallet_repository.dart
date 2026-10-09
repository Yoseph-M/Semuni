import '../services/api/interfaces.dart';
import '../models/passenger_wallet_transaction.dart';
import '../models/top_up_intent.dart';

import 'auth_repository.dart';

/// The passenger's wallet, read from and written through the backend.
///
/// There is deliberately no local credit or debit: a balance shown here is a
/// value the server reported, and it changes only when the server says so.
class PassengerWalletRepository {
  PassengerWalletRepository({
    PassengerWalletService? service,
    required this.authRepository,
  }) : _service = service ?? const _EmptyPassengerWalletService();

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

  /// Settles the top-up from an external receipt the passenger supplies
  /// (a links.et link, a payment reference, or a receipt image). Verification
  /// belongs to the backend: nothing is credited on the client's word, and a
  /// receipt the backend cannot verify upstream credits nothing.
  Future<TopUpConfirmation> verifyReceipt({
    required String intentId,
    String? reference,
    String? url,
    String? imageBase64,
  }) => _service.verifyReceipt(
    intentId: intentId,
    reference: reference,
    url: url,
    imageBase64: imageBase64,
  );
}

class _EmptyPassengerWalletService implements PassengerWalletService {
  const _EmptyPassengerWalletService();

  @override
  Future<double> getBalance(String passengerId) async => 0.0;

  @override
  Future<List<PassengerWalletTransaction>> getTransactionHistory(
    String passengerId,
  ) async => const [];

  @override
  Future<TopUpIntentView> initiateTopUp({
    required double amountEtb,
    required String idempotencyKey,
    String? provider,
  }) async => throw StateError('No wallet service configured');

  @override
  Future<TopUpConfirmation> confirmTopUp(String intentId) async =>
      throw StateError('No wallet service configured');

  @override
  Future<TopUpConfirmation> verifyReceipt({
    required String intentId,
    String? reference,
    String? url,
    String? imageBase64,
  }) async => throw StateError('No wallet service configured');

  @override
  Future<PassengerWalletTransaction> topUp(
    String passengerId,
    double amount,
  ) async => throw StateError('No wallet service configured');

  @override
  Future<PassengerWalletTransaction> payTaxiFare(
    String passengerId, {
    required double amount,
    required String description,
    String? referenceId,
  }) async => throw StateError('No wallet service configured');
}
