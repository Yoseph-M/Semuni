import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../navigation/app_routes.dart';

/// Reusable bottom navigation bar for the semuni passenger experience.
///
/// Contains exactly three destinations:
/// 0: Map ([AppRoutes.passengerMap])
/// 1: Home ([AppRoutes.passengerHome]) — Active/Selected
/// 2: Settings ([AppRoutes.passengerSettings])
class PassengerBottomNav extends StatelessWidget {
  const PassengerBottomNav({super.key, this.currentIndex = 1, this.onTap});

  /// Index of the currently active destination. Defaults to 1 (Home).
  final int currentIndex;

  /// Custom tap handler. If null, standard named route navigation is executed.
  final ValueChanged<int>? onTap;

  void _handleDestinationSelected(BuildContext context, int index) {
    if (onTap != null) {
      onTap!(index);
      return;
    }

    if (index == currentIndex) return;

    // Always pop back to passengerHome root first so the passengerHome instance
    // is preserved and tabs do not stack on top of each other.
    Navigator.of(context).popUntil(
      (route) =>
          route.settings.name == AppRoutes.passengerHome || route.isFirst,
    );

    switch (index) {
      case 0:
        Navigator.of(context).pushNamed(AppRoutes.passengerMap);
        break;
      case 1:
        // Already at preserved passengerHome
        break;
      case 2:
        Navigator.of(context).pushNamed(AppRoutes.passengerSettings);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBarBackground,
        border: Border(
          top: BorderSide(
            color: AppColors.border.withValues(alpha: 0.6),
            width: 1.0,
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) =>
            _handleDestinationSelected(context, index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Map',
            tooltip: 'Taxi Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
            tooltip: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
