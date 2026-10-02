import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/passenger_wallet_transaction.dart';
import '../../../models/top_up_intent.dart';
import '../../../repositories/passenger_wallet_repository.dart';
import '../../../repositories/auth_repository.dart';

/// Passenger wallet: the authoritative balance and ledger, plus top-ups.
///
/// A top-up is never a local balance increase. It is:
///
///   1. create an intent (`POST /wallet/top-up`) — no money moves
///   2. the passenger pays through the provider's checkout
///   3. confirm (`POST /wallet/top-up/:id/confirm`) — the backend verifies the
///      provider and credits the wallet exactly once
///   4. re-read the balance from the server
class PassengerWalletScreen extends StatefulWidget {
  const PassengerWalletScreen({
    super.key,
    required this.walletRepository,
    required this.authRepository,
  });

  final PassengerWalletRepository walletRepository;
  final AuthRepository authRepository;

  @override
  State<PassengerWalletScreen> createState() => _PassengerWalletScreenState();
}

class _PassengerWalletScreenState extends State<PassengerWalletScreen> {
  bool _isLoading = true;
  String? _error;
  List<PassengerWalletTransaction> _transactions = [];
  double? _balanceEtb;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait<Object>([
        widget.walletRepository.getBalance(),
        widget.walletRepository.getTransactionHistory(),
      ]);
      if (!mounted) return;
      setState(() {
        _balanceEtb = results[0] as double;
        _transactions = results[1] as List<PassengerWalletTransaction>;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is ApiException
              ? e.userMessage
              : 'Failed to load your wallet.';
          _isLoading = false;
        });
      }
    }
  }

  void _showTopUpDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppConstants.radiusXl),
        ),
      ),
      builder: (ctx) => _TopUpSheet(
        onConfirm: (amount) async {
          Navigator.of(ctx).pop(); // close sheet
          await _startTopUp(amount);
        },
      ),
    );
  }

  Future<void> _startTopUp(double amount) async {
    // One key per logical top-up; a retry of this same top-up reuses it, and
    // the backend then returns the same intent instead of creating another.
    final idempotencyKey = _newIdempotencyKey();

    try {
      final intent = await widget.walletRepository.initiateTopUp(
        amountEtb: amount,
        idempotencyKey: idempotencyKey,
      );
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _TopUpCheckoutDialog(intent: intent),
      );
      if (confirmed != true || !mounted) return;

      final confirmation = await widget.walletRepository.confirmTopUp(
        intent.intentId,
      );
      if (!mounted) return;

      await widget.authRepository.refreshPassengerProfile();
      await _afterCredit(confirmation);
    } on ApiException catch (error) {
      if (!mounted) return;
      _showSnack(error.userMessage, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showSnack('Failed to top up. Please try again.', isError: true);
    }
  }

  Future<void> _afterCredit(TopUpConfirmation confirmation) async {
    setState(() => _balanceEtb = confirmation.balanceEtb);
    await _loadWallet();
    if (!mounted) return;
    _showSnack(
      'Top Up Successful\nYour wallet balance is now '
      '${AppFormatters.formatCurrency(confirmation.balanceEtb)}.',
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  static String _newIdempotencyKey() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = Random().nextInt(0x7fffffff).toRadixString(36);
    return 'flutter-topup-$stamp-$entropy';
  }

  @override
  Widget build(BuildContext context) {
    final balance = _balanceEtb;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('My Wallet'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadWallet,
          color: AppColors.primary,
          child: ListView(
            padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
            children: [
              // Balance Card
              Container(
                padding: const EdgeInsets.all(AppConstants.spacingLg),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.walletGradientStart,
                      AppColors.walletGradientEnd,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 14,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Available Balance',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingSm),
                    Text(
                      balance == null
                          ? '—'
                          : AppFormatters.formatCurrency(balance),
                      style: AppTextStyles.displayMedium.copyWith(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppConstants.spacingLg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showTopUpDialog,
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'Top Up',
                          style: AppTextStyles.labelLarge.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppConstants.radiusMd,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppConstants.spacingXl),

              // Transactions Header
              Text(
                'Recent Transactions',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: AppConstants.spacingMd),

              // Transaction List
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppConstants.spacingXl),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (_error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingXl),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: AppColors.error,
                          size: 48,
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        Text(
                          _error!,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        OutlinedButton(
                          onPressed: _loadWallet,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_transactions.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacingXl),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_rounded,
                          color: AppColors.textHint.withValues(alpha: 0.5),
                          size: 64,
                        ),
                        const SizedBox(height: AppConstants.spacingMd),
                        Text(
                          'No transactions yet.',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._transactions.map((tx) => _TransactionTile(transaction: tx)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown after an intent exists: the passenger pays outside the app (when the
/// provider hosts checkout) and only then confirms, which makes the backend
/// verify and credit.
class _TopUpCheckoutDialog extends StatelessWidget {
  const _TopUpCheckoutDialog({required this.intent});

  final TopUpIntentView intent;

  @override
  Widget build(BuildContext context) {
    final url = intent.checkoutUrl;
    final hasCheckout = intent.requiresExternalCheckout;

    return AlertDialog(
      title: Text('Pay ${AppFormatters.formatCurrency(intent.amountEtb)}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hasCheckout
                ? 'Complete the payment through ${intent.provider} checkout, then come back and confirm. '
                      'Your wallet is credited only after Semuni verifies the payment.'
                : 'Provider ${intent.provider} will verify this payment when you confirm. '
                      'Your wallet is credited only after that verification.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          if (hasCheckout) ...[
            const SizedBox(height: AppConstants.spacingMd),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppConstants.spacingSm),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppConstants.radiusSm),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                url!,
                maxLines: 4,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: url));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Checkout link copied'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('Copy link'),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("I've paid — Confirm"),
        ),
      ],
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.transaction});

  final PassengerWalletTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final isCredit = transaction.isCredit;
    final color = isCredit ? AppColors.success : AppColors.error;
    final prefix = isCredit ? '+' : '-';
    final icon = isCredit
        ? Icons.arrow_downward_rounded
        : Icons.arrow_upward_rounded;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppConstants.spacingMd,
          vertical: AppConstants.spacingXs,
        ),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color, size: AppConstants.iconSm),
        ),
        title: Text(
          transaction.description,
          style: AppTextStyles.labelLarge.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          AppFormatters.formatDate(transaction.createdAt),
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        trailing: Text(
          '$prefix${AppFormatters.formatCurrency(transaction.amount)}',
          style: AppTextStyles.labelLarge.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet({required this.onConfirm});

  final ValueChanged<double> onConfirm;

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  final List<double> _presetAmounts = [50, 100, 200, 500];
  double? _selectedAmount;
  final TextEditingController _customAmountController = TextEditingController();

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  void _handlePresetSelected(double amount) {
    setState(() {
      _selectedAmount = amount;
      _customAmountController.clear();
    });
  }

  void _handleCustomAmountChanged(String value) {
    final amount = double.tryParse(value);
    if (amount != null && amount > 0) {
      setState(() {
        _selectedAmount = amount;
      });
    } else {
      setState(() {
        _selectedAmount = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: AppConstants.spacingLg,
        right: AppConstants.spacingLg,
        top: AppConstants.spacingLg,
        bottom: AppConstants.spacingLg + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Top Up Wallet',
                style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppConstants.spacingMd),
          Text(
            'Select Amount',
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Wrap(
            spacing: AppConstants.spacingSm,
            runSpacing: AppConstants.spacingSm,
            children: _presetAmounts.map((amount) {
              final isSelected =
                  _selectedAmount == amount &&
                  _customAmountController.text.isEmpty;
              return ChoiceChip(
                label: Text(AppFormatters.formatCurrency(amount)),
                selected: isSelected,
                onSelected: (_) => _handlePresetSelected(amount),
                selectedColor: AppColors.primaryTint,
                backgroundColor: Colors.white,
                labelStyle: AppTextStyles.labelMedium.copyWith(
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            'Or Enter Custom Amount',
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          TextField(
            controller: _customAmountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: _handleCustomAmountChanged,
            decoration: InputDecoration(
              hintText: 'e.g. 150',
              prefixText: 'ETB ',
              prefixStyle: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: AppColors.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                borderSide: const BorderSide(color: AppColors.inputBorder),
              ),
            ),
          ),
          const SizedBox(height: AppConstants.spacingXl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedAmount != null && _selectedAmount! > 0
                  ? () => widget.onConfirm(_selectedAmount!)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                ),
              ),
              child: Text(
                _selectedAmount != null && _selectedAmount! > 0
                    ? 'Continue (${AppFormatters.formatCurrency(_selectedAmount!)})'
                    : 'Continue',
                style: AppTextStyles.labelLarge.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
