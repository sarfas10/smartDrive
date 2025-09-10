// lib/theme/app_theme.dart
import 'package:flutter/material.dart';

/// ─────────────────────────
/// Color Tokens (Design System)
/// ─────────────────────────
class AppColors {
  // Surfaces & backgrounds
  static const Color background = Color(0xFFF6F7FB);
  static const Color surface    = Colors.white;

  // Text
  static const Color onSurface              = Colors.black87;
  static const Color onSurfaceMuted         = Colors.black54;
  static const Color onSurfaceFaint         = Colors.black38;
  static const Color onSurfaceInverse       = Colors.white;
  static const Color onSurfaceInverseMuted  = Colors.white70;

  // Brand / functional
  static const Color primary    = Color(0xFF2D5BFF);
  static const Color brand      = Color(0xFF4C63D2); // from your helpers
  static const Color success    = Color(0xFF10B981);
  static const Color warning    = Color(0xFFFF8F00);
  static const Color info       = Color(0xFF1565C0);
  static const Color accentTeal = Color(0xFF00695C);
  static const Color purple     = Color(0xFF6A1B9A);
  static const Color brown      = Color(0xFF5D4037);
  static const Color slate      = Color(0xFF455A64);
  static const Color danger     = Color(0xFFD32F2F);

  // Lines / misc
  static const Color divider = Color(0x14000000); // 8% black

  // Name card gradient stops
  static const Color cardGradA = Color(0xFF2B2B2D);
  static const Color cardGradB = Color(0xFF3A3B3E);
  static const Color cardGradC = Color(0xFF1F2022);

  // Badge palettes (light surfaces)
  static const Color warnBg   = Color(0xFFFFF3CD);
  static const Color warnFg   = Color(0xFF856404);
  static const Color okBg     = Color(0xFFD4EDDA);
  static const Color okFg     = Color(0xFF155724);
  static const Color errBg    = Color(0xFFF8D7DA);
  static const Color errFg    = Color(0xFF721C24);
  static const Color neuBg    = Color(0xFFE9ECEF);
  static const Color neuFg    = Color(0xFF495057);

  // Role badge palettes
  static const Color roleAdminBg      = Color(0xFFEDE7F6);
  static const Color roleAdminFg      = Color(0xFF5E35B1);
  static const Color roleInstructorBg = Color(0xFFE3F2FD);
  static const Color roleInstructorFg = Color(0xFF1565C0);
  static const Color roleStudentBg    = Color(0xFFFFF8E1);
  static const Color roleStudentFg    = Color(0xFFCC6E00);
}

/// ─────────────────────────
/// Radii / Elevation / Shadows
/// ─────────────────────────
class AppRadii {
  static const double s  = 12;
  static const double m  = 14;
  static const double l  = 16;
  static const double xl = 20;
}

class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withOpacity(0.08),
      blurRadius: 12,
      offset: const Offset(0, 3),
    ),
  ];

  static List<BoxShadow> elevatedDark = [
    BoxShadow(
      color: Colors.black.withOpacity(0.45),
      blurRadius: 14,
      offset: const Offset(0, 8),
    ),
  ];
}

/// ─────────────────────────
/// Gradients
/// ─────────────────────────
class AppGradients {
  // Name card
  static const LinearGradient nameCard = LinearGradient(
    begin: Alignment(-0.9, -0.9),
    end: Alignment(0.9, 0.9),
    colors: [AppColors.cardGradA, AppColors.cardGradB, AppColors.cardGradC],
    stops: [0.0, 0.55, 1.0],
  );

  // Brand hero background (used by BgGradient)
  static const LinearGradient brandHero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
  );

  // Brand chip/avatar
  static const LinearGradient brandChip = LinearGradient(
    colors: [AppColors.brand, Color(0xFF764BA2)],
  );
}

/// ─────────────────────────
/// Typography helpers
/// ─────────────────────────
class AppText {
  static const TextStyle sectionTitle = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 16,
    color: AppColors.onSurface,
  );

  static const TextStyle tileTitle = TextStyle(
    fontWeight: FontWeight.w700,
    fontSize: 14,
    color: AppColors.onSurface,
  );

  static const TextStyle tileSubtitle = TextStyle(
    fontSize: 12,
    color: AppColors.onSurfaceMuted,
  );

  static const TextStyle hintSmall = TextStyle(
    fontSize: 12,
    color: AppColors.onSurfaceFaint,
  );
}

/// ─────────────────────────
/// App Theme (global)
/// ─────────────────────────
class AppTheme {
  static ThemeData light = ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      background: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      shadowColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.l),
      ),
    ),
    dividerColor: AppColors.divider,
  );
}

/// ─────────────────────────
/// Handy BuildContext shortcuts
/// ─────────────────────────
extension XCtx on BuildContext {
  ColorScheme get c => Theme.of(this).colorScheme;
  TextTheme  get t => Theme.of(this).textTheme;
}
