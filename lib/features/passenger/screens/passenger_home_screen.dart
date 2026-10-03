import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/notification_repository.dart';
import '../../../repositories/trip_repository.dart';
import '../widgets/passenger_bottom_nav.dart';
import '../widgets/passenger_home_header.dart';
import '../widgets/passenger_primary_actions.dart';
import '../widgets/passenger_wallet_card.dart';
import '../widgets/recent_trips_section.dart';

/// Complete SMUNI Passenger Home Dashboard.
///
/// Features:
/// - Environment background in #F7FCF8 with dark green #1C5E40 brand accents
/// - Profile greeting header with notification action and unread badge
/// - Primary wallet balance card with subtle green gradient & Top Up CTA
/// - Quick actions: "Find Route" and "Wallet"
/// - "Recent Trips" section with realistic Ethiopian route data
/// - Three-tab bottom navigation (Map, Home, Settings)
class PassengerHomeScreen extends StatefulWidget {
  const PassengerHomeScreen({
    super.key,
    required this.authRepository,
    this.tripRepository,
    this.notificationRepository,
  });

  final AuthRepository authRepository;
  final TripRepository? tripRepository;
  final NotificationRepository? notificationRepository;

  @override
  State<PassengerHomeScreen> createState() => _PassengerHomeScreenState();
}

class _PassengerHomeScreenState extends State<PassengerHomeScreen> {
  TripRepository get _effectiveTripRepository =>
      widget.tripRepository ?? TripRepository();

  NotificationRepository get _effectiveNotificationRepository =>
      widget.notificationRepository ?? NotificationRepository();

  bool _hasUnreadNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
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
      // Non-fatal — badge simply won't appear
    }
  }

  @override
  Widget build(BuildContext context) {
    final passenger = widget.authRepository.currentPassenger;
    final displayName = passenger?.firstName ?? 'Passenger';
    final balance = passenger?.walletBalance ?? 0.0;

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
                  // 1. Header (Greeting, Avatar, Notifications)
                  PassengerHomeHeader(
                    passengerName: displayName,
                    hasUnread: _hasUnreadNotifications,
                  ),
                  const SizedBox(height: AppConstants.spacingLg),

                  // 2. Primary Wallet Balance Card
                  PassengerWalletCard(balance: balance),
                  const SizedBox(height: AppConstants.spacingLg),

                  // 3. Primary Actions (Find Route | Wallet)
                  const PassengerPrimaryActions(),
                  const SizedBox(height: AppConstants.spacingXl),

                  // 4. Recent Trips Section
                  RecentTripsSection(tripRepository: _effectiveTripRepository),
                  const SizedBox(height: AppConstants.spacingXl),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const PassengerBottomNav(currentIndex: 1),
    );
  }
}
