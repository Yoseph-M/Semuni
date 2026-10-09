import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/driver_withdrawal.dart';
import '../../../repositories/auth_repository.dart';
import '../../../repositories/driver_dashboard_repository.dart';

/// Withdrawal method option.
enum _WithdrawMethod { telebirr, cbe }

extension _WithdrawMethodX on _WithdrawMethod {
  String get label {
    return switch (this) {
      _WithdrawMethod.telebirr => 'Telebirr',
      _WithdrawMethod.cbe => 'Commercial Bank of Ethiopia',
    };
  }

  IconData get icon {
    return switch (this) {
      _WithdrawMethod.telebirr => Icons.phone_android_rounded,
      _WithdrawMethod.cbe => Icons.account_balance_rounded,
    };
  }

  /// The destination the backend records; there is no free-text "method".
  WithdrawalDestinationType get destinationType => switch (this) {
    _WithdrawMethod.telebirr => WithdrawalDestinationType.mobileMoney,
    _WithdrawMethod.cbe => WithdrawalDestinationType.bank,
  };

  String get destinationLabel => switch (this) {
    _WithdrawMethod.telebirr => 'Telebirr',
    _WithdrawMethod.cbe => 'Commercial Bank of Ethiopia',
  };
}

/// Three-phase driver withdrawal screen.
///
/// Phase 1 — Form: enter amount and destination, validate against the balance.
/// Phase 2 — Confirm: review, then submit to the backend.
/// Phase 3 — Submitted: the request is PENDING and settles asynchronously.
///
/// The destination is explicit (bank account or mobile money) and each submit
/// carries one idempotency key, so a retry cannot create a second withdrawal.
/// The balance shown is the server's; a withdrawal never edits it locally.
class DriverWithdrawScreen extends StatefulWidget {
  const DriverWithdrawScreen({
    super.key,
    required this.authRepository,
    this.dashboardRepository,
  });

  final AuthRepository authRepository;
  final DriverDashboardRepository? dashboardRepository;

  @override
  State<DriverWithdrawScreen> createState() => _DriverWithdrawScreenState();
}

enum _WithdrawPhase { form, confirm, success }

class _DriverWithdrawScreenState extends State<DriverWithdrawScreen> {
  late final DriverDashboardRepository _repo;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();
  final _accountController = TextEditingController();

  _WithdrawMethod _selectedMethod = _WithdrawMethod.telebirr;
  _WithdrawPhase _phase = _WithdrawPhase.form;
  bool _isSubmitting = false;

  /// Parsed amount from the text field — null until confirmed valid.
  double? _confirmedAmount;

  /// One key per logical withdrawal request, generated when the driver moves to
  /// the confirmation step and reused for retries of that same request.
  String? _idempotencyKey;

  /// The backend's answer, shown on the success phase.
  DriverWithdrawal? _submitted;

  @override
  void initState() {
    super.initState();
    _repo = widget.dashboardRepository ?? DriverDashboardRepository();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _amountFocus.dispose();
    _accountController.dispose();
    super.dispose();
  }

  double get _availableBalance =>
      widget.authRepository.currentDriver?.accountBalance ?? 0.0;

  String? _validateAmount(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Please enter an amount.';

    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid number.';
    if (parsed <= 0) return 'Amount must be greater than zero.';
    if (parsed > _availableBalance) {
      return 'Insufficient balance. '
          'Available: ${AppFormatters.formatCurrency(_availableBalance)}';
    }
    return null;
  }

  /// Bank transfers need a real account number; mobile money uses the phone
  /// number on the driver's profile.
  String? _validateAccount(String? value) {
    if (_selectedMethod != _WithdrawMethod.cbe) return null;
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Enter the destination account number.';
    if (trimmed.replaceAll(RegExp(r'\D'), '').length < 8) {
      return 'Enter a valid account number.';
    }
    return null;
  }

  void _onContinue() {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final parsed = double.tryParse(_amountController.text.trim())!;
    setState(() {
      _confirmedAmount = parsed;
      // A new logical request: a fresh key, reused for every retry of it.
      _idempotencyKey = _newIdempotencyKey();
      _phase = _WithdrawPhase.confirm;
    });
  }

  static String _newIdempotencyKey() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random().nextInt(0x7fffffff).toRadixString(36);
    return 'flutter-withdraw-$stamp-$entropy';
  }

  Future<void> _onConfirm() async {
    final driver = widget.authRepository.currentDriver;
    final key = _idempotencyKey;
    if (driver == null || _confirmedAmount == null || key == null) return;

    setState(() => _isSubmitting = true);

    try {
      final withdrawal = await _repo.requestWithdrawal(
        amountEtb: _confirmedAmount!,
        destinationType: _selectedMethod.destinationType,
        destination: _selectedMethod.destinationLabel,
        destinationAccount: _selectedMethod == _WithdrawMethod.cbe
            ? _accountController.text.trim()
            : driver.phone,
        idempotencyKey: key,
      );

      // The wallet only changes when the backend says it did; re-read it.
      await widget.authRepository.refreshDriverProfile();

      if (mounted) {
        setState(() {
          _submitted = withdrawal;
          _phase = _WithdrawPhase.success;
          _isSubmitting = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.userMessage),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Withdrawal failed. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _onBackFromConfirm() {
    setState(() => _phase = _WithdrawPhase.form);
  }

  void _onDone() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase == _WithdrawPhase.form || _phase == _WithdrawPhase.success,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _WithdrawPhase.confirm) {
          setState(() => _phase = _WithdrawPhase.form);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('Withdraw'),
          backgroundColor: AppColors.background,
          elevation: 0,
          centerTitle: true,
          scrolledUnderElevation: 1,
          // Hide the back button on success phase.
          automaticallyImplyLeading: _phase != _WithdrawPhase.success,
          leading: _phase == _WithdrawPhase.confirm
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  onPressed: _onBackFromConfirm,
                )
              : null,
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: switch (_phase) {
                _WithdrawPhase.form => _buildForm(),
                _WithdrawPhase.confirm => _buildConfirmation(),
                _WithdrawPhase.success => _buildSuccess(),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ─── Phase 1: Form ────────────────────────────────────────────────────────

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.screenVerticalPadding,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppConstants.spacingMd),

            // Available Balance tile
            _BalanceTile(balance: _availableBalance),
            const SizedBox(height: AppConstants.spacingXl),

            // Amount label
            Text(
              'Withdrawal Amount',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),

            // Amount input
            TextFormField(
              key: const Key('withdraw_amount_field'),
              controller: _amountController,
              focusNode: _amountFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              textInputAction: TextInputAction.done,
              validator: _validateAmount,
              style: AppTextStyles.headlineMedium.copyWith(
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                prefixText: 'ETB  ',
                prefixStyle: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                hintText: '0.00',
                hintStyle: AppTextStyles.headlineMedium.copyWith(
                  color: AppColors.textHint,
                ),
                filled: true,
                fillColor: AppColors.inputFill,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingMd,
                  vertical: AppConstants.spacingMd,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(color: AppColors.inputBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(color: AppColors.inputBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(
                    color: AppColors.inputFocusBorder,
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(
                    color: AppColors.error,
                    width: 1.5,
                  ),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  borderSide: const BorderSide(
                    color: AppColors.error,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppConstants.spacingXl),

            // Withdrawal Method label
            Text(
              'Withdrawal Method',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),

            // Method selector
            _MethodSelector(
              selectedMethod: _selectedMethod,
              onMethodChanged: (m) => setState(() => _selectedMethod = m),
            ),

            // Destination account (bank transfers only)
            if (_selectedMethod == _WithdrawMethod.cbe) ...[
              const SizedBox(height: AppConstants.spacingXl),
              Text(
                'Destination Account Number',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppConstants.spacingSm),
              TextFormField(
                key: const Key('withdraw_account_field'),
                controller: _accountController,
                keyboardType: TextInputType.number,
                validator: _validateAccount,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. 1000123456789',
                  filled: true,
                  fillColor: AppColors.inputFill,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppConstants.spacingMd,
                    vertical: AppConstants.spacingMd,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                    borderSide: const BorderSide(color: AppColors.inputBorder),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppConstants.spacingXxl),

            // Continue button
            SizedBox(
              height: AppConstants.minTouchTarget + 4,
              child: ElevatedButton(
                key: const Key('withdraw_continue_btn'),
                onPressed: _onContinue,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusFull,
                    ),
                  ),
                ),
                child: const Text('Continue'),
              ),
            ),
            const SizedBox(height: AppConstants.spacingMd),
          ],
        ),
      ),
    );
  }

  // ─── Phase 2: Confirmation ────────────────────────────────────────────────

  Widget _buildConfirmation() {
    final amount = _confirmedAmount!;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.screenVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppConstants.spacingMd),

          Text(
            'Review your withdrawal',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXs),
          Text(
            'Please confirm the details below before proceeding.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          // Summary card
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _SummaryRow(
                  label: 'Available Balance',
                  value: AppFormatters.formatCurrency(_availableBalance),
                  isFirst: true,
                ),
                const Divider(
                  height: 1,
                  color: AppColors.divider,
                  indent: 16,
                  endIndent: 16,
                ),
                _SummaryRow(
                  label: 'Withdrawal Amount',
                  value: AppFormatters.formatCurrency(amount),
                  valueStyle: AppTextStyles.titleLarge.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Divider(
                  height: 1,
                  color: AppColors.divider,
                  indent: 16,
                  endIndent: 16,
                ),
                _SummaryRow(
                  label: 'Destination',
                  value: _selectedMethod.destinationLabel,
                  trailing: Icon(
                    _selectedMethod.icon,
                    size: AppConstants.iconMd,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (_selectedMethod == _WithdrawMethod.cbe)
                  _SummaryRow(
                    label: 'Account',
                    value: _maskAccount(_accountController.text.trim()),
                  ),
                _SummaryRow(
                  label: 'Status',
                  value: 'Pending review',
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Confirm button
          SizedBox(
            height: AppConstants.minTouchTarget + 4,
            child: ElevatedButton(
              key: const Key('withdraw_confirm_btn'),
              onPressed: _isSubmitting ? null : _onConfirm,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.textOnPrimary,
                      ),
                    )
                  : const Text('Confirm Withdrawal'),
            ),
          ),
          const SizedBox(height: AppConstants.spacingMd),

          // Cancel/back link
          Center(
            child: TextButton(
              onPressed: _isSubmitting ? null : _onBackFromConfirm,
              child: Text(
                'Go back and edit',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Phase 3: Success ─────────────────────────────────────────────────────

  static String _maskAccount(String account) {
    if (account.length <= 4) return account;
    return '•••• ${account.substring(account.length - 4)}';
  }

  Widget _buildSuccess() {
    final amount = _confirmedAmount!;
    final submitted = _submitted;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.screenVerticalPadding,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Success icon
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: AppColors.successContainer,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 52,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),

          Text(
            'Withdrawal Submitted',
            style: AppTextStyles.headlineMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          if (submitted != null) ...[
            const SizedBox(height: AppConstants.spacingXs),
            Text(
              'Status: ${submitted.status}',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppConstants.spacingSm),

          Text(
            AppFormatters.formatCurrency(amount),
            style: AppTextStyles.displayMedium.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingMd),

          Text(
            'Your withdrawal request has been submitted to '
            '${_selectedMethod.destinationLabel}. '
            'It is pending and will be settled by semuni; funds are typically '
            'processed within 1–3 business days.',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppConstants.spacingXxl),

          // Done button
          SizedBox(
            height: AppConstants.minTouchTarget + 4,
            child: ElevatedButton(
              key: const Key('withdraw_done_btn'),
              onPressed: _onDone,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusFull),
                ),
              ),
              child: const Text('Back to Home'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Private helper widgets ──────────────────────────────────────────────────

class _BalanceTile extends StatelessWidget {
  const _BalanceTile({required this.balance});
  final double balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppConstants.spacingMd),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: AppColors.primary,
            size: AppConstants.iconLg,
          ),
          const SizedBox(width: AppConstants.spacingMd),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Available Balance',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                AppFormatters.formatCurrency(balance),
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MethodSelector extends StatelessWidget {
  const _MethodSelector({
    required this.selectedMethod,
    required this.onMethodChanged,
  });

  final _WithdrawMethod selectedMethod;
  final ValueChanged<_WithdrawMethod> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _WithdrawMethod.values.map((method) {
        final isSelected = selectedMethod == method;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
          child: InkWell(
            onTap: () => onMethodChanged(method),
            borderRadius: BorderRadius.circular(AppConstants.radiusMd),
            child: AnimatedContainer(
              duration: AppConstants.animFast,
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacingMd,
                vertical: AppConstants.spacingSm + 2,
              ),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryTint : AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.border,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    method.icon,
                    size: AppConstants.iconLg,
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: AppConstants.spacingMd),
                  Expanded(
                    child: Text(
                      method.label,
                      style: AppTextStyles.titleMedium.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.primary,
                      size: AppConstants.iconMd,
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueStyle,
    this.trailing,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final Widget? trailing;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacingMd,
        right: AppConstants.spacingMd,
        top: isFirst ? AppConstants.spacingMd : AppConstants.spacingSm + 2,
        bottom: isLast ? AppConstants.spacingMd : AppConstants.spacingSm + 2,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (trailing != null) ...[
                trailing!,
                const SizedBox(width: AppConstants.spacingXs),
              ],
              Text(
                value,
                style:
                    valueStyle ??
                    AppTextStyles.titleMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
