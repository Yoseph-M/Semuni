import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../navigation/app_routes.dart';

/// Prominent earnings card for the driver dashboard.
///
/// Features:
/// - Restrained green gradient matching semuni brand identity
/// - Bold ETB earnings display
/// - Subtext communicating completed ride count
class DriverEarningsCard extends StatelessWidget {
  const DriverEarningsCard({
    super.key,
    this.availableBalance = 0,
    this.onWithdrawTap,
  });

  final double availableBalance;
  final VoidCallback? onWithdrawTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.walletGradientStart, AppColors.walletGradientEnd],
        ),
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle background watermarked icon
          Positioned(
            right: -10,
            bottom: -16,
            child: Icon(
              Icons.trending_up_rounded,
              size: 110,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),

          // Card Content
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header label and brand badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Available Balance',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingXs + 2,
                        vertical: AppConstants.spacingXxs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                      ),
                      child: Text(
                        'semuni Pay',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppConstants.spacingMd),

                // Balance and right-aligned pill action, matching the
                // passenger wallet card layout.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        AppFormatters.formatCurrency(availableBalance),
                        style: AppTextStyles.amountDisplay.copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                      child: InkWell(
                        onTap:
                            onWithdrawTap ??
                            () =>
                                Navigator.of(context)
                                    .pushNamed(AppRoutes.driverWithdraw),
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusFull,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppConstants.spacingMd,
                            vertical: AppConstants.spacingSm - 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.account_balance_wallet_outlined,
                                size: AppConstants.iconSm + 1,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: AppConstants.spacingXs),
                              Text(
                                'Withdraw',
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
