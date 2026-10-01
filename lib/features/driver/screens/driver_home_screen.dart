import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/driver_activity.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/driver_dashboard_repository.dart';
import '../widgets/driver_activity_summary.dart';
import '../widgets/driver_balance_card.dart';
import '../widgets/driver_bottom_nav.dart';
import '../widgets/driver_earnings_card.dart';
import '../widgets/driver_home_header.dart';
import '../widgets/driver_recent_transactions_section.dart';

/// Complete SMUNI Driver Home Dashboard.
///
/// Features:
/// - Environment background #F7FCF8 with dark green #1C5E40 brand accents
/// - Profile greeting header with notification action and logout
/// - Available balance card with quick Withdraw CTA
/// - Today's activity summary (completed rides, total earnings, avg fare)
/// - Recent transactions section from mock repository
/// - Three-tab bottom navigation (Home, Routes, Settings)
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.authRepository,
    this.dashboardRepository,
  });

  final AuthRepository authRepository;
  final DriverDashboardRepository? dashboardRepository;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  late final DriverDashboardRepository _dashboardRepository;
  late Future<DriverActivity> _activityFuture;

  @override
  void initState() {
    super.initState();
    _dashboardRepository =
        widget.dashboardRepository ?? DriverDashboardRepository();
    _activityFuture = _dashboardRepository.getTodayActivity();
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.authRepository.currentDriver;
    final driverName = driver?.firstName ?? 'Driver';
    final balance = driver?.accountBalance ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.screenHorizontalPadding,
                vertical: AppConstants.screenVerticalPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Header: Avatar, greeting, notifications, logout
                  DriverHomeHeader(
                    driverName: driverName,
                    authRepository: widget.authRepository,
                  ),
                  const SizedBox(height: AppConstants.spacingMd),

                  // 3. Today's Earnings (async from repository)
                  FutureBuilder<DriverActivity>(
                    future: _activityFuture,
                    builder: (context, snapshot) {
                      final activity = snapshot.data;
                      return DriverEarningsCard(
                        todayEarnings: activity?.totalEarnings ?? 0.0,
                        completedRides: activity?.completedRides ?? 0,
                      );
                    },
                  ),
                  const SizedBox(height: AppConstants.spacingMd),

                  // 4. Available Balance Card with Withdraw CTA
                  DriverBalanceCard(balance: balance),
                  const SizedBox(height: AppConstants.spacingXl),

                  // 5. Today's Activity Summary (async from repository)
                  FutureBuilder<DriverActivity>(
                    future: _activityFuture,
                    builder: (context, snapshot) {
                      final activity = snapshot.data;
                      if (activity == null) {
                        return const SizedBox.shrink();
                      }
                      return DriverActivitySummary(activity: activity);
                    },
                  ),
                  const SizedBox(height: AppConstants.spacingLg),

                  // 7. Recent Transactions Section
                  DriverRecentTransactionsSection(
                    repository: _dashboardRepository,
                  ),
                  const SizedBox(height: AppConstants.spacingXl),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const DriverBottomNav(currentIndex: 0),
    );
  }
}
