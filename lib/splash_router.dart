import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/session_service.dart';
import 'onboard.dart';
import 'login.dart';
import 'student_dashboard.dart';
import 'instructor_dashboard.dart';
import 'admin_dashboard.dart';

class SplashRouter extends StatefulWidget {
  const SplashRouter({super.key});

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    try {
      final sp = await SharedPreferences.getInstance();

      // 1) Onboarding?
      final seenOnboarding = sp.getBool('onboarding_seen') ?? false;
      if (!seenOnboarding) {
        _go(const OnboardingScreen());
        return;
      }

      // 2) Session + remember-me?
      final rememberMe = sp.getBool('sd_remember_me') ?? false;
      final session = await SessionService().read();
      final uid = session.userId;
      final role = (session.role ?? '').trim().toLowerCase();

      if (rememberMe && uid != null && role.isNotEmpty) {
        _go(_roleToHome(role));
        return;
      }

      // 3) Default → Login (skip tiny boot check)
      _go(const LoginScreen(skipBootCheck: true));
    } catch (_) {
      // Any error → Login
      _go(const LoginScreen(skipBootCheck: true));
    }
  }

  Widget _roleToHome(String role) {
    switch (role) {
      case 'student':
        return StudentDashboard();
      case 'instructor':
      case 'intsrtuctor':
        return InstructorDashboardPage();
      case 'admin':
        return const AdminDashboard();
      default:
        return const LoginScreen(skipBootCheck: true);
    }
  }

  void _go(Widget page) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This is the ONLY spinner after the native splash.
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
