import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/app_formatters.dart';
import '../../../models/trip.dart';

class PassengerTripDetailScreen extends StatelessWidget {
  const PassengerTripDetailScreen({super.key, required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Trip Detail'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.screenHorizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppConstants.spacingMd),

              // Status & Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: trip.status == TripStatus.completed
                          ? AppColors.successContainer
                          : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(
                        AppConstants.radiusFull,
                      ),
                    ),
                    child: Text(
                      trip.status.name.toUpperCase(),
                      style: AppTextStyles.labelMedium.copyWith(
                        color: trip.status == TripStatus.completed
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    AppFormatters.formatTripDate(trip.completedAt),
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppConstants.spacingXl),

              // Journey Card
              _SectionTitle('Journey'),
              _SectionCard(
                children: [
                  _InfoRow(
                    icon: Icons.radio_button_on_rounded,
                    iconColor: AppColors.success,
                    label: 'From',
                    value: trip.fromLocation,
                  ),
                  const _Divider(),
                  _InfoRow(
                    icon: Icons.location_on_rounded,
                    iconColor: AppColors.error,
                    label: 'To',
                    value: trip.toLocation,
                  ),
                  if (trip.routeCode != null) ...[
                    const _Divider(),
                    _InfoRow(
                      icon: Icons.directions_bus_rounded,
                      iconColor: AppColors.textSecondary,
                      label: 'Route',
                      value: trip.routeCode!,
                    ),
                  ],
                ],
              ),

              const SizedBox(height: AppConstants.spacingLg),

              // Payment Card
              _SectionTitle('Payment'),
              _SectionCard(
                children: [
                  _InfoRow(
                    icon: Icons.check_circle_outline_rounded,
                    iconColor: AppColors.success,
                    label: 'Status',
                    value: 'Paid',
                    valueColor: AppColors.success,
                    valueBold: true,
                  ),
                  const _Divider(),
                  _InfoRow(
                    icon: Icons.payments_outlined,
                    iconColor: AppColors.primary,
                    label: 'Fare',
                    value: AppFormatters.formatCurrency(trip.amountPaid),
                    valueColor: AppColors.primary,
                    valueBold: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppConstants.spacingSm),
      child: Text(
        title,
        style: AppTextStyles.titleMedium.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.valueBold = false,
    this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool valueBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppConstants.spacingMd,
        vertical: AppConstants.spacingMd,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppConstants.iconMd, color: iconColor),
          const SizedBox(width: AppConstants.spacingMd),
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: valueBold ? FontWeight.w700 : FontWeight.w500,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 16, endIndent: 16);
  }
}
