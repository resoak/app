import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens aligned with LectureVault mock (dark navy, purple / blue accents).
abstract final class LectureVaultColors {
  static const Color bgDeep = Color(0xFF020617);
  static const Color bgCard = Color(0xFF0F172A);
  static const Color bgCardActive = Color(0xFF1A0F2E);
  static const Color borderActive = Color(0xFF9333EA);
  static const Color purple = Color(0xFF7C3AED);
  static const Color purpleBright = Color(0xFFA855F7);
  static const Color blueElectric = Color(0xFF3B82F6);
  static const Color statusGreen = Color(0xFF22C55E);
  static const Color stopRed = Color(0xFFEF4444);
  static const Color textMuted = Color(0xFF94A3B8);
  static const Color textMono = Color(0xFFCBD5E1);
}

ThemeData buildLectureVaultTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: LectureVaultColors.bgDeep,
    colorScheme: const ColorScheme.dark(
      primary: LectureVaultColors.purple,
      secondary: LectureVaultColors.blueElectric,
      surface: LectureVaultColors.bgCard,
      error: LectureVaultColors.stopRed,
    ),
  );

  return base.copyWith(
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}

TextStyle lvMono(double size, {Color? color, FontWeight? weight}) {
  return GoogleFonts.jetBrainsMono(
    fontSize: size,
    color: color ?? LectureVaultColors.textMono,
    fontWeight: weight ?? FontWeight.w500,
    letterSpacing: 0.3,
  );
}

TextStyle lvHeading(double size, {FontWeight weight = FontWeight.w700}) {
  return GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: Colors.white,
    letterSpacing: -0.3,
  );
}
