import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Primary (Emerald Green) ──
  static const Color primary = Color(0xFF10B981);
  static const Color primaryDark = Color(0xFF064E3B);
  static const Color primaryLight = Color(0xFF34D399);
  static const Color primarySurface = Color(0xFFECFDF5);

  // ── Background ──
  static const Color cream = Color(0xFFF8F5F0);
  static const Color warmWhite = Color(0xFFFAFAF8);
  static const Color pureWhite = Color(0xFFFFFFFF);

  // ── Text ──
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ── Accent ──
  static const Color gold = Color(0xFFD4AF37);
  static const Color softYellow = Color(0xFFFACC15);
  static const Color coral = Color(0xFFFB7185);
  static const Color skyBlue = Color(0xFF38BDF8);

  // ── Status ──
  static const Color success = Color(0xFF22C55E);
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color info = Color(0xFF3B82F6);

  // ── Green shades ──
  static const Color green50 = Color(0xFFECFDF5);
  static const Color green100 = Color(0xFFD1FAE5);
  static const Color green200 = Color(0xFFA7F3D0);
  static const Color green300 = Color(0xFF6EE7B7);
  static const Color green400 = Color(0xFF34D399);
  static const Color green500 = Color(0xFF10B981);
  static const Color green600 = Color(0xFF059669);
  static const Color green700 = Color(0xFF047857);
  static const Color green800 = Color(0xFF065F46);
  static const Color green900 = Color(0xFF064E3B);

  // ── Gray shades ──
  static const Color gray50 = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray300 = Color(0xFFD1D5DB);
  static const Color gray400 = Color(0xFF9CA3AF);
  static const Color gray500 = Color(0xFF6B7280);
  static const Color gray600 = Color(0xFF4B5563);
  static const Color gray700 = Color(0xFF374151);
  static const Color gray800 = Color(0xFF1F2937);
  static const Color gray900 = Color(0xFF111827);

  // ── Surface / Cards ──
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color surfaceBorder = Color(0xFFE5E7EB);
  static const Color surfaceOverlay = Color(0x33000000);

  // ── Soft glass (light mode) ──
  static const Color glassBg = Color(0x0D064E3B);       // very subtle green tint
  static const Color glassBorder = Color(0x1A064E3B);

  // ── Album preset colors ──
  static const List<Color> albumColors = [
    primary,
    skyBlue,
    coral,
    Color(0xFF8B5CF6), // violet
    Color(0xFFF59E0B), // amber
    Color(0xFF14B8A6), // teal
    Color(0xFFF43F5E), // rose
    Color(0xFF3B82F6), // blue
    gold,
    Color(0xFF84CC16), // lime
  ];

  // ── Gradients ──
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF10B981), Color(0xFF059669), Color(0xFF047857)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    colors: [cream, pureWhite],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [pureWhite, Color(0xFFFAFAF8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient headerGradient = LinearGradient(
    colors: [green50, pureWhite],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Dark Mode Colors ──
  static const Color darkBackground = Color(0xFF0B0F0C);
  static const Color darkSurface = Color(0xFF121815);
  static const Color darkCard = Color(0xFF1A1F1D);
  static const Color darkText = Color(0xFFF5F7F6);
  static const Color darkSubtitle = Color(0xFFA1A7A4);
  static const Color darkBorder = Color(0xFF2B2F2D);
  
  static const Color glassBgDark = Color(0x1AFFFFFF);
  static const Color glassBorderDark = Color(0x33FFFFFF);

  // ── Dark Mode Gradients ──
  static const LinearGradient darkBackgroundGradient = LinearGradient(
    colors: [darkBackground, darkSurface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ── Adaptive Helpers ──
  static LinearGradient getAdaptiveBackgroundGradient(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkBackgroundGradient : backgroundGradient;
  }

  static Color getAdaptiveSurfaceCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkCard : surfaceCard;
  }

  static Color getAdaptiveSurfaceBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? darkBorder : surfaceBorder;
  }

  static Color getAdaptiveGlassBg(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? glassBgDark : glassBg;
  }

  static Color getAdaptiveGlassBorder(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? glassBorderDark : glassBorder;
  }

  static Color parseHexColor(String? hexString, {Color fallback = AppColors.primary}) {
    if (hexString == null || hexString.trim().isEmpty) return fallback;
    try {
      String cleanHex = hexString.replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '').trim();
      if (cleanHex.length == 6) {
        cleanHex = 'FF$cleanHex';
      }
      return Color(int.parse(cleanHex, radix: 16));
    } catch (e) {
      debugPrint('Error parsing color $hexString: $e');
      return fallback;
    }
  }
}
