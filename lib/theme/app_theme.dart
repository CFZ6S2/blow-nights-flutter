import 'package:flutter/material.dart';

/// Tailwind palette used by the web app, so `text-fuchsia-400` → `Tw.fuchsia400`.
class Tw {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  static const slate300 = Color(0xFFCBD5E1);
  static const slate400 = Color(0xFF94A3B8);
  static const slate500 = Color(0xFF64748B);
  static const slate600 = Color(0xFF475569);
  static const slate700 = Color(0xFF334155);
  static const slate800 = Color(0xFF1E293B);
  static const slate900 = Color(0xFF0F172A);
  static const slate950 = Color(0xFF020617);

  static const fuchsia300 = Color(0xFFF0ABFC);
  static const fuchsia400 = Color(0xFFE879F9);
  static const fuchsia500 = Color(0xFFD946EF);
  static const fuchsia600 = Color(0xFFC026D3);
  static const fuchsia900 = Color(0xFF701A75);
  static const fuchsia950 = Color(0xFF4A044E);

  static const purple400 = Color(0xFFC084FC);
  static const purple500 = Color(0xFFA855F7);
  static const purple600 = Color(0xFF9333EA);
  static const purple900 = Color(0xFF581C87);

  static const indigo400 = Color(0xFF818CF8);
  static const indigo500 = Color(0xFF6366F1);
  static const indigo600 = Color(0xFF4F46E5);
  static const indigo900 = Color(0xFF312E81);
  static const indigo950 = Color(0xFF1E1B4B);

  static const blue400 = Color(0xFF60A5FA);
  static const blue500 = Color(0xFF3B82F6);
  static const blue600 = Color(0xFF2563EB);
  static const blue900 = Color(0xFF1E3A8A);

  static const pink500 = Color(0xFFEC4899);
  static const pink400 = Color(0xFFF472B6);

  static const emerald400 = Color(0xFF34D399);
  static const emerald500 = Color(0xFF10B981);
  static const green400 = Color(0xFF4ADE80);
  static const green500 = Color(0xFF22C55E);
  static const emerald600 = Color(0xFF059669);
  static const green600 = Color(0xFF16A34A);

  static const amber400 = Color(0xFFFBBF24);
  static const amber500 = Color(0xFFF59E0B);
  static const orange500 = Color(0xFFF97316);
  static const orange400 = Color(0xFFFB923C);
  static const orange600 = Color(0xFFEA580C);
  static const orange900 = Color(0xFF7C2D12);
  static const yellow400 = Color(0xFFFACC15);
  static const yellow500 = Color(0xFFEAB308);

  static const red400 = Color(0xFFF87171);
  static const red500 = Color(0xFFEF4444);
  static const red600 = Color(0xFFDC2626);
  static const red900 = Color(0xFF7F1D1D);

  static const cyan400 = Color(0xFF22D3EE);
  static const cyan500 = Color(0xFF06B6D4);
  static const cyan600 = Color(0xFF0891B2);
  static const teal400 = Color(0xFF2DD4BF);
  static const teal500 = Color(0xFF14B8A6);
  static const teal600 = Color(0xFF0D9488);
  static const rose400 = Color(0xFFFB7185);
  static const rose500 = Color(0xFFF43F5E);
  static const violet400 = Color(0xFFA78BFA);
  static const violet500 = Color(0xFF8B5CF6);
  static const sky400 = Color(0xFF38BDF8);
  static const lime400 = Color(0xFFA3E635);

  /// bg-white/5, border-white/10 etc.
  static Color w(double alpha) => white.withValues(alpha: alpha);
}

class AppTheme {
  static const Color primary = Tw.fuchsia500;
  static const Color primaryDark = Tw.purple600;
  static const Color background = Tw.slate950;
  static const Color surface = Tw.slate900;
  static const Color surfaceLight = Tw.slate800;
  static const Color textPrimary = Tw.white;
  static const Color textSecondary = Tw.slate400;
  static const Color success = Tw.green500;
  static const Color error = Tw.red500;
  static const Color warning = Tw.amber500;

  /// bg-gradient-to-r from-fuchsia-600 to-indigo-600 (primary CTA on the web)
  static const Gradient ctaGradient = LinearGradient(colors: [Tw.fuchsia600, Tw.indigo600]);

  /// from-fuchsia-500 via-purple-500 to-indigo-500 (BLOW NIGHTS wordmark)
  static const Gradient wordmarkGradient = LinearGradient(colors: [Tw.fuchsia500, Tw.purple500, Tw.indigo500]);

  static const Gradient brandGradient = ctaGradient;

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        primaryColor: primary,
        scaffoldBackgroundColor: background,
        fontFamily: null,
        colorScheme: const ColorScheme.dark(
          primary: primary,
          secondary: primaryDark,
          surface: surface,
          onPrimary: Colors.white,
          onSurface: textPrimary,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Tw.w(0.05),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          hintStyle: const TextStyle(color: Tw.slate500, fontSize: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Tw.w(0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Tw.w(0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Tw.fuchsia500.withValues(alpha: 0.5)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Tw.slate900,
          contentTextStyle: const TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Tw.w(0.1)),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dividerTheme: DividerThemeData(color: Tw.w(0.1), thickness: 1),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: Tw.fuchsia500),
      );
}
