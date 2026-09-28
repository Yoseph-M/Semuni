import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/driver_route.dart';

/// Modal bottom sheet displaying detailed route information.
///
/// Shows:
/// - Route name & code
/// - Origin and destination
/// - Ordered intermediate stops timeline
/// - Key trip metrics (fare, distance, travel time, operating hours)
/// - Active/Inactive status
class DriverRouteDetailsSheet extends StatelessWidget {
  const DriverRouteDetailsSheet({super.key, required this.route});

  final DriverRoute route;

  /// Helper to display this bottom sheet cleanly.
  static Future<void> show(BuildContext context, DriverRoute route) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DriverRouteDetailsSheet(route: route),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 12.0),
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2.0),
                ),
              ),
            ),

            // Sheet Title & Close button
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.screenHorizontalPadding,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Route Details',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (route.routeCode != null)
                        Text(
                          route.routeCode!,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: AppColors.textSecondary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppConstants.spacingSm),
            const Divider(color: AppColors.divider, height: 1.0),

            // Scrollable route details
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(
                  AppConstants.screenHorizontalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Route Name Banner
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppConstants.spacingMd),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint,
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8.0),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary,
                            ),
                            child: const Icon(
                              Icons.alt_route_rounded,
                              color: AppColors.textOnPrimary,
                              size: 20.0,
                            ),
                          ),
                          const SizedBox(width: AppConstants.spacingMd),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  route.name,
                                  style: AppTextStyles.titleMedium.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                                const SizedBox(height: 2.0),
                                Text(
                                  route.isActive
                                      ? 'Assigned & Active Route'
                                      : 'Inactive Route',
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: route.isActive
                                        ? AppColors.success
                                        : AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: AppConstants.spacingLg),

                    // Metrics Grid (Fare, Distance, Duration, Hours)
                    _buildMetricsGrid(),

                    const SizedBox(height: AppConstants.spacingLg),

                    // Stops & Waypoints Timeline
                    Text(
                      'Stations & Intermediate Stops',
                      style: AppTextStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingSm),

                    _buildStopsTimeline(),
                  ],
                ),
              ),
            ),

            // Bottom action
            Padding(
              padding: const EdgeInsets.all(
                AppConstants.screenHorizontalPadding,
              ),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(48.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.payments_outlined,
                label: 'Standard Fare',
                value: AppFormatters.formatCurrency(route.fare),
                highlightValue: true,
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.straighten_rounded,
                label: 'Distance',
                value: route.distanceKm != null
                    ? '${route.distanceKm!.toStringAsFixed(1)} km'
                    : 'N/A',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppConstants.spacingSm),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.schedule_rounded,
                label: 'Est. Duration',
                value: route.estimatedDuration ?? 'N/A',
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.access_time_rounded,
                label: 'Operating Hours',
                value: route.operatingHours ?? '06:00 – 21:00',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    bool highlightValue = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingSm),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppConstants.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18.0, color: AppColors.primary),
          const SizedBox(width: 8.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 10.0,
                  ),
                ),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: highlightValue
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStopsTimeline() {
    final allStops = [
      route.startLocation,
      ...route.intermediateStops,
      route.endLocation,
    ];

    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(allStops.length, (index) {
          final isFirst = index == 0;
          final isLast = index == allStops.length - 1;
          final stopName = allStops[index];

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Node and line
                SizedBox(
                  width: 24.0,
                  child: Column(
                    children: [
                      // Top line (if not first)
                      if (!isFirst)
                        Container(
                          width: 2.0,
                          height: 8.0,
                          color: AppColors.border,
                        )
                      else
                        const SizedBox(height: 8.0),

                      // Circle / node
                      Container(
                        width: isFirst || isLast ? 14.0 : 10.0,
                        height: isFirst || isLast ? 14.0 : 10.0,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFirst
                              ? AppColors.primary
                              : isLast
                              ? AppColors.error
                              : AppColors.border,
                          border: isFirst || isLast
                              ? null
                              : Border.all(
                                  color: AppColors.textHint,
                                  width: 1.5,
                                ),
                        ),
                        child: isLast
                            ? const Icon(
                                Icons.location_on,
                                size: 10.0,
                                color: Colors.white,
                              )
                            : null,
                      ),

                      // Bottom line (if not last)
                      if (!isLast)
                        Expanded(
                          child: Container(width: 2.0, color: AppColors.border),
                        )
                      else
                        const SizedBox(height: 8.0),
                    ],
                  ),
                ),
                const SizedBox(width: AppConstants.spacingSm),

                // Stop label
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            stopName,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: isFirst || isLast
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isFirst || isLast
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (isFirst)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTint,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              'Origin',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.primary,
                                fontSize: 10.0,
                              ),
                            ),
                          )
                        else if (isLast)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6.0,
                              vertical: 2.0,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.errorContainer,
                              borderRadius: BorderRadius.circular(4.0),
                            ),
                            child: Text(
                              'Destination',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.error,
                                fontSize: 10.0,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
