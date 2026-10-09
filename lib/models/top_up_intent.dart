/// A wallet top-up intent as returned by the backend.
///
/// Creating an intent moves no money: the wallet is credited only after the
/// payment provider is verified (`POST /wallet/top-up/:id/confirm`).
class TopUpIntentView {
  const TopUpIntentView({
    required this.intentId,
    required this.amountMinor,
    required this.currency,
    required this.provider,
    required this.status,
    this.providerReference,
    this.checkoutUrl,
  });

  final String intentId;

  /// Amount in minor units (santim), exactly as the backend stores it.
  final int amountMinor;

  final String currency;
  final String provider;

  /// `PENDING`, `SUCCESS`, `FAILED` or `EXPIRED`.
  final String status;

  final String? providerReference;

  /// Provider-hosted checkout page, when the provider uses one.
  final String? checkoutUrl;

  bool get isPending => status == 'PENDING';

  /// True when the user must pay outside the app before confirming.
  bool get requiresExternalCheckout =>
      checkoutUrl != null && checkoutUrl!.isNotEmpty;

  double get amountEtb => amountMinor / 100;

  @override
  String toString() =>
      'TopUpIntentView($intentId, $amountMinor $currency, $provider, $status)';
}

/// Result of confirming a top-up: the authoritative post-credit wallet balance.
class TopUpConfirmation {
  const TopUpConfirmation({
    required this.intentId,
    required this.status,
    required this.balanceMinor,
    required this.currency,
    this.receiptReference,
  });

  final String intentId;
  final String status;

  /// Wallet balance in minor units, as reported by the backend.
  final int balanceMinor;

  final String currency;

  /// The external receipt the backend settled this top-up from, when it was
  /// verified through links.et rather than the provider's own confirmation.
  final String? receiptReference;

  double get balanceEtb => balanceMinor / 100;

  @override
  String toString() =>
      'TopUpConfirmation($intentId, $status, balance: $balanceMinor)';
}
