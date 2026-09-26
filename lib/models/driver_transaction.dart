/// Driver transaction model.
///
/// Represents a financial transaction in the driver's account history.
class DriverTransaction {
  const DriverTransaction({
    required this.id,
    required this.description,
    required this.amount,
    required this.type,
    required this.createdAt,
    required this.passengerName,
  });

  final String id;

  /// Human-readable description, e.g. "Payment from Yosef".
  final String description;

  /// Transaction amount in ETB. Always positive; use [type] for direction.
  final double amount;
  final DriverTransactionType type;
  final DateTime createdAt;

  /// The passenger or entity involved in this transaction.
  final String passengerName;

  /// Whether this is money coming in (credit) or going out (debit).
  bool get isCredit => type == DriverTransactionType.payment;

  @override
  String toString() =>
      'DriverTransaction(id: $id, amount: $amount, type: $type)';
}

/// Direction / category of a driver transaction.
enum DriverTransactionType { payment, withdrawal, adjustment }
