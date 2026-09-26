/// SMUNI application-level constants.
///
/// UI spacing, sizing, and animation values used across the app.
/// Reference these instead of hardcoding magic numbers in widgets.
abstract final class AppConstants {
  // ---------------------------------------------------------------------------
  // Spacing
  // ---------------------------------------------------------------------------

  /// 4dp — micro gap
  static const double spacingXxs = 4.0;

  /// 8dp — small gap between tight elements
  static const double spacingXs = 8.0;

  /// 12dp — compact gap
  static const double spacingSm = 12.0;

  /// 16dp — standard gap between related elements
  static const double spacingMd = 16.0;

  /// 20dp — medium gap between sections
  static const double spacingLg = 20.0;

  /// 24dp — large gap between unrelated sections
  static const double spacingXl = 24.0;

  /// 32dp — section separator
  static const double spacingXxl = 32.0;

  /// 40dp — screen-level breathing room
  static const double spacingXxxl = 40.0;

  // ---------------------------------------------------------------------------
  // Screen Padding
  // ---------------------------------------------------------------------------

  /// Standard horizontal padding for screen-level content.
  static const double screenHorizontalPadding = 20.0;

  /// Standard vertical padding for screen-level content.
  static const double screenVerticalPadding = 16.0;

  // ---------------------------------------------------------------------------
  // Border Radius
  // ---------------------------------------------------------------------------

  /// 6dp — tight radius for small chips/badges
  static const double radiusSm = 6.0;

  /// 12dp — standard button and input radius
  static const double radiusMd = 12.0;

  /// 16dp — card radius
  static const double radiusLg = 16.0;

  /// 20dp — large card / bottom sheet radius
  static const double radiusXl = 20.0;

  /// 100dp — fully rounded (pill shape)
  static const double radiusFull = 100.0;

  // ---------------------------------------------------------------------------
  // Icon Sizes
  // ---------------------------------------------------------------------------

  /// 16dp — small inline icon
  static const double iconSm = 16.0;

  /// 20dp — standard inline icon
  static const double iconMd = 20.0;

  /// 24dp — standard icon button icon
  static const double iconLg = 24.0;

  /// 32dp — featured / prominent icon
  static const double iconXl = 32.0;

  /// 40dp — large feature icon
  static const double iconXxl = 40.0;

  // ---------------------------------------------------------------------------
  // Touch Targets
  // ---------------------------------------------------------------------------

  /// Minimum accessible touch target size (48dp per Material guidelines).
  static const double minTouchTarget = 48.0;

  // ---------------------------------------------------------------------------
  // Animation Durations
  // ---------------------------------------------------------------------------

  /// 150ms — micro interaction (hover, tap feedback)
  static const Duration animFast = Duration(milliseconds: 150);

  /// 250ms — standard transition
  static const Duration animNormal = Duration(milliseconds: 250);

  /// 400ms — emphasized transition
  static const Duration animSlow = Duration(milliseconds: 400);

  // ---------------------------------------------------------------------------
  // Elevation / Shadow
  // ---------------------------------------------------------------------------

  /// Offset used for card drop shadows.
  static const double cardShadowBlurRadius = 16.0;
  static const double cardShadowSpreadRadius = 0.0;

  // ---------------------------------------------------------------------------
  // Misc
  // ---------------------------------------------------------------------------

  /// Standard divider thickness.
  static const double dividerThickness = 1.0;

  /// The ISO 4217 currency code for Ethiopia.
  static const String currencyCode = 'ETB';

  /// Display prefix for Ethiopian Birr amounts.
  static const String currencyPrefix = 'ETB';
}
