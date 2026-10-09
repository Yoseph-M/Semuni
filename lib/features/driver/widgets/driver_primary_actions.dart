import 'package:flutter/material.dart';

/// Dashboard financial shortcuts are intentionally hidden for drivers.
/// Dedicated transaction and withdrawal screens remain available through the
/// app's existing routes, but no buttons are rendered on the dashboard.
class DriverPrimaryActions extends StatelessWidget {
  const DriverPrimaryActions({
    super.key,
    this.onTransactionsTap,
    this.onWithdrawTap,
  });

  final VoidCallback? onTransactionsTap;
  final VoidCallback? onWithdrawTap;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
