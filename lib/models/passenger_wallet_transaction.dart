/// Passenger wallet transaction model.
///
/// Represents a financial transaction in the passenger's wallet history.
class PassengerWalletTransaction {
  const PassengerWalletTransaction({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.createdAt,
    this.referenceId,
  });

  final String id;

  /// Human-readable description, e.g. "Wallet Top Up".
  final String description;

  /// Transaction amount in ETB. Always positive; use [type] for direction.
  final double amount;

  final PassengerWalletTransactionType type;

  final DateTime createdAt;

  /// Optional reference (e.g. trip ID or payment gateway ref).
  final String? referenceId;

  /// Whether this is money coming in (credit) or going out (debit).
  bool get isCredit =>
      type == PassengerWalletTransactionType.topUp ||
      type == PassengerWalletTransactionType.refund;

  @override
  String toString() =>
      'PassengerWalletTransaction(id: $id, amount: $amount, type: $type)';
}

/// Category of a passenger wallet transaction.
enum PassengerWalletTransactionType { topUp, payment, refund }
