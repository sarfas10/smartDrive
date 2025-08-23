// lib/reusables/branding.dart
import 'package:flutter/material.dart';

/// ===== Brand / App Config =====
class AppBrand {
  static const String appName = 'SmartDrive';

  /// Place your logo at: project-root/assets/logo.png
  /// pubspec.yaml:
  /// flutter:
  ///   assets:
  ///     - assets/logo.png
  static const String? assetLogo = 'assets/logo.png';
}

/// ===== Brand Colors =====
class AppColors {
  static const Color primary = Color(0xFF4C008A);
  static const Color accent = Color(0xFF06B6D4);

  // Surfaces
  static const Color backgroundDark = Color(0xFF0B1020);
  static const Color backgroundLight = Colors.white;

  // Text
  static const Color onDark = Colors.white;
  static const Color onDarkMuted = Color(0xCCFFFFFF);
  static const Color onLight = Color(0xFF0F172A);
  static const Color onLightMuted = Color(0x990F172A);
}

/// ===== Central Text Styles =====
class AppText {
  static const TextStyle titleOnDark = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.onDark,
    letterSpacing: 0.4,
  );

  static const TextStyle titleOnLight = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: AppColors.onLight,
    letterSpacing: 0.2,
  );

  static const TextStyle buttonOnLight = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.onLight,
  );

  static const TextStyle captionMuted = TextStyle(
    fontSize: 12,
    color: AppColors.onLightMuted,
  );
}

/// ===== App Name (text only) =====
class AppNameText extends StatelessWidget {
  const AppNameText({
    super.key,
    this.size = 24,
    this.color,
    this.textStyle,
    this.maxLines = 1,
    this.overflow = TextOverflow.fade,
    this.textAlign,
  });

  final double size;
  final Color? color;
  final TextStyle? textStyle;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).brightness == Brightness.dark
        ? AppText.titleOnDark
        : AppText.titleOnLight;

    return Text(
      AppBrand.appName,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: (textStyle ?? base).copyWith(
        fontSize: size,
        color: color ?? base.color,
      ),
    );
  }
}

/// ===== App Logo (image only) =====
/// Always renders as a square of [size] x [size], regardless of source ratio.
/// Uses BoxFit.cover so it fully fills the square (cropping if needed).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 64, // increased default size
    this.semanticLabel = 'App Logo',
    this.borderRadius = 0,
  });

  final double size;
  final String semanticLabel;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final path = AppBrand.assetLogo;

    if (path == null || path.isEmpty) {
      // Fallback icon locked to the requested size
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.directions_car_filled_rounded, size: size * 0.9),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Image.asset(
          path,
          fit: BoxFit.cover,               // fill the square area
          alignment: Alignment.center,     // center-crop if needed
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) => Center(
            child: Icon(Icons.directions_car_filled_rounded, size: size * 0.9),
          ),
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

/// ===== Combined: Logo + Name (optional) =====
class AppBrandingRow extends StatelessWidget {
  const AppBrandingRow({
    super.key,
    this.logoSize = 56,  // bumped up to feel balanced
    this.nameSize = 24,
    this.spacing = 10,
    this.textColor,
    this.textStyle,
  });

  final double logoSize;
  final double nameSize;
  final double spacing;
  final Color? textColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        SizedBox(width: spacing),
        AppNameText(
          size: nameSize,
          color: textColor,
          textStyle: textStyle,
        ),
      ],
    );
  }
}

/// ===== Reusable Onboarding Header =====
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.onSkip,
    this.padding = const EdgeInsets.all(24),
    this.variant = HeaderVariant.logo, // or HeaderVariant.name
  });

  final VoidCallback onSkip;
  final EdgeInsets padding;
  final HeaderVariant variant;

  @override
  Widget build(BuildContext context) {
    final brandWidget = switch (variant) {
      HeaderVariant.logo => const AppLogo(size: 32),                 // slightly larger
      HeaderVariant.name => const AppNameText(size: 24),
      HeaderVariant.both => const AppBrandingRow(logoSize: 32, nameSize: 20),
    };

    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Semantics(header: true, child: brandWidget),
          TextButton(
            onPressed: onSkip,
            child: const Text(
              'Skip',
              style: TextStyle(
                color: AppColors.onDarkMuted,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum HeaderVariant { logo, name, both }
