import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../navigation/app_routes.dart';

/// Available balance card with quick "Withdraw" action for drivers.
class DriverBalanceCard extends StatelessWidget {
  const DriverBalanceCard({
    super.key,
    required this.balance,
    this.onWithdrawTap,
  });

  final double balance;
  final VoidCallback? onWithdrawTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingLg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(color: AppColors.border, width: 1.0),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Balance Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Available Balance',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  AppFormatters.formatCurrency(balance),
                  style: AppTextStyles.headlineLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(width: AppConstants.spacingMd),

          // Withdraw CTA Button
          ElevatedButton.icon(
            onPressed:
                onWithdrawTap ??
                () {
                  Navigator.of(context).pushNamed(AppRoutes.driverWithdraw);
                },
            icon: const Icon(
              Icons.account_balance_wallet_outlined,
              size: AppConstants.iconSm + 2,
            ),
            label: const Text('Withdraw'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(116, 44),
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusFull),
              ),
              textStyle: AppTextStyles.labelMedium.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
