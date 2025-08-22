import 'package:flutter/material.dart';

/// ===== Brand / App Config =====
class AppBrand {
  static const String appName = 'SmartDrive';

  /// If you use an asset logo, set the path here and include it in pubspec.yaml.
  static const String? assetLogo = null; // e.g. 'assets/logo.png';
}

/// ===== Brand Colors =====
/// Stick to a small palette and reuse everywhere.
class AppColors {
  static const Color primary = Color(0xFF4C008A);
  static const Color accent = Color(0xFF06B6D4);

  // Dark onboarding background base color you used
  static const Color backgroundDark = Color(0xFF0B1020);

  // Text colors
  static const Color onDark = Colors.white;
  static const Color onDarkMuted = Color(0xCCFFFFFF);
}

/// ===== Text Styles (optional central styles) =====
class AppText {
  static const TextStyle titleOnDark = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: AppColors.onDark,
    letterSpacing: 0.5,
  );

  static const TextStyle buttonOnLight = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );
}

/// ===== Reusable Logo Widget =====
/// Use either an image asset or a styled text fallback.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size = 24,
    this.color = AppColors.onDark,
    this.textStyle,
  });

  final double size;
  final Color color;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (AppBrand.assetLogo != null) {
      return Image.asset(
        AppBrand.assetLogo!,
        height: size,
        fit: BoxFit.contain,
        color: null, // set to `color` if you use a monochrome svg/png
      );
    }
    // Text fallback
    return Text(
      AppBrand.appName,
      style: (textStyle ?? AppText.titleOnDark).copyWith(
        fontSize: size,
        color: color,
      ),
    );
  }
}

/// ===== Reusable Onboarding Header =====
/// Drop-in replacement for your header row ("SmartDrive" + "Skip").
class OnboardingHeader extends StatelessWidget {
  const OnboardingHeader({
    super.key,
    required this.onSkip,
    this.padding = const EdgeInsets.all(24),
  });

  final VoidCallback onSkip;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
           Semantics(
            header: true,
            child: AppLogo(size: 24),
          ),
          TextButton(
            onPressed: onSkip,
            child: Text(
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
