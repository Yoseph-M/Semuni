import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/driver_activity.dart';

/// Daily driver metrics. The card remains mounted while its values refresh.
class DriverActivitySummary extends StatelessWidget {
  const DriverActivitySummary({super.key, required this.activity});

  final DriverActivity activity;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        Icons.check_circle_outline_rounded,
        '${activity.completedRides}',
        'Completed rides',
      ),
      (
        Icons.payments_outlined,
        AppFormatters.formatCurrency(activity.totalEarnings),
        'Total earnings',
      ),
      (
        Icons.receipt_long_outlined,
        AppFormatters.formatCurrency(activity.averageFare),
        'Average fare',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Today's activity",
          style: AppTextStyles.headlineSmall.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Container(
          padding: const EdgeInsets.all(AppConstants.spacingSm),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFF1F8F4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            border: Border.all(color: AppColors.primaryTint),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              for (var index = 0; index < metrics.length; index++) ...[
                Expanded(
                  child: _MetricItem(
                    icon: metrics[index].$1,
                    value: metrics[index].$2,
                    label: metrics[index].$3,
                  ),
                ),
                if (index < metrics.length - 1)
                  const SizedBox(
                    height: 54,
                    child: VerticalDivider(color: AppColors.divider, width: 1),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacingXs),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryTint.withValues(alpha: .65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: AppColors.primary),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
