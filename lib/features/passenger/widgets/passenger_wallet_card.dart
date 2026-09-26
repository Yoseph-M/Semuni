import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../navigation/app_routes.dart';

/// Prominent wallet balance card for the passenger dashboard.
///
/// Features:
/// - Sophisticated #1C5E40-derived gradient
/// - Prominent ETB balance typography hierarchy
/// - Tappable "Top Up" action navigating to [AppRoutes.passengerWallet]
/// - Strong contrast and accessible touch targets
class PassengerWalletCard extends StatelessWidget {
  const PassengerWalletCard({
    super.key,
    required this.balance,
    this.onTopUpTap,
  });

  final double balance;
  final VoidCallback? onTopUpTap;

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
          // Subtle decorative background icon
          Positioned(
            right: -12,
            bottom: -16,
            child: Icon(
              Icons.account_balance_wallet_rounded,
              size: 110,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),

          // Main Card Content
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacingLg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Row: "Wallet Balance" label & mini brand badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Wallet Balance',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: AppConstants.iconSm - 2,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'SMUNI Pay',
                            style: AppTextStyles.labelSmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppConstants.spacingMd),

                // Balance Display & Top Up Action Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Formatted Currency Balance
                    Expanded(
                      child: Text(
                        AppFormatters.formatCurrency(balance),
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

                    // "Top Up" Pill Button
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                      child: InkWell(
                        onTap:
                            onTopUpTap ??
                            () {
                              Navigator.of(context)
                                  .pushNamed(AppRoutes.passengerWallet);
                            },
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
                                Icons.add_circle_outline_rounded,
                                size: AppConstants.iconSm + 1,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: AppConstants.spacingXs),
                              Text(
                                'Top Up',
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
