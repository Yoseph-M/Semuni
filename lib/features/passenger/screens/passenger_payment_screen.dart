import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/passenger_route.dart';
import '../../../repositories/passenger_wallet_repository.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/trip_repository.dart';

/// Passenger Taxi Payment Screen.
///
/// Allows a passenger to pay the taxi fare for an actual journey.
/// This is an explicit payment action — it is NOT triggered automatically
/// by route search or route detail viewing.
///
/// Flow:
///   Confirmation → Processing → Success / Insufficient Balance
class PassengerPaymentScreen extends StatefulWidget {
  const PassengerPaymentScreen({
    super.key,
    required this.route,
    required this.walletRepository,
    required this.authRepository,
    required this.tripRepository,
  });

  final PassengerRoute route;
  final PassengerWalletRepository walletRepository;
  final AuthRepository authRepository;
  final TripRepository tripRepository;

  @override
  State<PassengerPaymentScreen> createState() => _PassengerPaymentScreenState();
}

enum _PaymentStatus { idle, processing, success, insufficientBalance, failed }

class _PassengerPaymentScreenState extends State<PassengerPaymentScreen> {
  _PaymentStatus _status = _PaymentStatus.idle;
  double? _newBalance;

  Future<void> _processPayment() async {
    setState(() => _status = _PaymentStatus.processing);

    try {
      await widget.walletRepository.payTaxiFare(
        amount: widget.route.fare,
        fromLabel: widget.route.startLabel,
        toLabel: widget.route.endLabel,
        routeId: widget.route.id,
      );

      if (!mounted) return;
      setState(() {
        _status = _PaymentStatus.success;
        _newBalance = widget.authRepository.passengerWalletBalance;
      });
    } on InsufficientBalanceException {
      if (!mounted) return;
      setState(() => _status = _PaymentStatus.insufficientBalance);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _PaymentStatus.failed);
    }
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
      body: SafeArea(
        child: switch (_status) {
          _PaymentStatus.success => _SuccessBody(
            route: widget.route,
            newBalance:
                _newBalance ?? widget.authRepository.passengerWalletBalance,
            onCompleteJourney: () async {
              await widget.tripRepository.completeJourney(
                fromLocation: widget.route.startLabel,
                toLocation: widget.route.endLabel,
                fare: widget.route.fare,
                routeCode: widget.route.routeCode,
              );
              if (!mounted) return;
              Navigator.of(this.context).pop(); // pop payment screen
              Navigator.of(this.context).pushNamed('/passenger/trip-history');
            },
            onDone: () => Navigator.of(context).pop(),
          ),
          _PaymentStatus.insufficientBalance => _InsufficientBalanceBody(
            route: widget.route,
            currentBalance: widget.authRepository.passengerWalletBalance,
            onTopUp: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed('/passenger/wallet');
            },
            onBack: () => Navigator.of(context).pop(),
          ),
          _PaymentStatus.failed => _FailedBody(
            onRetry: () => setState(() => _status = _PaymentStatus.idle),
            onBack: () => Navigator.of(context).pop(),
          ),
          _PaymentStatus.processing => const _ProcessingBody(),
          _PaymentStatus.idle => _ConfirmationBody(
            route: widget.route,
            currentBalance: widget.authRepository.passengerWalletBalance,
            onConfirm: _processPayment,
          ),
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmation Body
// ---------------------------------------------------------------------------

class _ConfirmationBody extends StatelessWidget {
  const _ConfirmationBody({
    required this.route,
    required this.currentBalance,
    required this.onConfirm,
  });

  final PassengerRoute route;
  final double currentBalance;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final hasSufficientBalance = currentBalance >= route.fare;
    final afterPayment = currentBalance - route.fare;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppConstants.spacingMd),

          // Journey info card
          _SectionCard(
            children: [
              _InfoRow(
                icon: Icons.radio_button_on_rounded,
                iconColor: AppColors.success,
                label: 'From',
                value: route.startLabel,
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.location_on_rounded,
                iconColor: AppColors.error,
                label: 'To',
                value: route.endLabel,
              ),
              if (route.estimatedDuration != null) ...[
                const _Divider(),
                _InfoRow(
                  icon: Icons.access_time_rounded,
                  iconColor: AppColors.textSecondary,
                  label: 'Duration',
                  value: route.estimatedDuration!,
                ),
              ],
            ],
          ),

          const SizedBox(height: AppConstants.spacingMd),

          // Fare & balance card
          _SectionCard(
            children: [
              _InfoRow(
                icon: Icons.payments_outlined,
                iconColor: AppColors.primary,
                label: 'Taxi Fare',
                value: AppFormatters.formatCurrency(route.fare),
                valueBold: true,
                valueColor: AppColors.primary,
              ),
              const _Divider(),
              _InfoRow(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: AppColors.textSecondary,
                label: 'Wallet',
                value: AppFormatters.formatCurrency(currentBalance),
              ),
              if (hasSufficientBalance) ...[
                const _Divider(),
                _InfoRow(
                  icon: Icons.arrow_downward_rounded,
                  iconColor: AppColors.textHint,
                  label: 'After Payment',
                  value: AppFormatters.formatCurrency(afterPayment),
                  valueColor: AppColors.textSecondary,
                ),
              ],
            ],
          ),

          if (!hasSufficientBalance) ...[
            const SizedBox(height: AppConstants.spacingMd),
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: AppColors.errorContainer,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
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
                      'Insufficient wallet balance. You need '
                      '${AppFormatters.formatCurrency(route.fare - currentBalance)} more to pay this fare.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppConstants.spacingXl),

          // Pay button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              key: const Key('confirm_payment_button'),
              onPressed: hasSufficientBalance ? onConfirm : null,
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
                hasSufficientBalance
                    ? 'Pay ${AppFormatters.formatCurrency(route.fare)}'
                    : 'Insufficient Balance',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          if (!hasSufficientBalance) ...[
            const SizedBox(height: AppConstants.spacingSm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pushNamed('/passenger/wallet'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                ),
                child: Text(
                  'Top Up Wallet',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: AppConstants.spacingXxl),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Processing Body
// ---------------------------------------------------------------------------

class _ProcessingBody extends StatelessWidget {
  const _ProcessingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: AppConstants.spacingMd),
          Text('Processing payment…'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Success Body
// ---------------------------------------------------------------------------

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({
    required this.route,
    required this.newBalance,
    required this.onCompleteJourney,
    required this.onDone,
  });

  final PassengerRoute route;
  final double newBalance;
  final VoidCallback onCompleteJourney;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: AppConstants.spacingXxl),

          // Success icon
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
            AppFormatters.formatCurrency(route.fare),
            style: AppTextStyles.displaySmall.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            '${route.startLabel} → ${route.endLabel}',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),

          const SizedBox(height: AppConstants.spacingXl),

          // Remaining balance row
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
                  AppFormatters.formatCurrency(newBalance),
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
              onPressed: onCompleteJourney,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                'Complete Journey & View Trip',
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
              onPressed: onDone,
              child: Text(
                'Done',
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
}

// ---------------------------------------------------------------------------
// Insufficient Balance Body
// ---------------------------------------------------------------------------

class _InsufficientBalanceBody extends StatelessWidget {
  const _InsufficientBalanceBody({
    required this.route,
    required this.currentBalance,
    required this.onTopUp,
    required this.onBack,
  });

  final PassengerRoute route;
  final double currentBalance;
  final VoidCallback onTopUp;
  final VoidCallback onBack;

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
            decoration: const BoxDecoration(
              color: AppColors.errorContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              size: 36,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            'Insufficient Balance',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Your wallet has ${AppFormatters.formatCurrency(currentBalance)} '
            'but the fare is ${AppFormatters.formatCurrency(route.fare)}.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onTopUp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                'Top Up Wallet',
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
              onPressed: onBack,
              child: Text(
                'Back to Route',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Generic Failure Body
// ---------------------------------------------------------------------------

class _FailedBody extends StatelessWidget {
  const _FailedBody({required this.onRetry, required this.onBack});

  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: AppColors.error,
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            'Payment Failed',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            'Something went wrong. Please try again.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                'Try Again',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          TextButton(
            onPressed: onBack,
            child: Text(
              'Cancel',
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

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

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
