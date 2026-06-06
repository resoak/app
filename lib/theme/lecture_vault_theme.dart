import 'package:flutter/material.dart';

import '../models/app_settings.dart';

/// Local font family names registered in `pubspec.yaml`.
abstract final class LectureVaultFonts {
  static const String body = 'Inter';
  static const String mono = 'JetBrainsMono';
}

/// Brand accents shared by both black/white themes.
abstract final class LectureVaultColors {
  @Deprecated(
      'Use Theme.of(context).lectureVaultPalette.backgroundBase instead.')
  static const Color bgDeep = Color(0xFF020617);
  @Deprecated('Use Theme.of(context).lectureVaultPalette.surface instead.')
  static const Color bgCard = Color(0xFF0F172A);
  @Deprecated(
      'Use Theme.of(context).lectureVaultPalette.surfaceSelected instead.')
  static const Color bgCardActive = Color(0xFF1A0F2E);
  @Deprecated('Use Theme.of(context).lectureVaultPalette.borderStrong instead.')
  static const Color borderActive = Color(0xFF9333EA);
  static const Color purple = Color(0xFF7C3AED);
  static const Color purpleBright = Color(0xFFA855F7);
  static const Color blueElectric = Color(0xFF3B82F6);
  static const Color statusGreen = Color(0xFF22C55E);
  static const Color stopRed = Color(0xFFEF4444);
  @Deprecated('Use Theme.of(context).lectureVaultPalette.textMuted instead.')
  static const Color textMuted = Color(0xFF94A3B8);
  @Deprecated('Use Theme.of(context).lectureVaultPalette.textMono instead.')
  static const Color textMono = Color(0xFFCBD5E1);
}

@immutable
class LectureVaultPalette extends ThemeExtension<LectureVaultPalette> {
  const LectureVaultPalette({
    required this.backgroundBase,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSelected,
    required this.inputFill,
    required this.chromeSurface,
    required this.summaryGlass,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textMono,
  });

  final Color backgroundBase;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSelected;
  final Color inputFill;
  final Color chromeSurface;
  final Color summaryGlass;
  final Color borderSubtle;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textMono;

  static const LectureVaultPalette black = LectureVaultPalette(
    backgroundBase: Color(0xFF020617),
    surface: Color(0xFF0F172A),
    surfaceAlt: Color(0xFF111827),
    surfaceSelected: Color(0xFF1A0F2E),
    inputFill: Color(0xFF111827),
    chromeSurface: Color(0xFF0B1120),
    summaryGlass: Color(0xFF2D1B4E),
    borderSubtle: Color(0x14FFFFFF),
    borderStrong: Color(0xFF9333EA),
    textPrimary: Colors.white,
    textSecondary: Color(0xFFE2E8F0),
    textMuted: Color(0xFF94A3B8),
    textMono: Color(0xFFCBD5E1),
  );

  static const LectureVaultPalette white = LectureVaultPalette(
    backgroundBase: Colors.white, // 改為純白
    surface: Colors.white,
    surfaceAlt: Color(0xFFF1F5F9),
    surfaceSelected: Color(0xFFF3E8FF),
    inputFill: Color(0xFFF8FAFC),
    chromeSurface: Colors.white,
    summaryGlass: Color(0xFFF1E8FF),
    borderSubtle: Color(0xFFE2E8F0), // 更淡的邊框
    borderStrong: Color(0xFF7C3AED),
    textPrimary: Color(0xFF0F172A),
    textSecondary: Color(0xFF475569),
    textMuted: Color(0xFF94A3B8),
    textMono: Color(0xFF64748B),
  );

  @override
  LectureVaultPalette copyWith({
    Color? backgroundBase,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceSelected,
    Color? inputFill,
    Color? chromeSurface,
    Color? summaryGlass,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textMono,
  }) {
    return LectureVaultPalette(
      backgroundBase: backgroundBase ?? this.backgroundBase,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceSelected: surfaceSelected ?? this.surfaceSelected,
      inputFill: inputFill ?? this.inputFill,
      chromeSurface: chromeSurface ?? this.chromeSurface,
      summaryGlass: summaryGlass ?? this.summaryGlass,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textMono: textMono ?? this.textMono,
    );
  }

  @override
  LectureVaultPalette lerp(
    covariant ThemeExtension<LectureVaultPalette>? other,
    double t,
  ) {
    if (other is! LectureVaultPalette) {
      return this;
    }

    return LectureVaultPalette(
      backgroundBase: Color.lerp(backgroundBase, other.backgroundBase, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceSelected: Color.lerp(surfaceSelected, other.surfaceSelected, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      chromeSurface: Color.lerp(chromeSurface, other.chromeSurface, t)!,
      summaryGlass: Color.lerp(summaryGlass, other.summaryGlass, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textMono: Color.lerp(textMono, other.textMono, t)!,
    );
  }
}

ThemeData buildLectureVaultTheme(AppBackgroundStyle backgroundStyle) {
  final palette = switch (backgroundStyle) {
    AppBackgroundStyle.darkDefault => LectureVaultPalette.black,
    AppBackgroundStyle.white => LectureVaultPalette.white,
  };
  final isDark = backgroundStyle == AppBackgroundStyle.darkDefault;
  final base = ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: palette.backgroundBase,
    colorScheme: (isDark
            ? const ColorScheme.dark(
                primary: LectureVaultColors.purple,
                secondary: LectureVaultColors.blueElectric,
                error: LectureVaultColors.stopRed,
              )
            : const ColorScheme.light(
                primary: LectureVaultColors.purple,
                secondary: LectureVaultColors.blueElectric,
                error: LectureVaultColors.stopRed,
              ))
        .copyWith(
      surface: palette.surface,
      onSurface: palette.textPrimary,
      outline: palette.borderSubtle,
      onSurfaceVariant: palette.textMuted,
      surfaceTint: Colors.transparent,
    ),
  );

  return base.copyWith(
    extensions: <ThemeExtension<dynamic>>[palette],
    textTheme: base.textTheme
        .apply(
          bodyColor: palette.textPrimary,
          displayColor: palette.textPrimary,
        )
        .copyWith(
          // Use the locally bundled Inter font for every TextTheme role so
          // that default Material widgets (AppBar, Button, ListTile, etc.)
          // pick up the bundled font without needing to set fontFamily
          // explicitly at every callsite.
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          displayLarge: base.textTheme.displayLarge?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
          displaySmall: base.textTheme.displaySmall?.copyWith(
            fontFamily: LectureVaultFonts.body,
          ),
        ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    canvasColor: palette.surface,
    cardColor: palette.surface,
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomAppBarTheme: BottomAppBarThemeData(
      color: palette.chromeSurface,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: palette.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(
        fontFamily: LectureVaultFonts.mono,
        color: palette.textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.3,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.inputFill,
      hintStyle: TextStyle(color: palette.textMuted.withValues(alpha: 0.55)),
      labelStyle: TextStyle(color: palette.textMuted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: palette.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: LectureVaultColors.purpleBright),
      ),
    ),
    dividerColor: palette.borderSubtle,
    iconTheme: IconThemeData(color: palette.textPrimary),
  );
}

extension LectureVaultThemeDataX on ThemeData {
  LectureVaultPalette get lectureVaultPalette {
    final palette = extension<LectureVaultPalette>();
    assert(palette != null, 'LectureVaultPalette is missing from the theme.');
    return palette!;
  }
}

extension LectureVaultContextThemeX on BuildContext {
  LectureVaultPalette get lvPalette => Theme.of(this).lectureVaultPalette;

  TextStyle lvMono(double size, {Color? color, FontWeight? weight}) {
    return TextStyle(
      fontFamily: LectureVaultFonts.mono,
      fontSize: size,
      color: color ?? lvPalette.textMono,
      fontWeight: weight ?? FontWeight.w500,
      letterSpacing: 0.3,
    );
  }

  TextStyle lvHeading(
    double size, {
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: LectureVaultFonts.body,
      fontSize: size,
      fontWeight: weight,
      color: color ?? lvPalette.textPrimary,
      letterSpacing: -0.3,
    );
  }
}
