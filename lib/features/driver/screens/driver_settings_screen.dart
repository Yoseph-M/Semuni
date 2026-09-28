import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/auth_repository.dart';
import '../widgets/driver_bottom_nav.dart';

/// Driver Settings Screen.
///
/// Provides access to driver account details, preferences, and logout functionality.
/// Fits into the 3-tab driver navigation structure.
class DriverSettingsScreen extends StatefulWidget {
  const DriverSettingsScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<DriverSettingsScreen> createState() => _DriverSettingsScreenState();
}

class _DriverSettingsScreenState extends State<DriverSettingsScreen> {
  bool _notificationsEnabled = true;

  Future<void> _handleLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Log out'),
          content: const Text(
            'Are you sure you want to sign out of your driver account?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                'Log out',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true && context.mounted) {
      await widget.authRepository.logout();
      if (context.mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.authRepository.currentDriver;

    // Safety check - if driver is null for some reason, provide fallbacks
    final name = driver?.name ?? 'Unknown Driver';
    final username = driver?.username ?? 'unknown';
    final phone = driver?.phone ?? 'No phone';
    final license = driver?.licenseNumber ?? 'N/A';
    final plate = driver?.vehiclePlate ?? 'N/A';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.screenHorizontalPadding,
                vertical: AppConstants.screenVerticalPadding,
              ),
              children: [
                // Account Section
                _buildSectionHeader('Account'),
                const SizedBox(height: AppConstants.spacingSm),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    side: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingLg),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: AppColors.primaryTint.withValues(
                            alpha: 0.3,
                          ),
                          child: Text(
                            initial,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppConstants.spacingLg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: AppTextStyles.titleLarge.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '@$username • Driver',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                phone,
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
                ),
                const SizedBox(height: AppConstants.spacingMd),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    side: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.badge_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text('License Number'),
                        trailing: Text(
                          license,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(
                          Icons.directions_car_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text('Vehicle Plate'),
                        trailing: Text(
                          plate,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppConstants.spacingXl),

                // Preferences Section
                _buildSectionHeader('Preferences'),
                const SizedBox(height: AppConstants.spacingSm),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    side: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Notifications'),
                        subtitle: const Text('Route and payment updates'),
                        secondary: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.primary,
                        ),
                        activeTrackColor: AppColors.primary,
                        value: _notificationsEnabled,
                        onChanged: (value) {
                          setState(() {
                            _notificationsEnabled = value;
                          });
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(
                          Icons.language_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('Language'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'English',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: AppConstants.spacingXs),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                        onTap: () {
                          // Placeholder for future language selection
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppConstants.spacingXl),

                // About Section
                _buildSectionHeader('About'),
                const SizedBox(height: AppConstants.spacingSm),
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                    side: BorderSide(
                      color: AppColors.border.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.primary,
                        ),
                        title: const Text('About SMUNI'),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textSecondary,
                        ),
                        onTap: () {
                          // Placeholder for about page
                        },
                      ),
                      const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: const Icon(
                          Icons.verified_outlined,
                          color: AppColors.primary,
                        ),
                        title: const Text('Version'),
                        trailing: Text(
                          '1.0.0',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppConstants.spacingXl),

                // Logout Action
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    key: const Key('driver_logout_button'),
                    onPressed: () => _handleLogout(context),
                    icon: const Icon(
                      Icons.logout_rounded,
                      color: AppColors.error,
                    ),
                    label: Text(
                      'Log out',
                      style: AppTextStyles.labelLarge.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppConstants.radiusMd,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: AppConstants.spacingXxl),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: const DriverBottomNav(currentIndex: 2),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: AppConstants.spacingSm),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
