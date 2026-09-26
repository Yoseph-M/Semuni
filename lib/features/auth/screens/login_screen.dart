import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../repositories/auth_repository.dart';
import '../widgets/login_form.dart';

/// Complete SMUNI login screen.
///
/// Features:
/// - Distinctive, intentional SMUNI branding header (ready to swap with SVG/PNG asset)
/// - Welcome heading and concise supporting copy
/// - Segmented role selector (Passenger default | Driver)
/// - Material 3 text inputs with validation, icons, and password toggle
/// - Keyboard-safe responsive layout for small, standard, and large screens
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.screenHorizontalPadding,
              vertical: AppConstants.screenVerticalPadding,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppConstants.spacingLg),

                  // -----------------------------------------------------------
                  // SMUNI Branding & Logo Placeholder
                  // -----------------------------------------------------------
                  _buildBrandingHeader(),
                  const SizedBox(height: AppConstants.spacingXl),

                  // -----------------------------------------------------------
                  // Welcome Heading
                  // -----------------------------------------------------------
                  Text(
                    'Welcome to SMUNI',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXs),
                  Text(
                    'Sign in to access your transportation and digital payment services.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingXl),

                  // -----------------------------------------------------------
                  // Login Form (Role selector, inputs, CTA)
                  // -----------------------------------------------------------
                  LoginForm(authRepository: authRepository),

                  const SizedBox(height: AppConstants.spacingXl),

                  // -----------------------------------------------------------
                  // Footer branding tag
                  // -----------------------------------------------------------
                  Center(
                    child: Text(
                      'SMUNI • Urban Mobility & Digital Payments',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppConstants.spacingMd),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Clean, intentional SMUNI logo mark placeholder.
  ///
  /// Can be seamlessly swapped with an `SvgPicture.asset` or `Image.asset`
  /// once production logo assets are available.
  Widget _buildBrandingHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.local_taxi_rounded,
              size: 26,
              color: AppColors.textOnPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppConstants.spacingSm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SMUNI',
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              'Simple · Mobile · Urban',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
