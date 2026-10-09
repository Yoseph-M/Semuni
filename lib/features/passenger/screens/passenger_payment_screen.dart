import 'dart:math';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/available_driver.dart';
import '../../../models/fare_quote.dart';
import '../../../models/passenger_route.dart';
import '../../../models/trip.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/driver_discovery_repository.dart';
import '../../../repositories/passenger_route_repository.dart';
import '../../../repositories/passenger_wallet_repository.dart';
import '../../../repositories/payment_repository.dart';
import '../../../repositories/trip_repository.dart';
import '../../../services/api/payment_service.dart';

/// Passenger Taxi Payment Screen.
///
/// The real financial flow, in order:
///
///   1. the passenger picks the segment (boarding and drop-off stops) and the
///      minibus/driver they are riding with
///   2. the backend quotes the fare (`POST /fares/calculate`)
///   3. "Continue" creates a trip (`POST /trips`); the server prices and stores
///      it, and the screen shows that authoritative fare
///   4. an explicit confirmation pays it (`POST /payments/trip`) with one
///      stable idempotency key
///   5. the wallet balance is re-read from the server — never adjusted locally
///
/// A timeout is not presented as a failure: the screen offers to check what the
/// backend actually recorded before the passenger retries.
class PassengerPaymentScreen extends StatefulWidget {
  const PassengerPaymentScreen({
    super.key,
    required this.route,
    required this.walletRepository,
    required this.authRepository,
    required this.tripRepository,
    required this.paymentRepository,
    required this.driverDiscoveryRepository,
    required this.routeRepository,
  });

  final PassengerRoute route;
  final PassengerWalletRepository walletRepository;
  final AuthRepository authRepository;
  final TripRepository tripRepository;
  final PaymentRepository paymentRepository;
  final DriverDiscoveryRepository driverDiscoveryRepository;
  final PassengerRouteRepository routeRepository;

  @override
  State<PassengerPaymentScreen> createState() => _PassengerPaymentScreenState();
}

enum _PaymentStage {
  /// Loading wallet, drivers and the first quote.
  loading,

  /// Journey selection (stops + driver) with a server quote shown.
  ready,

  /// Re-quoting after a stop change.
  preparingQuote,

  /// POST /trips in flight.
  creatingTrip,

  /// The trip exists; the server's fare is displayed for confirmation.
  tripCreated,

  /// POST /payments/trip in flight.
  processing,

  success,
  insufficientBalance,

  /// The outcome is genuinely unknown (timeout / lost response).
  unknown,

  failed,
}

class _PassengerPaymentScreenState extends State<PassengerPaymentScreen> {
  _PaymentStage _stage = _PaymentStage.loading;

  double? _balanceEtb;
  AvailableDriver? _selectedDriver;
  RouteStop? _originStop;
  RouteStop? _destinationStop;
  FareQuote? _quote;
  Trip? _trip;
  TripPayment? _payment;
  String? _inlineError;
  String? _failureMessage;
  late final TextEditingController _licenseController;

  /// One key per logical payment. It survives retries of the same payment and
  /// is only replaced when a genuinely new payment begins.
  String? _idempotencyKey;

  List<RouteStop> get _stops => widget.route.stops;

  @override
  void initState() {
    super.initState();
    _licenseController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _stage = _PaymentStage.loading;
      _inlineError = null;
    });

    try {
      final balance = await widget.walletRepository.getBalance();
      if (!mounted) return;

      setState(() {
        _balanceEtb = balance;
        _selectedDriver = null;
        _originStop = _stops.isNotEmpty ? _stops.first : null;
        _destinationStop = _stops.length >= 2 ? _stops.last : null;
      });

      // A route without two priced stops can never be quoted. Surface that in
      // the selection body (which explains it) instead of leaving the screen on
      // the loading spinner forever.
      if (_originStop == null || _destinationStop == null) {
        setState(() => _stage = _PaymentStage.ready);
        return;
      }

      await _requote();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _PaymentStage.failed;
        _failureMessage = error.userMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stage = _PaymentStage.failed;
        _failureMessage = 'Could not prepare this payment.';
      });
    }
  }

  Future<void> _findDriverByLicense() async {
    final license = _licenseController.text.trim();
    if (license.isEmpty) {
      setState(() => _inlineError = 'Enter the driver license number first.');
      return;
    }
    setState(() {
      _inlineError = null;
      _selectedDriver = null;
      _stage = _PaymentStage.preparingQuote;
    });
    try {
      final driver = await widget.driverDiscoveryRepository.findByLicense(
        license,
      );
      if (!mounted) return;
      setState(() {
        _selectedDriver = driver;
        _stage = _PaymentStage.ready;
        _inlineError = driver == null
            ? 'No active driver was found for that license number.'
            : null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _PaymentStage.ready;
        _inlineError = error.userMessage;
      });
    }
  }

  Future<void> _requote() async {
    final origin = _originStop;
    final destination = _destinationStop;
    if (origin == null || destination == null) return;

    setState(() {
      _stage = _PaymentStage.preparingQuote;
      _inlineError = null;
    });

    try {
      final quote = await widget.routeRepository.quoteFare(
        routeId: widget.route.id,
        originStopId: origin.id,
        destinationStopId: destination.id,
      );
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _stage = _PaymentStage.ready;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _stage = _PaymentStage.ready;
        _inlineError = error.userMessage;
      });
    }
  }

  bool get _canQuote {
    final origin = _originStop;
    final destination = _destinationStop;
    return origin != null &&
        destination != null &&
        origin.sequence < destination.sequence;
  }

  Future<void> _createTrip() async {
    final origin = _originStop;
    final destination = _destinationStop;
    final driver = _selectedDriver;
    if (origin == null || destination == null || driver == null) return;

    setState(() {
      _stage = _PaymentStage.creatingTrip;
      _inlineError = null;
    });

    try {
      final trip = await widget.tripRepository.createTrip(
        // The driver's *user* id: the identifier the trip API expects.
        driverId: driver.driverUserId,
        routeId: widget.route.id,
        originStopId: origin.id,
        destinationStopId: destination.id,
        origin: origin.name,
        destination: destination.name,
      );
      if (!mounted) return;
      setState(() {
        _trip = trip;
        // A new logical payment starts now, so it gets its own key.
        _idempotencyKey = _newIdempotencyKey(trip.id);
        _stage = _PaymentStage.tripCreated;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _stage = _PaymentStage.ready;
        _inlineError = error.userMessage;
      });
    }
  }

  Future<void> _confirmPayment() async {
    final trip = _trip;
    final key = _idempotencyKey;
    if (trip == null || key == null) return;

    setState(() {
      _stage = _PaymentStage.processing;
      _inlineError = null;
    });

    try {
      final payment = await widget.paymentRepository.payTrip(
        tripId: trip.id,
        idempotencyKey: key,
      );
      await _onPaymentSettled(payment);
    } on ApiException catch (error) {
      if (!mounted) return;
      await _handlePaymentFailure(error);
    }
  }

  Future<void> _onPaymentSettled(TripPayment payment) async {
    // Re-read the server balance; the client never computes a new one.
    final balance = await _safeBalance();
    await widget.authRepository.refreshPassengerProfile();
    if (!mounted) return;
    setState(() {
      _payment = payment;
      _balanceEtb = balance ?? _balanceEtb;
      _stage = _PaymentStage.success;
    });
  }

  Future<void> _handlePaymentFailure(ApiException error) async {
    // A trip that is already paid is a success that arrived via a different
    // route (a retry after a lost response, for example).
    if (error.code == ApiErrorCodes.tripAlreadyPaid) {
      final existing = await _safeFindPayment();
      if (existing != null && existing.isSuccess) {
        await _onPaymentSettled(existing);
        return;
      }
    }

    // The request may have succeeded even though the response was lost, so the
    // outcome is resolved against the backend before anything is claimed.
    if (error.isRetryable) {
      final existing = await _safeFindPayment();
      if (!mounted) return;
      if (existing != null && existing.isSuccess) {
        await _onPaymentSettled(existing);
        return;
      }
      setState(() {
        _stage = _PaymentStage.unknown;
        _failureMessage = error.userMessage;
      });
      return;
    }

    if (!mounted) return;
    if (error.code == ApiErrorCodes.walletInsufficientBalance ||
        error.code == ApiErrorCodes.withdrawalInsufficientBalance) {
      setState(() => _stage = _PaymentStage.insufficientBalance);
      return;
    }

    if (error.code == ApiErrorCodes.idempotencyConflict) {
      // The backend no longer recognises this key as this payment, so a fresh
      // attempt must carry a fresh key.
      _idempotencyKey = _newIdempotencyKey(_trip?.id ?? '');
    }

    setState(() {
      _stage = _PaymentStage.failed;
      _failureMessage = error.userMessage;
    });
  }

  Future<void> _retryPayment() async {
    final existing = await _safeFindPayment();
    if (!mounted) return;
    if (existing != null && existing.isSuccess) {
      await _onPaymentSettled(existing);
      return;
    }
    // Same key on purpose: the backend deduplicates the attempt.
    await _confirmPayment();
  }

  Future<double?> _safeBalance() async {
    try {
      return await widget.walletRepository.getBalance();
    } catch (_) {
      return null;
    }
  }

  Future<TripPayment?> _safeFindPayment() async {
    final trip = _trip;
    if (trip == null) return null;
    try {
      return await widget.paymentRepository.findTripPayment(trip.id);
    } catch (_) {
      return null;
    }
  }

  /// Prefixed so a key is recognisable in backend logs; unique per attempt.
  static String _newIdempotencyKey(String tripId) {
    final random = Random();
    final entropy = random.nextInt(0x7fffffff).toRadixString(36);
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'flutter-pay-$tripId-$stamp-$entropy';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Taxi Payment'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    return switch (_stage) {
      _PaymentStage.loading => const _BusyBody(label: 'Loading journey…'),
      _PaymentStage.preparingQuote => const _BusyBody(
        label: 'Checking the official fare…',
      ),
      _PaymentStage.creatingTrip => const _BusyBody(label: 'Creating trip…'),
      _PaymentStage.processing => const _BusyBody(label: 'Processing payment…'),
      _PaymentStage.tripCreated => _confirmationBody(),
      _PaymentStage.ready => _selectionBody(),
      _PaymentStage.success => _successBody(),
      _PaymentStage.insufficientBalance => _insufficientBody(),
      _PaymentStage.unknown => _unknownBody(),
      _PaymentStage.failed => _failedBody(),
    };
  }

  // ─── Selection ─────────────────────────────────────────────────────────────

  Widget _selectionBody() {
    final quote = _quote;
    final canContinue = _canQuote && quote != null && _selectedDriver != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            widget.route.name,
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),

          if (_stops.length < 2)
            _ErrorCard(
              message: 'This route has no stop data from the backend, so it cannot be priced.',
            ),

          if (_stops.length >= 2) ...[
            _SectionCard(
              children: [
                _StopDropdown(
                  label: 'Boarding at',
                  icon: Icons.radio_button_on_rounded,
                  iconColor: AppColors.success,
                  stops: _stops,
                  value: _originStop,
                  onChanged: (stop) {
                    setState(() => _originStop = stop);
                    _requote();
                  },
                ),
                const _Divider(),
                _StopDropdown(
                  label: 'Drop-off at',
                  icon: Icons.location_on_rounded,
                  iconColor: AppColors.error,
                  stops: _stops,
                  value: _destinationStop,
                  onChanged: (stop) {
                    setState(() => _destinationStop = stop);
                    _requote();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingMd),
            _SectionCard(
              children: [
                _InfoRow(
                  icon: Icons.payments_outlined,
                  iconColor: AppColors.primary,
                  label: 'Official fare',
                  value: quote == null
                      ? (_canQuote ? '…' : 'Choose a valid segment')
                      : AppFormatters.formatCurrency(quote.fareEtb),
                  valueBold: true,
                  valueColor: AppColors.primary,
                ),
                const _Divider(),
                _InfoRow(
                  icon: Icons.account_balance_wallet_outlined,
                  iconColor: AppColors.textSecondary,
                  label: 'Wallet',
                  value: _balanceEtb == null
                      ? '…'
                      : AppFormatters.formatCurrency(_balanceEtb!),
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingMd),
            _SectionCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppConstants.spacingMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your minibus',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppConstants.spacingXs),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('driver_license_field'),
                              controller: _licenseController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _findDriverByLicense(),
                              decoration: const InputDecoration(
                                labelText: 'Driver license number',
                                hintText: 'e.g. AA-DL-12345',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacingSm),
                          IconButton.filled(
                            key: const Key('find_driver_button'),
                            onPressed: _findDriverByLicense,
                            icon: const Icon(Icons.search),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.textOnPrimary,
                              disabledBackgroundColor: AppColors.border,
                            ),
                            tooltip: 'Find driver',
                          ),
                        ],
                      ),
                      if (_selectedDriver != null) ...[
                        const SizedBox(height: AppConstants.spacingSm),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(_selectedDriver!.fullName),
                          subtitle: Text(_selectedDriver!.displayLabel),
                          trailing: const Icon(
                            Icons.verified,
                            color: AppColors.success,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],

          if (_inlineError != null) ...[
            const SizedBox(height: AppConstants.spacingMd),
            _ErrorCard(message: _inlineError!),
          ],

          const SizedBox(height: AppConstants.spacingXl),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('confirm_payment_button'),
              onPressed: canContinue ? _createTrip : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                disabledBackgroundColor: AppColors.border,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                quote == null
                    ? 'Continue'
                    : 'Continue · ${AppFormatters.formatCurrency(quote.fareEtb)}',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
        ],
      ),
    );
  }

  // ─── Trip created: explicit confirmation of the authoritative fare ────────

  Widget _confirmationBody() {
    final trip = _trip!;
    final fare = trip.fareEtb;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppConstants.spacingMd),
          _SectionCard(
            children: [
              _InfoRow(
                icon: Icons.radio_button_on_rounded,
                iconColor: AppColors.success,
                label: 'From',
                value: trip.fromLocation,
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.location_on_rounded,
                iconColor: AppColors.error,
                label: 'To',
                value: trip.toLocation,
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.directions_bus_rounded,
                iconColor: AppColors.textSecondary,
                label: 'Minibus',
                value: _selectedDriver?.vehiclePlate ?? trip.driverName,
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.payments_outlined,
                iconColor: AppColors.primary,
                label: 'Official fare',
                value: AppFormatters.formatCurrency(fare),
                valueBold: true,
                valueColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'This price is the backend\'s official fare for this journey and is '
              'what will be charged. Confirm to pay it from your semuni wallet.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('pay_trip_button'),
              onPressed: _confirmPayment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                'Confirm payment · ${AppFormatters.formatCurrency(fare)}',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => setState(() {
                _stage = _PaymentStage.ready;
                _trip = null;
                _idempotencyKey = null;
              }),
              child: Text(
                'Back',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
        ],
      ),
    );
  }

  // ─── Success ───────────────────────────────────────────────────────────────

  Widget _successBody() {
    final payment = _payment;
    final fare = payment?.amountEtb ?? _trip?.fareEtb ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppConstants.spacingXxl),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.successContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 44,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            'Payment Successful',
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            AppFormatters.formatCurrency(fare),
            style: AppTextStyles.displaySmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (payment?.receiptNumber != null) ...[
            const SizedBox(height: AppConstants.spacingXs),
            Text(
              'Receipt ${payment!.receiptNumber}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppConstants.spacingXl),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Text(
                  'Remaining Balance',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppConstants.spacingXs),
                Text(
                  _balanceEtb == null
                      ? '—'
                      : AppFormatters.formatCurrency(_balanceEtb!),
                  style: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('complete_journey_button'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed('/passenger/trip-history');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                'View Trip History',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Done',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),
        ],
      ),
    );
  }

  // ─── Insufficient balance ─────────────────────────────────────────────────

  Widget _insufficientBody() {
    final fare = _trip?.fareEtb ?? _quote?.fareEtb ?? 0;
    return _CenteredMessage(
      icon: Icons.account_balance_wallet_outlined,
      iconColor: AppColors.error,
      iconBackground: AppColors.errorContainer,
      title: 'Insufficient Balance',
      message:
          'Your wallet has ${_balanceEtb == null ? '—' : AppFormatters.formatCurrency(_balanceEtb!)} '
          'but the fare is ${AppFormatters.formatCurrency(fare)}.',
      primaryLabel: 'Top Up Wallet',
      onPrimary: () {
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed('/passenger/wallet');
      },
      secondaryLabel: 'Back to Route',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }

  // ─── Unknown outcome ──────────────────────────────────────────────────────

  Widget _unknownBody() {
    return _CenteredMessage(
      icon: Icons.help_outline_rounded,
      iconColor: AppColors.primary,
      iconBackground: AppColors.primaryTint,
      title: 'Checking with semuni…',
      message: _failureMessage ?? 'The payment may have gone through. Check the trip status before trying again.',
      primaryLabel: 'Check Payment Status',
      onPrimary: _retryPayment,
      secondaryLabel: 'Back',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }

  // ─── Failure ──────────────────────────────────────────────────────────────

  Widget _failedBody() {
    return _CenteredMessage(
      icon: Icons.error_outline_rounded,
      iconColor: AppColors.error,
      iconBackground: AppColors.errorContainer,
      title: 'Payment Not Completed',
      message: _failureMessage ?? 'Something went wrong. Please try again.',
      primaryLabel: _trip == null ? 'Try Again' : 'Retry Payment',
      onPrimary: () {
        if (_trip == null) {
          _load();
        } else {
          _confirmPayment();
        }
      },
      secondaryLabel: 'Cancel',
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}

// ---------------------------------------------------------------------------
// Small shared widgets
// ---------------------------------------------------------------------------

class _StopDropdown extends StatelessWidget {
  const _StopDropdown({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.stops,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final List<RouteStop> stops;
  final RouteStop? value;
  final ValueChanged<RouteStop?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
        vertical: AppConstants.spacingSm,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppConstants.iconMd, color: iconColor),
          const SizedBox(width: AppConstants.spacingMd),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: DropdownButtonFormField<RouteStop>(
              initialValue: value,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSm,
                  vertical: AppConstants.spacingSm,
                ),
              ),
              items: stops
                  .map(
                    (stop) => DropdownMenuItem(
                      value: stop,
                      child: Text('${stop.sequence}. ${stop.name}'),
                    ),
                  )
                  .toList(growable: false),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusyBody extends StatelessWidget {
  const _BusyBody({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppConstants.spacingMd),
          Text(label),
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: iconColor),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            title,
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            message,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                primaryLabel,
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          TextButton(
            onPressed: onSecondary,
            child: Text(
              secondaryLabel,
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.error,
            size: AppConstants.iconMd,
          ),
          const SizedBox(width: AppConstants.spacingSm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueBold = false,
    this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool valueBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
        vertical: AppConstants.spacingMd,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppConstants.iconMd, color: iconColor),
          const SizedBox(width: AppConstants.spacingMd),
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }
}
