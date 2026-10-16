import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // --- Light Theme Palette ---
  // Mid-range blue — distinctive for titles, links, and interactive elements.
  // sidebarBackground keeps the original dark navy separately.
  static const Color primaryBlue = Color(0xFF1A5AA8);
  static const Color amber = Color(0xFFF5A623);
  static const Color warmOffWhite = Color(0xFFF8F6F2);
  static const Color white = Color(0xFFFFFFFF);
  static const Color nearBlack = Color(0xFF1A1A2E);
  static const Color darkGray = Color(0xFF4A4A6A);
  static const Color deepGreen = Color(0xFF2E7D32);
  static const Color boldRed = Color(0xFFC62828);
  static const Color lightBlue = Color(0xFFE8F0F8);

  // --- Dark Theme Palette ---
  static const Color darkBackground = Color(0xFF0F1923);
  static const Color darkSurface = Color(0xFF1A2740);
  static const Color skyBlue = Color(0xFF4A90D9);
  static const Color warmWhite = Color(0xFFE8E8F0);
  static const Color coolGray = Color(0xFF9A9AB0);
  static const Color mediumGreen = Color(0xFF4CAF50);
  static const Color coralRed = Color(0xFFEF5350);

  // --- Semantic Colors ---
  static const Color success = deepGreen;
  static const Color error = boldRed;
  static const Color warning = amber;
  static const Color info = lightBlue;

  // --- Table / Room Status Colors ---
  static const Color statusAvailable = deepGreen;
  static const Color statusOccupied = boldRed;
  static const Color statusBillRequested = amber;
  static const Color statusReserved = Color(0xFF1565C0);
  static const Color statusMaintenance = Color(0xFF6A1B9A);
  static const Color statusCleaning = Color(0xFF1565C0);
  static const Color statusCheckoutToday = Color(0xFFEF6C00);

  // --- Order Age Colors ---
  static const Color orderFresh = deepGreen;
  static const Color orderWaiting = amber;
  static const Color orderLate = boldRed;

  // --- Sidebar ---
  // Sidebar keeps the original dark navy regardless of primaryBlue changes.
  static const Color sidebarBackground = Color(0xFF1A3C5E);
  static const Color sidebarSelected = Color(0xFF254D74);
  static const Color sidebarText = white;
  static const Color sidebarIcon = Color(0xFFB0C8E0);
  // Named sidebar / dark-mode structural colors (previously inline magic values)
  static const Color sidebarDivider = Color(0xFF254D74);
  static const Color sidebarSectionLabel = Color(0xFF4A7FA5);
  static const Color darkBorder = Color(0xFF2A3A50);

  // --- Card shadow ---
  static const List<BoxShadow> cardShadow = [
    BoxShadow(
      color: Color(0x14000000),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];

  static const List<BoxShadow> cardShadowDark = [
    BoxShadow(
      color: Color(0x28000000),
      offset: Offset(0, 2),
      blurRadius: 8,
    ),
  ];
}
