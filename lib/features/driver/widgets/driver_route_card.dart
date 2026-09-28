import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/driver_route.dart';

/// Card widget representing an individual assigned taxi route.
///
/// Displays:
/// - Route identifier tag & status pill (Active / Inactive)
/// - Primary route name
/// - Visual start-to-destination path with station nodes
/// - Metadata chips: Standard fare, distance, estimated travel time
/// - Tap target for viewing full route details
class DriverRouteCard extends StatelessWidget {
  const DriverRouteCard({super.key, required this.route, this.onTap});

  final DriverRoute route;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        border: Border.all(
          color: route.isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : AppColors.border,
          width: route.isActive ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8.0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppConstants.radiusLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Route Code & Active/Inactive Status badge
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (route.routeCode != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppConstants.spacingSm,
                          vertical: 4.0,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(
                            AppConstants.radiusSm,
                          ),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          route.routeCode!,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    _buildStatusBadge(),
                  ],
                ),
                const SizedBox(height: AppConstants.spacingSm),

                // Route Name
                Text(
                  route.name,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppConstants.spacingMd),

                // Visual route path (Origin to Destination)
                _buildRoutePath(),

                const SizedBox(height: AppConstants.spacingMd),
                const Divider(color: AppColors.divider, height: 1.0),
                const SizedBox(height: AppConstants.spacingSm),

                // Footer metadata row: Fare, Distance, Duration, and Details indicator
                Row(
                  children: [
                    // Fare badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppConstants.spacingSm,
                        vertical: 4.0,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusSm,
                        ),
                      ),
                      child: Text(
                        AppFormatters.formatCurrency(route.fare),
                        style: AppTextStyles.labelMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppConstants.spacingSm),

                    // Distance
                    if (route.distanceKm != null) ...[
                      Icon(
                        Icons.straighten_rounded,
                        size: 14.0,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4.0),
                      Flexible(
                        child: Text(
                          '${route.distanceKm!.toStringAsFixed(1)} km',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppConstants.spacingSm),
                    ],

                    // Duration
                    if (route.estimatedDuration != null) ...[
                      Icon(
                        Icons.schedule_rounded,
                        size: 14.0,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4.0),
                      Flexible(
                        child: Text(
                          route.estimatedDuration!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],

                    const Spacer(),

                    // Details chevron
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20.0,
                      color: AppColors.textHint,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final isActive = route.isActive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: isActive ? AppColors.successContainer : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppConstants.radiusFull),
        border: Border.all(
          color: isActive ? AppColors.success : AppColors.border,
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7.0,
            height: 7.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? AppColors.success : AppColors.textHint,
            ),
          ),
          const SizedBox(width: 5.0),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: AppTextStyles.labelSmall.copyWith(
              color: isActive ? AppColors.success : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutePath() {
    return Column(
      children: [
        // Start Location row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 10.0,
              height: 10.0,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Expanded(
              child: Text(
                route.startLocation,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        // Vertical connecting segment
        Padding(
          padding: const EdgeInsets.only(left: 4.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(width: 2.0, height: 16.0, color: AppColors.border),
          ),
        ),

        // End Location row
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.location_on_rounded, size: 12.0, color: AppColors.error),
            const SizedBox(width: 7.0),
            Expanded(
              child: Text(
                route.endLocation,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
