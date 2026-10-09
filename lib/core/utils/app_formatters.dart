import '../constants/app_constants.dart';

/// Utility functions for formatting values in the semuni UI.
abstract final class AppFormatters {
  /// Formats an ETB currency amount for display.
  ///
  /// Example: `formatCurrency(1250.0)` → `'ETB 1,250.00'`
  static String formatCurrency(double amount) {
    // Format with thousands separator and 2 decimal places.
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0];
    final decPart = parts[1];

    // Insert commas every 3 digits from the right.
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(intPart[i]);
    }

    return '${AppConstants.currencyPrefix} $buffer.$decPart';
  }

  /// Formats a [DateTime] as a short date string.
  ///
  /// Example: `formatDate(DateTime(2024, 6, 15))` → `'Jun 15, 2024'`
  static String formatDate(DateTime date) {
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
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Formats a [DateTime] as a short time string (12-hour format).
  ///
  /// Example: `formatTime(DateTime(2024, 6, 15, 14, 30))` → `'2:30 PM'`
  static String formatTime(DateTime time) {
    final hour = time.hour == 0
        ? 12
        : time.hour > 12
        ? time.hour - 12
        : time.hour;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  /// Formats a [DateTime] as a combined date+time label.
  ///
  /// Example: `formatDateTime(...)` → `'Jun 15 · 2:30 PM'`
  static String formatDateTime(DateTime dateTime) {
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
    final month = months[dateTime.month - 1];
    final day = dateTime.day;
    return '$month $day · ${formatTime(dateTime)}';
  }

  /// Formats a trip's completion [DateTime] into a friendly relative string.
  ///
  /// Examples:
  /// - Today: `'Today, 8:42 AM'`
  /// - Yesterday: `'Yesterday, 5:20 PM'`
  /// - Other: `'Jun 15, 2:30 PM'`
  static String formatTripDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tripDay = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final difference = today.difference(tripDay).inDays;

    if (difference == 0) {
      return 'Today, ${formatTime(dateTime)}';
    } else if (difference == 1) {
      return 'Yesterday, ${formatTime(dateTime)}';
    } else {
      return '${formatDate(dateTime)}, ${formatTime(dateTime)}';
    }
  }

  /// Returns a greeting based on the current hour.
  ///
  /// - 00:00–11:59 → 'Good morning'
  /// - 12:00–16:59 → 'Good afternoon'
  /// - 17:00–23:59 → 'Good evening'
  static String timeBasedGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
