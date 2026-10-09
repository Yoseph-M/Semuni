import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../navigation/app_route_observer.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/driver_activity.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/driver_dashboard_repository.dart';
import '../../../repositories/notification_repository.dart';
import '../widgets/driver_activity_summary.dart';
import '../widgets/driver_bottom_nav.dart';
import '../widgets/driver_earnings_card.dart';
import '../widgets/driver_home_header.dart';
import '../widgets/driver_recent_transactions_section.dart';

/// Complete semuni Driver Home Dashboard.
///
/// Features:
/// - Environment background #F7FCF8 with dark green #1C5E40 brand accents
/// - Profile greeting header with notification action
/// - Available balance card with quick Withdraw CTA
/// - Driver status card (Online / Offline toggle)
/// - Today's activity summary (completed trips, total earnings, avg fare)
/// - Primary action shortcuts (Transactions, Withdraw, Routes)
/// - Recent transactions section from mock repository
/// - Three-tab bottom navigation (Home, Routes, Settings)
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({
    super.key,
    required this.authRepository,
    this.dashboardRepository,
    this.notificationRepository,
  });

  final AuthRepository authRepository;
  final DriverDashboardRepository? dashboardRepository;
  final NotificationRepository? notificationRepository;

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> with RouteAware {
  late final DriverDashboardRepository _dashboardRepository;
  late Future<DriverActivity> _activityFuture;
  Timer? _refreshTimer;
  int _transactionsRefreshToken = 0;

  NotificationRepository get _effectiveNotificationRepository =>
      widget.notificationRepository ?? NotificationRepository();

  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _dashboardRepository =
        widget.dashboardRepository ?? DriverDashboardRepository();
    _activityFuture = _dashboardRepository.getTodayActivity();
    _loadUnreadCount();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshDashboard();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) appRouteObserver.subscribe(this, route);
  }

  @override
  void didPopNext() => _refreshDashboard();

  Future<void> _refreshDashboard() async {
    await widget.authRepository.refreshDriverProfile();
    if (!mounted) return;
    setState(() {
      _activityFuture = _dashboardRepository.getTodayActivity();
      _transactionsRefreshToken++;
    });
    _loadUnreadCount();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final count = await _effectiveNotificationRepository.getUnreadCount();
      if (mounted) {
        setState(() {
          _hasUnreadNotifications = count > 0;
        });
      }
    } catch (_) {
      // Non-fatal if count fails to load
    }
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
                  // 1. Header: Avatar, greeting, notifications
                  DriverHomeHeader(
                    driverName: driverName,
                    authRepository: widget.authRepository,
                    hasUnread: _hasUnreadNotifications,
                  ),
                  const SizedBox(height: AppConstants.spacingMd),

                  // 2. Today's Earnings (async from repository)
                  DriverEarningsCard(availableBalance: balance),
                  const SizedBox(height: AppConstants.spacingMd),

                  // 3. Today's Activity Summary (async from repository)
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

                  // 4. Recent Transactions Section
                  DriverRecentTransactionsSection(
                    repository: _dashboardRepository,
                    refreshToken: _transactionsRefreshToken,
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
