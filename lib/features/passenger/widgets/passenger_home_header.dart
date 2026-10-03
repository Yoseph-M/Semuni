import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../navigation/app_routes.dart';

/// Clean header for the SMUNI Passenger Dashboard.
///
/// Displays:
/// - Passenger avatar with profile icon
/// - Dynamic time-based greeting with passenger's name
/// - Tappable notification button navigating to [AppRoutes.passengerNotifications]
/// - Optional [hasUnread] badge on the notification button
class PassengerHomeHeader extends StatelessWidget {
  const PassengerHomeHeader({
    super.key,
    required this.passengerName,
    this.onNotificationTap,
    this.hasUnread = false,
  });

  final String passengerName;
  final VoidCallback? onNotificationTap;

  /// When true, a small green dot badge is shown on the notification bell.
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    final greeting = AppFormatters.timeBasedGreeting();
    final displayName = passengerName.isNotEmpty ? passengerName : 'Passenger';

    return Row(
      children: [
        // Passenger Profile Avatar
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
              Icons.person_rounded,
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
                'Where would you like to go?',
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
                      .pushNamed(AppRoutes.passengerNotifications);
                },
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
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
                if (hasUnread)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.surface,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
