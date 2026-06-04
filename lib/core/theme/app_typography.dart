import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Plus Jakarta Sans text theme. Applied by AppTheme for both brightnesses.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(TextTheme base) =>
      GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
        displaySmall: GoogleFonts.plusJakartaSans(
            textStyle: base.displaySmall, fontWeight: FontWeight.w800),
        headlineSmall: GoogleFonts.plusJakartaSans(
            textStyle: base.headlineSmall, fontWeight: FontWeight.w700),
        titleLarge: GoogleFonts.plusJakartaSans(
            textStyle: base.titleLarge, fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.plusJakartaSans(
            textStyle: base.titleMedium, fontWeight: FontWeight.w600),
        labelLarge: GoogleFonts.plusJakartaSans(
            textStyle: base.labelLarge, fontWeight: FontWeight.w600),
      );
}
