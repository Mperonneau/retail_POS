class AppConstants {
  AppConstants._();

  // --- Responsive Breakpoints ---
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  // --- Spacing (8px grid) ---
  static const double spacing4 = 4;
  static const double spacing6 = 6;
  static const double spacing8 = 8;
  static const double spacing10 = 10;
  static const double spacing12 = 12;
  static const double spacing16 = 16;
  static const double spacing20 = 20;
  static const double spacing24 = 24;
  static const double spacing32 = 32;
  static const double spacing48 = 48;

  // --- Border Radius ---
  static const double radiusCard = 12;
  static const double radiusButton = 8;
  static const double radiusInput = 6;
  static const double radiusBadge = 20;

  // --- Touch Targets ---
  static const double minTouchTarget = 44;
  static const double buttonHeight = 48;
  /// Dense buttons (e.g. card footers) — shorter with tighter insets.
  static const double buttonHeightCompact = 40;
  /// Bill footer / tight toolbars — minimal vertical footprint.
  static const double buttonHeightDense = 34;

  // --- Sidebar ---
  static const double sidebarWidth = 240;
  static const double railWidth = 72;

  // --- Retail split-view detail (quotes + order history, desktop only) ---
  /// Min/max width for the right-hand quote / order detail panel.
  static const double retailDetailSidePanelMin = 480;
  static const double retailDetailSidePanelMax = 560;

  /// Scales slightly with [viewportWidth] (e.g. full scaffold width), clamped.
  static double retailDetailSidePanelWidth(double viewportWidth) =>
      (viewportWidth * 0.38)
          .clamp(retailDetailSidePanelMin, retailDetailSidePanelMax);

  // --- Retail inventory — wide right drawer (wider than quote/order panels) ---
  static const double retailInventoryDetailPanelMin = 640;
  static const double retailInventoryDetailPanelMax = 900;

  /// Fraction of viewport; clamped between [retailInventoryDetailPanelMin] and max.
  static double retailInventoryDetailPanelWidth(double viewportWidth) =>
      (viewportWidth * 0.50).clamp(
        retailInventoryDetailPanelMin,
        retailInventoryDetailPanelMax,
      );

  // --- Animation Durations ---
  static const Duration animFast = Duration(milliseconds: 150);
  static const Duration animNormal = Duration(milliseconds: 250);
  static const Duration animSlow = Duration(milliseconds: 350);

  // --- Splash ---
  static const Duration splashDuration = Duration(milliseconds: 1500);
}
