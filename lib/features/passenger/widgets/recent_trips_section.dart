import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/trip.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/trip_repository.dart';

/// Recent Trips section for the passenger dashboard.
///
/// Features:
/// - Section header with "Recent Trips" title and "View all" action
/// - Retrieves data asynchronously via [TripRepository]
/// - Compact, clean card items communicating route, price, and timestamp
/// - Gracefully handles loading and empty states
class RecentTripsSection extends StatefulWidget {
  const RecentTripsSection({
    super.key,
    required this.tripRepository,
    this.onViewAllTap,
    this.refreshToken = 0,
  });

  final TripRepository tripRepository;
  final VoidCallback? onViewAllTap;

  /// Changes when the parent wants fresh trip values without replacing
  /// this card's mounted layout.
  final int refreshToken;

  @override
  State<RecentTripsSection> createState() => _RecentTripsSectionState();
}

class _RecentTripsSectionState extends State<RecentTripsSection> {
  late Future<List<Trip>> _tripsFuture;
  List<Trip>? _cachedTrips;

  @override
  void initState() {
    super.initState();
    _tripsFuture = widget.tripRepository.getRecentTrips(limit: 4);
  }

  @override
  void didUpdateWidget(covariant RecentTripsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripRepository != widget.tripRepository ||
        oldWidget.refreshToken != widget.refreshToken) {
      _tripsFuture = widget.tripRepository.getRecentTrips(limit: 4);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Recent Trips',
              style: AppTextStyles.headlineSmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(
              onPressed:
                  widget.onViewAllTap ??
                  () {
                    Navigator.of(context)
                        .pushNamed(AppRoutes.passengerTripHistory);
                  },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSm,
                  vertical: AppConstants.spacingXs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View all',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: AppConstants.iconSm,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: AppConstants.spacingSm),

        // Trips List with Async State Handling
        FutureBuilder<List<Trip>>(
          future: _tripsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _cachedTrips = snapshot.data;
            }
            final trips = _cachedTrips ?? snapshot.data;

            if (trips == null &&
                snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppConstants.spacingXl),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              );
            }

            final list = trips ?? [];

            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spacingXl),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: AppConstants.iconXl,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(height: AppConstants.spacingSm),
                      Text(
                        'No recent trips yet',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
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
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: list.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.divider,
                  indent: 68,
                  endIndent: AppConstants.spacingMd,
                ),
                itemBuilder: (context, index) {
                  return _TripListItem(trip: list[index]);
                },
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TripListItem extends StatelessWidget {
  const _TripListItem({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context)
            .pushNamed(AppRoutes.passengerTripDetail, arguments: trip);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMd,
          vertical: AppConstants.spacingSm + 2,
        ),
        child: Row(
          children: [
            // Transportation Icon Badge
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm + 2),
              ),
              child: const Center(
                child: Icon(
                  Icons.local_taxi_outlined,
                  size: AppConstants.iconMd,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppConstants.spacingSm),

            // Route (From → To) & Timestamp
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trip.fromLocation,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 13,
                          color: AppColors.textHint,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          trip.toLocation,
                          style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppFormatters.formatTripDate(trip.completedAt),
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppConstants.spacingSm),

            // Amount Paid & Driver Name
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppFormatters.formatCurrency(trip.amountPaid),
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trip.driverName,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textHint,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ],
        ), // Row
      ), // Padding
    ); // InkWell
  }
}
