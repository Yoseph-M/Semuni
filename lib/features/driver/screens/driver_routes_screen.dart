import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/driver_route.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/driver_route_repository.dart';
import '../widgets/driver_bottom_nav.dart';
import '../widgets/driver_route_card.dart';
import '../widgets/driver_route_details_sheet.dart';

/// Screen displaying the driver's assigned taxi routes.
///
/// Features:
/// - AppBar / Header with back navigation, route count indicator
/// - Route filtering (All / Active Only)
/// - List of [DriverRouteCard]s representing Addis Ababa taxi corridors
/// - Interactive detail sheet on route tap ([DriverRouteDetailsSheet])
/// - Graceful empty state when no routes are assigned
/// - Integrated [DriverBottomNav] with destination 1 (Routes) active
class DriverRoutesScreen extends StatefulWidget {
  const DriverRoutesScreen({
    super.key,
    this.routeRepository,
    this.authRepository,
  });

  final DriverRouteRepository? routeRepository;
  final AuthRepository? authRepository;

  @override
  State<DriverRoutesScreen> createState() => _DriverRoutesScreenState();
}

class _DriverRoutesScreenState extends State<DriverRoutesScreen> {
  late final DriverRouteRepository _routeRepository;
  late Future<List<DriverRoute>> _routesFuture;

  // Filter selection: 0 = All, 1 = Active Only, 2 = Inactive
  int _selectedFilterIndex = 0;

  @override
  void initState() {
    super.initState();
    _routeRepository = widget.routeRepository ?? DriverRouteRepository();
    _routesFuture = _routeRepository.getAssignedRoutes();
  }

  void _reloadRoutes() {
    setState(() {
      _routesFuture = _routeRepository.getAssignedRoutes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 1.0,
        centerTitle: false,
        leading: canPop
            ? IconButton(
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppColors.textPrimary,
                ),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Routes',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              'Assigned taxi corridors & fares',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            tooltip: 'Refresh routes',
            onPressed: _reloadRoutes,
          ),
          const SizedBox(width: AppConstants.spacingSm),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: AppColors.border, height: 1.0),
        ),
      ),
      bottomNavigationBar: DriverBottomNav(
        currentIndex: 1,
        onTap: (index) {
          if (index == 1) return; // Already on Routes
          if (index == 0) {
            Navigator.of(context).pushReplacementNamed(AppRoutes.driverHome);
          } else if (index == 2) {
            Navigator.of(context).pushNamed(AppRoutes.driverSettings);
          }
        },
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: FutureBuilder<List<DriverRoute>>(
              future: _routesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (snapshot.hasError) {
                  return _buildErrorState(snapshot.error.toString());
                }

                final routes = snapshot.data ?? [];
                if (routes.isEmpty) {
                  return _buildEmptyState();
                }

                return _buildRoutesContent(routes);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoutesContent(List<DriverRoute> allRoutes) {
    final activeCount = allRoutes.where((r) => r.isActive).length;

    // Filtered routes list based on selected tab
    final displayedRoutes = switch (_selectedFilterIndex) {
      1 => allRoutes.where((r) => r.isActive).toList(),
      2 => allRoutes.where((r) => !r.isActive).toList(),
      _ => allRoutes,
    };

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async => _reloadRoutes(),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.screenHorizontalPadding,
          vertical: AppConstants.screenVerticalPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Summary Banner
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingMd),
              decoration: BoxDecoration(
                color: AppColors.primaryTint,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10.0),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: const Icon(
                      Icons.route_rounded,
                      color: AppColors.textOnPrimary,
                      size: 22.0,
                    ),
                  ),
                  const SizedBox(width: AppConstants.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$activeCount Active Routes Assigned',
                          style: AppTextStyles.titleSmall.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        const SizedBox(height: 2.0),
                        Text(
                          'Total of ${allRoutes.length} registered corridors in your fleet',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),

            // Filter Segmented Row
            Wrap(
              spacing: AppConstants.spacingSm,
              runSpacing: AppConstants.spacingSm,
              children: [
                _buildFilterChip(
                  index: 0,
                  label: 'All Routes (${allRoutes.length})',
                ),
                _buildFilterChip(index: 1, label: 'Active ($activeCount)'),
                _buildFilterChip(
                  index: 2,
                  label: 'Inactive (${allRoutes.length - activeCount})',
                ),
              ],
            ),
            const SizedBox(height: AppConstants.spacingMd),

            // Routes list or empty filter state
            if (displayedRoutes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Center(
                  child: Text(
                    'No routes found for the selected filter.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ...displayedRoutes.map((route) {
                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: AppConstants.spacingMd,
                  ),
                  child: DriverRouteCard(
                    route: route,
                    onTap: () => DriverRouteDetailsSheet.show(context, route),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({required int index, required String label}) {
    final isSelected = _selectedFilterIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedFilterIndex = index),
      borderRadius: BorderRadius.circular(AppConstants.radiusFull),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.radiusFull),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelMedium.copyWith(
            color: isSelected
                ? AppColors.textOnPrimary
                : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding * 2),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.surfaceVariant,
              ),
              child: const Icon(
                Icons.alt_route_rounded,
                size: 56.0,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            Text(
              'No Assigned Routes',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              'You currently do not have any assigned taxi routes. Contact your fleet supervisor to configure your operating corridors.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingLg),
            OutlinedButton.icon(
              onPressed: _reloadRoutes,
              icon: const Icon(Icons.refresh_rounded, size: 18.0),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48.0,
              color: AppColors.error,
            ),
            const SizedBox(height: AppConstants.spacingMd),
            Text(
              'Failed to Load Routes',
              style: AppTextStyles.titleMedium.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              error,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacingLg),
            FilledButton.icon(
              onPressed: _reloadRoutes,
              icon: const Icon(Icons.refresh_rounded, size: 18.0),
              label: const Text('Try Again'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
