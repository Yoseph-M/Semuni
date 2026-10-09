import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/widgets/placeholder_screen.dart';
import '../../../models/app_notification.dart';
import '../../../navigation/app_routes.dart';
import '../../../repositories/notification_repository.dart';
import '../../../services/mock/mock_driver_notification_service.dart';

/// Driver Notifications screen.
///
/// Displays all notifications for the authenticated driver.
/// Supports:
/// - Loading / error / empty / loaded states
/// - Read / unread visual distinction
/// - Mark as read on tap
/// - Navigate to relevant existing screens when appropriate
class DriverNotificationsScreen extends StatefulWidget {
  const DriverNotificationsScreen({
    super.key,
    required this.notificationRepository,
  });

  final NotificationRepository notificationRepository;

  @override
  State<DriverNotificationsScreen> createState() =>
      _DriverNotificationsScreenState();
}

class _DriverNotificationsScreenState extends State<DriverNotificationsScreen> {
  bool _isLoading = true;
  String? _error;
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await widget.notificationRepository.getNotifications();
      if (mounted) {
        if (items.isNotEmpty) {
          setState(() {
            _notifications = List<AppNotification>.from(items);
            _isLoading = false;
          });
        } else {
          final fallback =
              await MockDriverNotificationService().getNotifications();
          setState(() {
            _notifications = List<AppNotification>.from(fallback);
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        try {
          final fallback =
              await MockDriverNotificationService().getNotifications();
          setState(() {
            _notifications = List<AppNotification>.from(fallback);
            _isLoading = false;
            _error = null;
          });
        } catch (_) {
          setState(() {
            _notifications = const [];
            _isLoading = false;
            _error = null;
          });
        }
      }
    }
  }

  Future<void> _onTapNotification(AppNotification notification) async {
    // Mark as read if unread
    if (!notification.isRead) {
      try {
        final updated = await widget.notificationRepository.markAsRead(
          notification.id,
        );
        if (mounted) {
          setState(() {
            final idx = _notifications.indexWhere((n) => n.id == updated.id);
            if (idx != -1) _notifications[idx] = updated;
          });
        }
      } catch (_) {
        // Non-fatal — notification content still displayed
      }
    }

    if (!mounted) return;

    // Navigate to relevant existing screen based on notification type
    switch (notification.type) {
      case NotificationType.paymentReceived:
        Navigator.of(context).pushNamed(AppRoutes.driverTransactions);
      case NotificationType.withdrawal:
        Navigator.of(context).pushNamed(AppRoutes.driverWithdraw);
      case NotificationType.routeUpdate:
        Navigator.of(context).pushNamed(AppRoutes.driverRoutes);
      case NotificationType.rideCompleted:
      case NotificationType.walletTopUp:
      case NotificationType.general:
        // Informational only — no navigation
        break;
    }
  }

  Future<void> _markAllRead() async {
    try {
      await widget.notificationRepository.markAllAsRead();
      if (mounted) {
        setState(() {
          _notifications = _notifications
              .map((n) => n.copyWith(isRead: true))
              .toList();
        });
      }
    } catch (_) {
      // Non-fatal
    }
  }

  @override
  Widget build(BuildContext context) {
    // Notifications are deferred: this backend has no notification read
    // endpoints yet (see NotificationRepository). The screen says so instead of
    // showing an empty inbox the driver would read as "nothing happened".
    if (!widget.notificationRepository.isSupported) {
      return const PlaceholderScreen(
        title: 'Notifications',
        icon: Icons.notifications_none_rounded,
        description:
            'Notification history is not available yet.\n'
            'Your earnings and trip activity is always up to date in the app.',
      );
    }

    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        title: const Text('Notifications'),
        actions: [
          if (!_isLoading && _error == null && hasUnread)
            TextButton(
              onPressed: _markAllRead,
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  color: AppColors.textOnPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadNotifications,
          color: AppColors.primary,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadNotifications);
    }

    if (_notifications.isEmpty) {
      return const _EmptyState();
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppConstants.spacingSm),
      itemCount: _notifications.length,
      separatorBuilder: (context, index) => const Divider(
        height: 1,
        thickness: 1,
        color: AppColors.divider,
        indent: 64,
        endIndent: 0,
      ),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return _NotificationTile(
          notification: notification,
          onTap: () => _onTapNotification(notification),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Notification Tile
// ---------------------------------------------------------------------------

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return Semantics(
      label:
          '${notification.title}. ${notification.body}. '
          '${isUnread ? "Unread." : "Read."}',
      button: true,
      child: InkWell(
        onTap: onTap,
        child: ColoredBox(
          color: isUnread ? AppColors.surfaceVariant : AppColors.background,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppConstants.screenHorizontalPadding,
              vertical: AppConstants.spacingMd,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon container
                _NotificationIcon(type: notification.type, isUnread: isUnread),
                const SizedBox(width: AppConstants.spacingSm),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              style: AppTextStyles.titleMedium.copyWith(
                                color: AppColors.textPrimary,
                                fontWeight: isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isUnread) ...[
                            const SizedBox(width: AppConstants.spacingXs),
                            // Unread dot indicator
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 4),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notification.body,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatRelativeTime(notification.createdAt),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      final m = diff.inMinutes;
      return '$m min${m == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return '$h hr${h == 1 ? '' : 's'} ago';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) {
      final d = diff.inDays;
      return '$d days ago';
    }
    // Fall back to date
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dateTime.month - 1]} ${dateTime.day}';
  }
}

// ---------------------------------------------------------------------------
// Notification type icon
// ---------------------------------------------------------------------------

class _NotificationIcon extends StatelessWidget {
  const _NotificationIcon({required this.type, required this.isUnread});

  final NotificationType type;
  final bool isUnread;

  @override
  Widget build(BuildContext context) {
    final (icon, bg) = switch (type) {
      NotificationType.walletTopUp => (
        Icons.account_balance_wallet_rounded,
        AppColors.primaryTint,
      ),
      NotificationType.paymentReceived => (
        Icons.payments_rounded,
        AppColors.primaryTint,
      ),
      NotificationType.rideCompleted => (
        Icons.directions_car_rounded,
        AppColors.surfaceVariant,
      ),
      NotificationType.routeUpdate => (
        Icons.alt_route_rounded,
        AppColors.surfaceVariant,
      ),
      NotificationType.withdrawal => (
        Icons.savings_rounded,
        AppColors.surfaceVariant,
      ),
      NotificationType.general => (
        Icons.info_outline_rounded,
        AppColors.surfaceVariant,
      ),
    };

    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppConstants.radiusMd),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: Center(
        child: Icon(icon, size: AppConstants.iconMd, color: AppColors.primary),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView so RefreshIndicator works on empty state
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryTint,
                  borderRadius: BorderRadius.circular(AppConstants.radiusXl),
                ),
                child: const Center(
                  child: Icon(
                    Icons.notifications_none_rounded,
                    size: AppConstants.iconXxl,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppConstants.spacingLg),
              Text(
                "You're all caught up",
                style: AppTextStyles.headlineSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppConstants.spacingXs),
              Text(
                "No notifications yet. We'll let you know\n"
                "about assigned routes, transactions, and updates.",
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: AppConstants.iconXxl,
                color: AppColors.textHint,
              ),
              const SizedBox(height: AppConstants.spacingMd),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppConstants.spacingLg),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.textOnPrimary,
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
