import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/driver_transaction.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/driver_dashboard_repository.dart';

import 'driver_transaction_card.dart';

/// Recent Transactions section for the driver dashboard.
///
/// Features:
/// - Section header with "Recent Transactions" title and "View all" action
/// - Retrieves data asynchronously via [DriverDashboardRepository]
/// - Compact, clean list items showing description, amount (+ / -), and date
/// - Gracefully handles loading and empty states
///
/// Uses StatefulWidget to cache the future in [initState], preventing
/// FutureBuilder from rebuilding on every parent setState call.
class DriverRecentTransactionsSection extends StatefulWidget {
  const DriverRecentTransactionsSection({
    super.key,
    required this.repository,
    this.onViewAllTap,
    this.refreshToken = 0,
  });

  final DriverDashboardRepository repository;
  final VoidCallback? onViewAllTap;

  /// Changes when the parent wants fresh transaction values without replacing
  /// this card's mounted layout.
  final int refreshToken;

  @override
  State<DriverRecentTransactionsSection> createState() =>
      _DriverRecentTransactionsSectionState();
}

class _DriverRecentTransactionsSectionState
    extends State<DriverRecentTransactionsSection> {
  late Future<List<DriverTransaction>> _transactionsFuture;
  List<DriverTransaction>? _cachedTransactions;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = widget.repository.getRecentTransactions(limit: 4);
  }

  @override
  void didUpdateWidget(covariant DriverRecentTransactionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.refreshToken != widget.refreshToken) {
      _transactionsFuture = widget.repository.getRecentTransactions(limit: 4);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'Recent Transactions',
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed:
                  widget.onViewAllTap ??
                  () {
                    Navigator.of(context)
                        .pushNamed(AppRoutes.driverTransactions);
                  },
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppConstants.spacingSm,
                  vertical: AppConstants.spacingXs,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'View all',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: AppConstants.iconSm,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: AppConstants.spacingSm),

        // Transactions List with Async State Handling
        FutureBuilder<List<DriverTransaction>>(
          future: _transactionsFuture,
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _cachedTransactions = snapshot.data;
            }
            final transactions = _cachedTransactions ?? snapshot.data;

            if (transactions == null &&
                snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: AppConstants.spacingXl),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              );
            }

            final list = transactions ?? [];

            if (list.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppConstants.spacingXl),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppConstants.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: AppConstants.iconXl,
                        color: AppColors.textHint,
                      ),
                      const SizedBox(height: AppConstants.spacingSm),
                      Text(
                        'No transactions yet',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
                border: Border.all(color: AppColors.border, width: 1.0),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: list.length,
                separatorBuilder: (context, index) => const Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.divider,
                  indent: 68,
                  endIndent: AppConstants.spacingMd,
                ),
                itemBuilder: (context, index) {
                  return DriverTransactionCard(
                    transaction: list[index],
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
