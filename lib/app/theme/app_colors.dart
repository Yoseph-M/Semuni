import 'package:flutter/material.dart';

/// semuni centralized color system.
///
/// All colors used in the application are defined here.
/// Never hardcode color values inside widgets.
/// Always reference these constants.
abstract final class AppColors {
  // ---------------------------------------------------------------------------
  // Brand Colors
  // ---------------------------------------------------------------------------

  /// Primary semuni brand color. Used for buttons, active states, selected
  /// navigation items, important icons, and primary CTAs.
  static const Color primary = Color(0xFF1C5E40);

  /// Slightly lighter variant of primary for hover / pressed states.
  static const Color primaryLight = Color(0xFF2E7D55);

  /// Darker variant of primary for pressed states on dark surfaces.
  static const Color primaryDark = Color(0xFF134530);

  /// Very light tint of primary for subtle backgrounds on selected items.
  static const Color primaryTint = Color(0xFFE8F4EE);

  // ---------------------------------------------------------------------------
  // Background Colors
  // ---------------------------------------------------------------------------

  /// Primary application background. Dominant surface color throughout the app.
  static const Color background = Color(0xFFF7FCF8);

  /// Slightly warmer surface for cards on the main background.
  static const Color surface = Color(0xFFFFFFFF);

  /// Secondary surface, e.g. slightly tinted cards or grouped sections.
  static const Color surfaceVariant = Color(0xFFF0F7F3);

  // ---------------------------------------------------------------------------
  // Wallet / Balance Card Gradient
  // ---------------------------------------------------------------------------

  /// Start color for the wallet / balance card gradient.
  static const Color walletGradientStart = Color(0xFF1C5E40);

  /// End color for the wallet / balance card gradient.
  static const Color walletGradientEnd = Color(0xFF2E7D55);

  // ---------------------------------------------------------------------------
  // Text Colors
  // ---------------------------------------------------------------------------

  /// Primary text — used for headings and important content.
  static const Color textPrimary = Color(0xFF0D1F17);

  /// Secondary text — used for subtitles, labels, and supporting information.
  static const Color textSecondary = Color(0xFF4A6358);

  /// Disabled / hint text.
  static const Color textHint = Color(0xFF8FAF9E);

  /// Text on primary-colored surfaces (buttons, wallet card, etc.).
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Semantic Colors
  // ---------------------------------------------------------------------------

  /// Error / destructive actions.
  static const Color error = Color(0xFFBA1A1A);

  /// Light error surface.
  static const Color errorContainer = Color(0xFFFFDAD6);

  /// Success indicator.
  static const Color success = Color(0xFF2E7D32);

  /// Success light surface.
  static const Color successContainer = Color(0xFFE8F5E9);

  /// Warning indicator.
  static const Color warning = Color(0xFFF57F17);

  /// Warning light surface.
  static const Color warningContainer = Color(0xFFFFF8E1);

  // ---------------------------------------------------------------------------
  // Border / Divider Colors
  // ---------------------------------------------------------------------------

  /// Subtle border used on cards and input fields.
  static const Color border = Color(0xFFD6E8DC);

  /// Divider color used in lists and section separators.
  static const Color divider = Color(0xFFEAF3ED);

  // ---------------------------------------------------------------------------
  // Navigation Bar Colors
  // ---------------------------------------------------------------------------

  /// Navigation bar background.
  static const Color navBarBackground = Color(0xFFFFFFFF);

  /// Inactive navigation item color.
  static const Color navBarInactive = Color(0xFF8FAF9E);

  /// Active navigation item color — same as primary brand.
  static const Color navBarActive = Color(0xFF1C5E40);

  /// Navigation bar indicator / highlight background.
  static const Color navBarIndicator = Color(0xFFE8F4EE);

  // ---------------------------------------------------------------------------
  // Input Field Colors
  // ---------------------------------------------------------------------------

  /// Fill color for text input fields.
  static const Color inputFill = Color(0xFFF0F7F3);

  /// Border color for focused input fields.
  static const Color inputFocusBorder = Color(0xFF1C5E40);

  /// Border color for unfocused input fields.
  static const Color inputBorder = Color(0xFFD6E8DC);

  // ---------------------------------------------------------------------------
  // Shadow / Overlay
  // ---------------------------------------------------------------------------

  /// Subtle shadow color for cards and elevated surfaces.
  static const Color shadow = Color(0x1A1C5E40);

  /// Scrim / modal overlay.
  static const Color scrim = Color(0x661C5E40);
}
