import 'package:flutter/material.dart';

/// semuni centralized typography system.
///
/// All text styles are defined here and reference [AppColors].
/// Never define ad-hoc text styles inside widgets.
abstract final class AppTextStyles {
  // ---------------------------------------------------------------------------
  // Display — Very large, hero-level text (balance amounts, big headings)
  // ---------------------------------------------------------------------------

  static const TextStyle displayLarge = TextStyle(
    fontSize: 36.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    height: 1.1,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 28.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.15,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    height: 1.2,
  );

  // ---------------------------------------------------------------------------
  // Headline — Section headings and screen titles
  // ---------------------------------------------------------------------------

  static const TextStyle headlineLarge = TextStyle(
    fontSize: 22.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
    height: 1.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 18.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
    height: 1.3,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
    height: 1.35,
  );

  // ---------------------------------------------------------------------------
  // Title — Card titles, list item primaries
  // ---------------------------------------------------------------------------

  static const TextStyle titleLarge = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Body — General readable text
  // ---------------------------------------------------------------------------

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.25,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.4,
    height: 1.5,
  );

  // ---------------------------------------------------------------------------
  // Label — Buttons, navigation labels, chips, small caps
  // ---------------------------------------------------------------------------

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.4,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // Currency / Amount — Special styles for monetary values
  // ---------------------------------------------------------------------------

  /// Large balance display (wallet card, driver balance card).
  static const TextStyle amountDisplay = TextStyle(
    fontSize: 32.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.1,
  );

  /// Medium amount display (earnings, transaction amounts).
  static const TextStyle amountMedium = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.25,
    height: 1.2,
  );

  /// Small amount (list item prices, trip costs).
  static const TextStyle amountSmall = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.0,
    height: 1.3,
  );

  /// ETB currency prefix — smaller than the amount it precedes.
  static const TextStyle currencyPrefix = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.4,
  );
}
