import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/passenger_route.dart';
import '../../../models/trip.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/passenger_route_repository.dart';
import '../../../repositories/trip_repository.dart';

/// Screen for confirming a passenger ride booking and displaying the success state.
///
/// Implements Phase 11 — Passenger Ride Booking:
/// 1. Displays trip summary (pickup, destination, route code, fare, duration).
/// 2. Validates passenger wallet balance against the estimated fare.
/// 3. Shows insufficient balance warning + Top Up action if balance is inadequate.
/// 4. Dispatches booking request to [TripRepository] and updates [AuthRepository].
/// 5. Transitions to a dedicated "Ride Requested" success state with actions.
class PassengerBookingScreen extends StatefulWidget {
  const PassengerBookingScreen({
    super.key,
    this.route,
    required this.authRepository,
    this.tripRepository,
    this.passengerRouteRepository,
  });

  /// The route selected from the map discovery flow.
  /// If null, a fallback route is loaded from [passengerRouteRepository].
  final PassengerRoute? route;

  final AuthRepository authRepository;
  final TripRepository? tripRepository;
  final PassengerRouteRepository? passengerRouteRepository;

  @override
  State<PassengerBookingScreen> createState() => _PassengerBookingScreenState();
}

class _PassengerBookingScreenState extends State<PassengerBookingScreen> {
  PassengerRoute? _activeRoute;
  bool _isLoadingRoute = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  Trip? _bookedTrip;

  TripRepository get _effectiveTripRepository =>
      widget.tripRepository ?? TripRepository();

  PassengerRouteRepository get _effectivePassengerRouteRepository =>
      widget.passengerRouteRepository ?? PassengerRouteRepository();

  @override
  void initState() {
    super.initState();
    if (widget.route != null) {
      _activeRoute = widget.route;
    } else {
      _loadFallbackRoute();
    }
  }

  Future<void> _loadFallbackRoute() async {
    setState(() => _isLoadingRoute = true);
    try {
      final routes = await _effectivePassengerRouteRepository.getAllRoutes();
      final available = routes.where((r) => r.isAvailable).toList();
      if (mounted) {
        setState(() {
          _activeRoute = available.isNotEmpty ? available.first : null;
          _isLoadingRoute = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingRoute = false);
      }
    }
  }

  Future<void> _handleConfirmBooking(PassengerRoute route) async {
    final balance = widget.authRepository.passengerWalletBalance;
    if (balance < route.fare) {
      setState(() {
        _errorMessage = 'Insufficient wallet balance to book this ride.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final trip = await _effectiveTripRepository.bookRide(
        fromLocation: route.startLabel,
        toLocation: route.endLabel,
        fare: route.fare,
        routeCode: route.routeCode,
      );

      // Deduct balance in AuthRepository
      widget.authRepository.deductPassengerBalance(route.fare);

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _bookedTrip = trip;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to confirm ride booking. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _bookedTrip != null ? 'Booking Confirmed' : 'Confirm Booking',
          style: AppTextStyles.titleLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
          onPressed: () {
            if (_bookedTrip != null) {
              Navigator.of(
                context,
              ).pushNamedAndRemoveUntil(AppRoutes.passengerHome, (r) => false);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: _isLoadingRoute
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _bookedTrip != null
                ? _BookingSuccessView(
                    trip: _bookedTrip!,
                    route: _activeRoute,
                    remainingBalance:
                        widget.authRepository.passengerWalletBalance,
                    onBackToHome: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.passengerHome,
                        (r) => false,
                      );
                    },
                    onViewTrips: () {
                      Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRoutes.passengerHome,
                        (r) => false,
                      );
                    },
                  )
                : _activeRoute == null
                ? _NoRouteSelectedView(
                    onSelectRoute: () {
                      Navigator.of(context)
                          .pushReplacementNamed(AppRoutes.passengerMap);
                    },
                  )
                : _BookingConfirmationForm(
                    route: _activeRoute!,
                    walletBalance: widget.authRepository.passengerWalletBalance,
                    isSubmitting: _isSubmitting,
                    errorMessage: _errorMessage,
                    onConfirm: () => _handleConfirmBooking(_activeRoute!),
                    onTopUp: () {
                      Navigator.of(context)
                          .pushNamed(AppRoutes.passengerWallet);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Booking Confirmation Form
// -----------------------------------------------------------------------------

class _BookingConfirmationForm extends StatelessWidget {
  const _BookingConfirmationForm({
    required this.route,
    required this.walletBalance,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onConfirm,
    required this.onTopUp,
  });

  final PassengerRoute route;
  final double walletBalance;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onConfirm;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final hasSufficientBalance = walletBalance >= route.fare;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.screenVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Error Banner (if any)
          if (errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: AppColors.error),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: AppConstants.spacingSm),
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
          ],

          // 2. Route & Stations Card
          _RouteSummaryCard(route: route),
          const SizedBox(height: AppConstants.spacingMd),

          // 3. Fare & Wallet Card
          _FareAndPaymentCard(
            fare: route.fare,
            walletBalance: walletBalance,
            hasSufficientBalance: hasSufficientBalance,
            onTopUp: onTopUp,
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // 4. Instructions / Note Card
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: AppConstants.iconSm + 4,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: Text(
                    route.instructions ??
                        'Please be at the ${route.startLabel} taxi station when your driver arrives. Fare will be deducted automatically from your SMUNI wallet.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // 5. Confirm Ride Button
          SizedBox(
            height: AppConstants.minTouchTarget + 6,
            child: ElevatedButton(
              onPressed:
                  (isSubmitting || !hasSufficientBalance || !route.isAvailable)
                  ? null
                  : onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                disabledBackgroundColor: AppColors.surfaceVariant,
                disabledForegroundColor: AppColors.textHint,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                elevation: 0,
              ),
              child: isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.textOnPrimary,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_outline_rounded,
                          size: AppConstants.iconMd,
                        ),
                        const SizedBox(width: AppConstants.spacingSm),
                        Text(
                          'Confirm Ride',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: hasSufficientBalance
                                ? AppColors.textOnPrimary
                                : AppColors.textHint,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Route Summary Card
// -----------------------------------------------------------------------------

class _RouteSummaryCard extends StatelessWidget {
  const _RouteSummaryCard({required this.route});

  final PassengerRoute route;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Route code & availability
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (route.routeCode != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingSm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                  ),
                  child: Text(
                    route.routeCode!,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: route.isAvailable
                      ? AppColors.primaryTint
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: route.isAvailable
                            ? AppColors.primary
                            : AppColors.textHint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      route.isAvailable ? 'Active Route' : 'Unavailable',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: route.isAvailable
                            ? AppColors.primary
                            : AppColors.textHint,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Route Name
          Text(
            route.name,
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Origin and Destination Visual Connection
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Visual track
              Column(
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                  Container(
                    width: 2,
                    height: 38,
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                  const Icon(
                    Icons.location_on_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(width: AppConstants.spacingMd),

              // Labels
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Origin
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PICKUP',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          route.startLabel,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppConstants.spacingMd),

                    // Destination
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DESTINATION',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          route.endLabel,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const Divider(height: 32, thickness: 1, color: AppColors.divider),

          // Duration & Distance row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TripMetaItem(
                icon: Icons.timer_outlined,
                label: 'Duration',
                value: route.estimatedDuration ?? '~25 min',
              ),
              if (route.distanceKm != null)
                _TripMetaItem(
                  icon: Icons.straighten_rounded,
                  label: 'Distance',
                  value: '${route.distanceKm!.toStringAsFixed(1)} km',
                ),
              _TripMetaItem(
                icon: Icons.alt_route_rounded,
                label: 'Stops',
                value: '${route.intermediateStops.length} stops',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TripMetaItem extends StatelessWidget {
  const _TripMetaItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          size: AppConstants.iconSm + 2,
          color: AppColors.textSecondary,
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: AppTextStyles.labelMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Fare & Payment Card
// -----------------------------------------------------------------------------

class _FareAndPaymentCard extends StatelessWidget {
  const _FareAndPaymentCard({
    required this.fare,
    required this.walletBalance,
    required this.hasSufficientBalance,
    required this.onTopUp,
  });

  final double fare;
  final double walletBalance;
  final bool hasSufficientBalance;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: hasSufficientBalance ? AppColors.border : AppColors.warning,
          width: hasSufficientBalance ? 1.0 : 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title
          Text(
            'Payment Details',
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Estimated Fare Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Estimated Fare',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                AppFormatters.formatCurrency(fare),
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),

          const Divider(height: 24, thickness: 1, color: AppColors.divider),

          // Payment Method Row
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                  size: AppConstants.iconSm + 2,
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SMUNI Wallet',
                      style: AppTextStyles.titleSmall.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Available: ${AppFormatters.formatCurrency(walletBalance)}',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: hasSufficientBalance
                            ? AppColors.textSecondary
                            : AppColors.error,
                        fontWeight: hasSufficientBalance
                            ? FontWeight.normal
                            : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (!hasSufficientBalance)
                ElevatedButton(
                  onPressed: onTopUp,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.spacingMd,
                      vertical: AppConstants.spacingXs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusSm,
                      ),
                    ),
                  ),
                  child: const Text('Top Up'),
                ),
            ],
          ),

          // Insufficient Balance Notice Banner
          if (!hasSufficientBalance) ...[
            const SizedBox(height: AppConstants.spacingMd),
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingSm + 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFC2410C),
                    size: AppConstants.iconSm + 2,
                  ),
                  const SizedBox(width: AppConstants.spacingSm),
                  Expanded(
                    child: Text(
                      'Insufficient wallet balance. You need ${AppFormatters.formatCurrency(fare - walletBalance)} more.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: const Color(0xFF9A3412),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Booking Success View
// -----------------------------------------------------------------------------

class _BookingSuccessView extends StatelessWidget {
  const _BookingSuccessView({
    required this.trip,
    required this.route,
    required this.remainingBalance,
    required this.onBackToHome,
    required this.onViewTrips,
  });

  final Trip trip;
  final PassengerRoute? route;
  final double remainingBalance;
  final VoidCallback onBackToHome;
  final VoidCallback onViewTrips;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.screenVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppConstants.spacingLg),

          // Animated / Clean Checkmark Badge
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
                width: 3,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.check_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Title & Subtitle
          Text(
            'Ride Requested',
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            'Your ride from ${trip.fromLocation} to ${trip.toLocation} has been requested.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.spacingMd,
              vertical: AppConstants.spacingXs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primaryTint,
              borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppConstants.spacingXs),
                Text(
                  'Status: Requested',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // Trip Details Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _SuccessDetailRow(
                  label: 'Booking Ref',
                  value: trip.id,
                  isBold: true,
                ),
                const Divider(
                  height: 20,
                  thickness: 1,
                  color: AppColors.divider,
                ),
                _SuccessDetailRow(label: 'Pickup', value: trip.fromLocation),
                const SizedBox(height: 8),
                _SuccessDetailRow(label: 'Destination', value: trip.toLocation),
                const Divider(
                  height: 20,
                  thickness: 1,
                  color: AppColors.divider,
                ),
                _SuccessDetailRow(
                  label: 'Fare Paid',
                  value: AppFormatters.formatCurrency(trip.amountPaid),
                  valueColor: AppColors.primary,
                  isBold: true,
                ),
                const SizedBox(height: 8),
                _SuccessDetailRow(
                  label: 'Remaining Balance',
                  value: AppFormatters.formatCurrency(remainingBalance),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Meeting point tip
          Container(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.primary,
                  size: AppConstants.iconSm + 4,
                ),
                const SizedBox(width: AppConstants.spacingSm),
                Expanded(
                  child: Text(
                    'Head to the ${trip.fromLocation} taxi bay. Your ride is recorded in your recent trips.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // Action Buttons
          SizedBox(
            width: double.infinity,
            height: AppConstants.minTouchTarget + 4,
            child: ElevatedButton(
              onPressed: onBackToHome,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
                elevation: 0,
              ),
              child: Text(
                'Back to Home',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          SizedBox(
            width: double.infinity,
            height: AppConstants.minTouchTarget,
            child: OutlinedButton(
              onPressed: onViewTrips,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: const Text('View Recent Trips'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessDetailRow extends StatelessWidget {
  const _SuccessDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.isBold = false,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final bool isBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// No Route Selected Fallback View
// -----------------------------------------------------------------------------

class _NoRouteSelectedView extends StatelessWidget {
  const _NoRouteSelectedView({required this.onSelectRoute});

  final VoidCallback onSelectRoute;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.map_rounded, size: 64, color: AppColors.textHint),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'No Route Selected',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            'Please select a destination and route from the map to proceed with booking.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXl),
          ElevatedButton.icon(
            onPressed: onSelectRoute,
            icon: const Icon(Icons.explore_rounded),
            label: const Text('Explore Routes on Map'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
