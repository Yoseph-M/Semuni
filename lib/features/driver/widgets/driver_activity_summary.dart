import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/driver_activity.dart';

/// Concise summary section displaying the driver's daily operational metrics:
/// - Completed Rides
/// - Total Earnings
/// - Average Fare
class DriverActivitySummary extends StatelessWidget {
  const DriverActivitySummary({super.key, required this.activity});

  final DriverActivity activity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Text(
          "Today's Activity",
          style: AppTextStyles.headlineSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),

        // Metrics Container
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppConstants.spacingMd,
            vertical: AppConstants.spacingMd,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
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
              // Stat 1: Completed Rides
              Expanded(
                child: _MetricItem(
                  label: 'Completed Rides',
                  value: '${activity.completedRides}',
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: AppColors.primary,
                ),
              ),

              const SizedBox(
                height: 40,
                child: VerticalDivider(
                  color: AppColors.divider,
                  thickness: 1,
                  width: 1,
                ),
              ),

              // Stat 2: Total Earnings
              Expanded(
                child: _MetricItem(
                  label: 'Total Earnings',
                  value: AppFormatters.formatCurrency(activity.totalEarnings),
                  icon: Icons.payments_outlined,
                  iconColor: AppColors.primary,
                ),
              ),

              const SizedBox(
                height: 40,
                child: VerticalDivider(
                  color: AppColors.divider,
                  thickness: 1,
                  width: 1,
                ),
              ),

              // Stat 3: Average Fare
              Expanded(
                child: _MetricItem(
                  label: 'Average Fare',
                  value: AppFormatters.formatCurrency(activity.averageFare),
                  icon: Icons.receipt_outlined,
                  iconColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: AppConstants.iconSm + 2, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13.5,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 11.0,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
