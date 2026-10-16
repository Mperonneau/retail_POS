import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  AppTextStyles._();

  // --- App Name / Logo ---
  static TextStyle appName({Color? color = const Color(0xFFFFFFFF)}) =>
      GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: color);

  // --- Page Title H1 ---
  // Default null → inherits primaryText from the theme's DefaultTextStyle
  static TextStyle h1({Color? color}) =>
      GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700, color: color);

  // --- Section Title H2 ---
  static TextStyle h2({Color? color}) =>
      GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: color);

  // --- Card Title H3 ---
  static TextStyle h3({Color? color = const Color(0xFFF5A623)}) =>
      GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: color);

  // --- Body Text ---
  // Default null → inherits bodyMedium color (nearBlack in light / warmWhite in dark)
  static TextStyle body({Color? color}) =>
      GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: color);

  // --- Label / Caption ---
  // Default null → inherits labelSmall color (darkGray in light / coolGray in dark)
  static TextStyle caption({Color? color}) =>
      GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: color);

  // --- Prices / Numbers ---
  // Default null → inherits primaryText (nearBlack in light / warmWhite in dark)
  static TextStyle price({Color? color}) =>
      GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: color);

  // --- Large Stat Number (dashboard) ---
  // Default null → inherits primaryText
  static TextStyle statNumber({Color? color}) =>
      GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w700, color: color);

  // --- Button Text ---
  static TextStyle button({Color? color = const Color(0xFFFFFFFF)}) =>
      GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: color);

  // --- Navigation Items ---
  static TextStyle navItem({Color? color = const Color(0xFFFFFFFF)}) =>
      GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500, color: color);

  // --- Input Label ---
  // Default null → inherits theme label color (darkGray in light / coolGray in dark)
  static TextStyle inputLabel({Color? color}) =>
      GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: color);

  // --- Error Text ---
  static TextStyle errorText({Color? color = const Color(0xFFC62828)}) =>
      GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: color);
}
