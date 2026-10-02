/// The backend's official price for a journey.
///
/// Produced only by `POST /fares/calculate` from an ADMIN-activated tariff.
/// The client never computes or adjusts a fare; it displays this value and
/// sends the identifiers when creating the trip, which the backend re-quotes.
class FareQuote {
  const FareQuote({
    required this.fareMinor,
    required this.currency,
    required this.routeId,
    required this.originStopId,
    required this.destinationStopId,
    this.routeName,
    this.originStopName,
    this.destinationStopName,
    this.tariffId,
    this.tariffVersion,
    this.tariffRuleId,
  });

  /// Fare in minor units (santim). `ETB 85.00` is `8500`.
  final int fareMinor;

  final String currency;
  final String routeId;
  final String originStopId;
  final String destinationStopId;

  final String? routeName;
  final String? originStopName;
  final String? destinationStopName;

  /// The tariff that priced this journey, kept so the trip snapshot can be
  /// explained later.
  final String? tariffId;
  final String? tariffVersion;
  final String? tariffRuleId;

  double get fareEtb => fareMinor / 100;

  @override
  String toString() => 'FareQuote($fareMinor $currency, $routeId)';
}
