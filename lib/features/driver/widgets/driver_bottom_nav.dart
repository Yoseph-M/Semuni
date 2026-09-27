import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../navigation/app_routes.dart';

/// Reusable bottom navigation bar for the SMUNI driver experience.
///
/// Contains exactly three destinations:
/// 0: Home ([AppRoutes.driverHome]) — Active/Selected
/// 1: Routes ([AppRoutes.driverRoutes])
/// 2: Settings ([AppRoutes.driverSettings])
class DriverBottomNav extends StatelessWidget {
  const DriverBottomNav({super.key, this.currentIndex = 0, this.onTap});

  /// Index of the currently active destination. Defaults to 0 (Home).
  final int currentIndex;

  /// Custom tap handler. If null, standard named route navigation is executed.
  final ValueChanged<int>? onTap;

  void _handleDestinationSelected(BuildContext context, int index) {
    if (onTap != null) {
      onTap!(index);
      return;
    }

    if (index == currentIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushReplacementNamed(AppRoutes.driverHome);
        break;
      case 1:
        Navigator.of(context).pushNamed(AppRoutes.driverRoutes);
        break;
      case 2:
        Navigator.of(context).pushNamed(AppRoutes.driverSettings);
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
        indicatorColor: AppColors.navBarIndicator,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
            tooltip: 'Driver Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon: Icon(Icons.alt_route_rounded),
            label: 'Routes',
            tooltip: 'My Routes',
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
