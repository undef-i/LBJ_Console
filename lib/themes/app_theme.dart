import 'package:flutter/material.dart';

class AppTheme {
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Colors.white,
    onPrimary: Colors.black,
    secondary: Color(0xFF9E9E9E),
    onSecondary: Colors.black,
    error: Color(0xFFCF6679),
    onError: Colors.black,
    surface: Color(0xFF121212),
    surfaceBright: Color(0xFF393939),
    onSurface: Colors.white,
    surfaceContainerLowest: Color(0xFF0A0A0A),
    surfaceContainerLow: Color(0xFF171717),
    surfaceContainer: Color(0xFF1E1E1E),
    surfaceContainerHigh: Color(0xFF262626),
    surfaceContainerHighest: Color(0xFF2E2E2E),
    onSurfaceVariant: Color(0xFFB3B3B3),
    outline: Color(0xFF3A3A3C),
    outlineVariant: Color(0xFF2A2A2A),
    scrim: Colors.black,
    shadow: Colors.black,
    inverseSurface: Colors.white,
    onInverseSurface: Colors.black,
    inversePrimary: Colors.black,
  );

  static const ColorScheme _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Colors.black,
    onPrimary: Colors.white,
    secondary: Color(0xFF8E8E93),
    onSecondary: Colors.white,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    surface: Color(0xFFF2F2F7),
    surfaceBright: Colors.white,
    onSurface: Color(0xFF1C1C1E),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Color(0xFFF2F2F7),
    surfaceContainerHigh: Color(0xFFF2F2F7),
    surfaceContainerHighest: Color(0xFFE5E5EA),
    onSurfaceVariant: Color(0xFF48484A),
    outline: Color(0xFFC6C6C8),
    outlineVariant: Color(0xFFE5E5EA),
    scrim: Colors.black,
    shadow: Colors.black,
    inverseSurface: Color(0xFF1C1C1E),
    onInverseSurface: Colors.white,
    inversePrimary: Colors.white,
  );

  static ThemeData get darkTheme => _build(_darkScheme);
  static ThemeData get lightTheme => _build(_lightScheme);

  static ThemeData _build(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final background = dark ? scheme.surface : scheme.surfaceContainer;
    final primaryText = dark ? Colors.white : const Color(0xFF1C1C1E);
    final secondaryText = dark ? Colors.white70 : const Color(0xFF48484A);
    final tertiaryText = dark ? Colors.white60 : const Color(0xFF8A8A8E);
    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: scheme.surfaceContainer,
      primaryColor: scheme.primary,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: primaryText,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: primaryText),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
            color: primaryText, fontSize: 32, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(
            color: primaryText, fontSize: 28, fontWeight: FontWeight.bold),
        headlineSmall: TextStyle(
            color: primaryText, fontSize: 24, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(
            color: primaryText, fontSize: 20, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(
            color: primaryText, fontSize: 18, fontWeight: FontWeight.w500),
        titleSmall: TextStyle(
            color: primaryText, fontSize: 16, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: primaryText, fontSize: 16),
        bodyMedium: TextStyle(color: secondaryText, fontSize: 14),
        bodySmall: TextStyle(color: tertiaryText, fontSize: 12),
        labelLarge: TextStyle(
            color: primaryText, fontSize: 14, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(color: secondaryText, fontSize: 12),
        labelSmall: TextStyle(color: tertiaryText, fontSize: 10),
      ),
      iconTheme: IconThemeData(color: primaryText),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(34),
        ),
        titleTextStyle: TextStyle(
            color: primaryText, fontSize: 20, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: secondaryText, fontSize: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          elevation: 0,
          shape: const StadiumBorder(),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: dark
              ? scheme.surfaceContainerHigh
              : scheme.surfaceBright,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          minimumSize: const Size(0, 44),
          shape: const StadiumBorder(),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          shape: const StadiumBorder(),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          shape: const StadiumBorder(),
          textStyle:
              const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: primaryText, fontSize: 14),
        actionTextColor: primaryText,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  static const Color errorRed = Color(0xFFCF6679);
  static const Color successGreen = Color(0xFF4CAF50);
  static const Color warningOrange = Color(0xFFFF9800);

  static const TextStyle titleLarge = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
  );

  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;
  static const double spacingXXL = 48.0;

  static const double radiusS = 4.0;
  static const double radiusM = 8.0;
  static const double radiusL = 12.0;
  static const double radiusXL = 16.0;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get buttonShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];
}
