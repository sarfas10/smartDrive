// lib/onboard.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_drive/reusables/animated_background.dart';
import 'package:smart_drive/reusables/branding.dart';

import 'login.dart'; // LoginScreen

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const _seenKey = 'onboarding_seen';

  final PageController _pageController = PageController();
  int currentPage = 0;

  late final AnimationController _cardController;
  late final Animation<double> _fadeAnimation;

  late final List<OnboardingData> pages;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: AppColors.backgroundDark,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // 👇 Titles now are base strings without app name
    pages = const [
      OnboardingData(
        title: "Welcome to ",
        description:
            "Your comprehensive driving education platform that connects students with certified instructors",
        icon: Icons.directions_car_rounded,
        color: Color(0xFF6366F1),
      ),
      OnboardingData(
        title: "Learn from Experts",
        description:
            "Get personalized lessons from certified driving instructors with years of experience",
        icon: Icons.school_rounded,
        color: Color(0xFF8B5CF6),
      ),
      OnboardingData(
        title: "Track Your Progress",
        description:
            "Monitor your learning journey with detailed progress tracking and performance analytics",
        icon: Icons.trending_up_rounded,
        color: Color(0xFF06B6D4),
      ),
      OnboardingData(
        title: "Safe & Secure",
        description:
            "All instructors are verified and background-checked for your safety and peace of mind",
        icon: Icons.security_rounded,
        color: Color(0xFF10B981),
      ),
    ];

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutCubic,
    );
    _cardController.forward();

    _maybeSkipIfSeen();
  }

  Future<void> _maybeSkipIfSeen() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) {
      _goToLogin(replace: true);
    }
  }

  @override
  void dispose() {
    _cardController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishAndMarkSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
    _goToLogin(replace: true);
  }

  void _goToLogin({bool replace = false}) {
    final route = MaterialPageRoute(builder: (_) => const LoginScreen());
    if (replace) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  void nextPage() {
    HapticFeedback.selectionClick();
    if (currentPage < pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishAndMarkSeen();
    }
  }

  void skipOnboarding() {
    HapticFeedback.lightImpact();
    _finishAndMarkSeen();
  }

  Color get _accent => pages[currentPage].color;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AnimatedBlobBackground(),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.05),
                  ],
                  stops: const [0.7, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                OnboardingHeader(onSkip: skipOnboarding),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => currentPage = index);
                      _cardController
                        ..reset()
                        ..forward();
                    },
                    itemCount: pages.length,
                    itemBuilder: (_, i) => _buildPageContent(pages[i]),
                  ),
                ),
                _buildBottomSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(OnboardingData data) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: Colors.white.withOpacity(0.28),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(data.icon, size: 60, color: Colors.white),
            ),
            const SizedBox(height: 48),
            Text(
              // 👇 If title contains "Welcome to ", append appName
              data.title.contains("Welcome to ")
                  ? "${data.title}${AppBrand.appName}"
                  : data.title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            Text(
              data.description,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.90),
                height: 1.6,
                fontWeight: FontWeight.w300,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        children: [
          _buildPageIndicator(),
          const SizedBox(height: 32),
          _buildNavigationButton(),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        pages.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: currentPage == index ? 32 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentPage == index
                ? Colors.white
                : Colors.white.withOpacity(0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButton() {
    final isLast = currentPage == pages.length - 1;
    return Semantics(
      button: true,
      label: isLast ? 'Get Started' : 'Next',
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: nextPage,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.96),
            foregroundColor: _accent,
            elevation: 10,
            shadowColor: Colors.black.withOpacity(0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isLast ? 'Get Started' : 'Next',
                style: AppText.buttonOnLight,
              ),
              const SizedBox(width: 8),
              Icon(
                isLast
                    ? Icons.rocket_launch_rounded
                    : Icons.arrow_forward_rounded,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingData {
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const OnboardingData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}
