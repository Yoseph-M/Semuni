import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../models/driver_transaction.dart';
import '../../../repositories/driver_dashboard_repository.dart';
import '../widgets/driver_transaction_card.dart';

/// Screen to display the complete transaction history for a driver.
///
/// Features:
/// - Filtering by All, Earnings (credits), and Withdrawals (debits)
/// - Asynchronous data fetching
/// - Empty state and loading state handling
class DriverTransactionsScreen extends StatefulWidget {
  const DriverTransactionsScreen({super.key, required this.repository});

  final DriverDashboardRepository repository;

  @override
  State<DriverTransactionsScreen> createState() =>
      _DriverTransactionsScreenState();
}

class _DriverTransactionsScreenState extends State<DriverTransactionsScreen> {
  late Future<List<DriverTransaction>> _transactionsFuture;
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Earnings', 'Withdrawals'];

  @override
  void initState() {
    super.initState();
    // Use a larger limit for the main transactions screen.
    _transactionsFuture = widget.repository.getRecentTransactions(limit: 50);
  }

  void _onFilterChanged(String filter) {
    setState(() {
      _selectedFilter = filter;
    });
  }

  List<DriverTransaction> _filterTransactions(
    List<DriverTransaction> transactions,
  ) {
    if (_selectedFilter == 'Earnings') {
      return transactions.where((t) => t.isCredit).toList();
    } else if (_selectedFilter == 'Withdrawals') {
      return transactions.where((t) => !t.isCredit).toList();
    }
    return transactions;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Transactions'),
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 1,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Filter Tabs
            _buildFilterTabs(),

            const SizedBox(height: AppConstants.spacingSm),

            // Transactions List
            Expanded(
              child: FutureBuilder<List<DriverTransaction>>(
                future: _transactionsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppConstants.spacingXl),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 48,
                              color: AppColors.error,
                            ),
                            const SizedBox(height: AppConstants.spacingMd),
                            Text(
                              'Failed to load transactions',
                              style: AppTextStyles.titleMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppConstants.spacingSm),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _transactionsFuture = widget.repository
                                      .getRecentTransactions(limit: 50);
                                });
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  final allTransactions = snapshot.data ?? [];
                  final filteredTransactions = _filterTransactions(
                    allTransactions,
                  );

                  if (filteredTransactions.isEmpty) {
                    return _buildEmptyState();
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppConstants.screenHorizontalPadding,
                      vertical: AppConstants.spacingMd,
                    ),
                    itemCount: filteredTransactions.length,
                    separatorBuilder: (context, index) => const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.divider,
                      indent: 58, // Align with the text, skipping the icon
                    ),
                    itemBuilder: (context, index) {
                      return DriverTransactionCard(
                        transaction: filteredTransactions[index],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.screenHorizontalPadding,
        vertical: AppConstants.spacingSm,
      ),
      child: Row(
        children: _filters.map((filter) {
          final isSelected = _selectedFilter == filter;
          return Padding(
            padding: const EdgeInsets.only(right: AppConstants.spacingSm),
            child: ChoiceChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) {
                  _onFilterChanged(filter);
                }
              },
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              labelStyle: AppTextStyles.labelLarge.copyWith(
                color: isSelected
                    ? AppColors.textOnPrimary
                    : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              side: BorderSide(
                color: isSelected ? AppColors.primary : AppColors.border,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.spacingXl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(AppConstants.spacingLg),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: AppColors.textHint,
              ),
            ),
            const SizedBox(height: AppConstants.spacingLg),
            Text(
              'No transactions yet',
              style: AppTextStyles.titleLarge.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppConstants.spacingSm),
            Text(
              'Your driver transactions will appear here.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
