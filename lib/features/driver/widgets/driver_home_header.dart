import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/auth_repository.dart';

/// Clean header for the SMUNI Driver Dashboard.
///
/// Displays:
/// - Driver avatar icon
/// - Dynamic time-based greeting with the driver's name
/// - Tappable notification action button
/// - Tappable logout action button
class DriverHomeHeader extends StatelessWidget {
  const DriverHomeHeader({
    super.key,
    required this.driverName,
    required this.authRepository,
    this.onNotificationTap,
    this.onLogoutTap,
  });

  final String driverName;
  final AuthRepository authRepository;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onLogoutTap;

  @override
  Widget build(BuildContext context) {
    final greeting = AppFormatters.timeBasedGreeting();
    final displayName = driverName.isNotEmpty ? driverName : 'Driver';

    return Row(
      children: [
        // Driver Profile Avatar
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: AppColors.primaryTint,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            border: Border.all(color: AppColors.border, width: 1.0),
          ),
          child: const Center(
            child: Icon(
              Icons.drive_eta_rounded,
              size: AppConstants.iconLg,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),

        // Greeting & Name
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$greeting, $displayName',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'Driver Dashboard',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        const SizedBox(width: AppConstants.spacingSm),

        // Notification Action Button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap:
                onNotificationTap ??
                () {
                  Navigator.of(context)
                      .pushNamed(AppRoutes.driverNotifications);
                },
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: AppColors.border, width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.notifications_outlined,
                  size: AppConstants.iconMd + 2,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ),

        const SizedBox(width: AppConstants.spacingXs),

        // Logout Action Button
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap:
                onLogoutTap ??
                () async {
                  await authRepository.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushReplacementNamed(AppRoutes.login);
                  }
                },
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(color: AppColors.border, width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.logout_rounded,
                  size: AppConstants.iconMd,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
