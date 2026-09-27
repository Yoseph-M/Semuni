import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../navigation/app_routes.dart';

/// Primary quick action cards for the driver dashboard:
/// - "Transactions" (Material receipt/transactions icon) → [AppRoutes.driverTransactions]
/// - "Withdraw" (Material bank/wallet icon) → [AppRoutes.driverWithdraw]
/// - "Routes" (Material route/directions icon) → [AppRoutes.driverRoutes]
class DriverPrimaryActions extends StatelessWidget {
  const DriverPrimaryActions({
    super.key,
    this.onTransactionsTap,
    this.onWithdrawTap,
    this.onRoutesTap,
  });

  final VoidCallback? onTransactionsTap;
  final VoidCallback? onWithdrawTap;
  final VoidCallback? onRoutesTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Action 1: Transactions
        Expanded(
          child: _DriverActionCard(
            title: 'Transactions',
            subtitle: 'History',
            icon: Icons.receipt_long_outlined,
            onTap:
                onTransactionsTap ??
                () {
                  Navigator.of(context).pushNamed(AppRoutes.driverTransactions);
                },
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),

        // Action 2: Withdraw
        Expanded(
          child: _DriverActionCard(
            title: 'Withdraw',
            subtitle: 'To bank',
            icon: Icons.account_balance_outlined,
            onTap:
                onWithdrawTap ??
                () {
                  Navigator.of(context).pushNamed(AppRoutes.driverWithdraw);
                },
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),

        // Action 3: Routes
        Expanded(
          child: _DriverActionCard(
            title: 'Routes',
            subtitle: 'Assigned',
            icon: Icons.alt_route_rounded,
            onTap:
                onRoutesTap ??
                () {
                  Navigator.of(context).pushNamed(AppRoutes.driverRoutes);
                },
          ),
        ),
      ],
    );
  }
}

class _DriverActionCard extends StatelessWidget {
  const _DriverActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppConstants.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingXs,
            vertical: AppConstants.spacingSm + 2,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppColors.border, width: 1.0),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Icon container with light green tint
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(
                    AppConstants.radiusSm + 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: AppConstants.iconMd,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingXs),

              // Title
              Text(
                title,
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.0,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),

              // Subtitle
              Text(
                subtitle,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
