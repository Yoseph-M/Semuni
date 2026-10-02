/// Where a driver wants their money sent.
///
/// Mirrors the backend `WithdrawalDestinationType` enum. The API contract is
/// explicit about the destination; there is no generic "method" string, because
/// a free-text method cannot be validated or reconciled.
enum WithdrawalDestinationType {
  bank('BANK'),
  mobileMoney('MOBILE_MONEY');

  const WithdrawalDestinationType(this.apiValue);

  /// Exact value the backend accepts.
  final String apiValue;

  String get label => switch (this) {
    WithdrawalDestinationType.bank => 'Bank account',
    WithdrawalDestinationType.mobileMoney => 'Mobile money',
  };
}

/// A withdrawal request that has been accepted by the backend.
///
/// A withdrawal starts as PENDING and settles asynchronously
/// (PENDING → PROCESSING → SUCCESS/FAILED); nothing is final when this object
/// is returned, which is why the UI must say "submitted", never "paid".
class DriverWithdrawal {
  const DriverWithdrawal({
    required this.id,
    required this.amountMinor,
    required this.currency,
    required this.status,
    this.destinationType,
    this.destination,
    this.createdAt,
  });

  final String id;

  /// Amount in minor units (santim).
  final int amountMinor;

  final String currency;

  /// `PENDING`, `PROCESSING`, `SUCCESS` or `FAILED`.
  final String status;

  final WithdrawalDestinationType? destinationType;
  final String? destination;
  final DateTime? createdAt;

  double get amountEtb => amountMinor / 100;

  bool get isPending => status == 'PENDING' || status == 'PROCESSING';

  @override
  String toString() =>
      'DriverWithdrawal($id, $amountMinor $currency, $status)';
}
