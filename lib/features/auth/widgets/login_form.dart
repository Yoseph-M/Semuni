import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/user_role.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/auth_repository.dart';
import 'role_selector.dart';

/// Complete SMUNI login form supporting both [UserRole.passenger] and [UserRole.driver].
///
/// Handles input validation, password obscurity toggle, loading state,
/// error presentation, and delegating authentication to [AuthRepository].
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.authRepository,
    this.initialRole = UserRole.passenger,
  });

  final AuthRepository authRepository;
  final UserRole initialRole;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  late UserRole _selectedRole;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.initialRole;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onRoleChanged(UserRole newRole) {
    if (_selectedRole == newRole) return;
    setState(() {
      _selectedRole = newRole;
      _errorMessage = null; // Clear any active auth error when switching roles
    });
    // Clear validation error state if form was previously submitted
    _formKey.currentState?.reset();
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  void _onFieldChanged() {
    if (_errorMessage != null) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  Future<void> _handleLogin() async {
    // Dismiss soft keyboard
    FocusScope.of(context).unfocus();

    // Client-side validation check
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    try {
      final result = _selectedRole.isPassenger
          ? await widget.authRepository.loginPassenger(
              username: username,
              password: password,
            )
          : await widget.authRepository.loginDriver(
              username: username,
              password: password,
            );

      if (!mounted) return;

      if (result.isSuccess) {
        final destination = _selectedRole.isPassenger
            ? AppRoutes.passengerHome
            : AppRoutes.driverHome;

        Navigator.of(context).pushReplacementNamed(destination);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              result.errorMessage ??
              'Invalid username or password. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'An unexpected error occurred. Please try again.';
      });
    }
  }

  void _handleForgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Password recovery will be available in an upcoming update.',
          style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        ),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Role Selector Segmented Control
          RoleSelector(
            selectedRole: _selectedRole,
            onRoleChanged: _onRoleChanged,
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Role-specific hint/subtitle
          AnimatedSwitcher(
            duration: AppConstants.animFast,
            child: Align(
              key: ValueKey(_selectedRole),
              alignment: Alignment.centerLeft,
              child: Text(
                _selectedRole.isPassenger
                    ? 'Passenger Account'
                    : 'Driver Account',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),

          Text(
            _selectedRole.isPassenger
                ? 'Sign in to access your digital wallet, route discovery, and ride payments.'
                : 'Sign in to manage your assigned taxi routes and track today’s earnings.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Error banner (if authentication failed)
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm,
              ),
              decoration: BoxDecoration(
                color: AppColors.errorContainer.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: AppConstants.iconMd,
                  ),
                  const SizedBox(width: AppConstants.spacingSm),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
          ],

          // Username Field
          TextFormField(
            controller: _usernameController,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.text,
            enabled: !_isLoading,
            onChanged: (_) => _onFieldChanged(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'e.g. testpassenger',
              prefixIcon: const Icon(
                Icons.phone_outlined,
                size: AppConstants.iconMd,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your username';
              }
              return null;
            },
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Password Field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            enabled: !_isLoading,
            onChanged: (_) => _onFieldChanged(),
            onFieldSubmitted: (_) => _handleLogin(),
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: InputDecoration(
              labelText: 'Password',
              hintText: 'Enter your password',
              prefixIcon: const Icon(
                Icons.lock_outline_rounded,
                size: AppConstants.iconMd,
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: AppConstants.iconMd,
                  color: AppColors.textSecondary,
                ),
                tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                onPressed: _togglePasswordVisibility,
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: AppConstants.spacingXs),

          // Forgot Password Action
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading ? null : _handleForgotPassword,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSm,
                  vertical: AppConstants.spacingXs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot password?',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingLg),

          // Primary CTA Button (Login)
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.textOnPrimary,
                      ),
                    ),
                  )
                : const Text('Login'),
          ),
        ],
      ),
    );
  }
}
