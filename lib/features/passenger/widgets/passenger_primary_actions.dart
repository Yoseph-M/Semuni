import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../navigation/app_routes.dart';

/// Primary quick action cards below the wallet balance card:
/// - "Find Route" (Material car icon) → [AppRoutes.passengerMap]
/// - "Wallet" (Material wallet icon) → [AppRoutes.passengerWallet]
class PassengerPrimaryActions extends StatelessWidget {
  const PassengerPrimaryActions({
    super.key,
    this.onFindRouteTap,
    this.onWalletTap,
  });

  final VoidCallback? onFindRouteTap;
  final VoidCallback? onWalletTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Action 1: Find Route — navigates to the Map/Route Discovery screen.
        Expanded(
          child: _ActionCard(
            title: 'Find Route',
            subtitle: 'Search taxi stations',
            icon: Icons.directions_car_outlined,
            onTap:
                onFindRouteTap ??
                () {
                  Navigator.of(context).pushNamed(AppRoutes.passengerMap);
                },
          ),
        ),
        const SizedBox(width: AppConstants.spacingMd),

        // Action 2: Wallet
        Expanded(
          child: _ActionCard(
            title: 'Wallet',
            subtitle: 'Pay driver & cards',
            icon: Icons.account_balance_wallet_outlined,
            onTap:
                onWalletTap ??
                () {
                  Navigator.of(context).pushNamed(AppRoutes.passengerWallet);
                },
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
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
            horizontal: AppConstants.spacingMd,
            vertical: AppConstants.spacingMd,
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
          child: Row(
            children: [
              // Icon container with light green tint
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(
                    AppConstants.radiusSm + 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    icon,
                    size: AppConstants.iconLg - 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppConstants.spacingSm),

              // Title & Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
