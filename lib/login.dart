import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_drive/admin_dashboard';
import 'package:smart_drive/instructor_dashboard.dart';
import 'package:smart_drive/student_dashboard.dart';

import 'register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // Background gradient animation (new)
  late final AnimationController _bgController;

  // Card/content animations (existing)
  late final AnimationController _cardController;
  late final Animation<double> _cardAnimation;
  late final Animation<Offset> _slideAnimation;

  bool obscurePassword = true;
  bool rememberMe = false;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _cardAnimation = CurvedAnimation(
      parent: _cardController,
      curve: Curves.elasticOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutCubic,
    ));

    _cardController.forward();

    _restoreRemembered();
  }

  Future<void> _restoreRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('sd_saved_email');
    final savedRemember = prefs.getBool('sd_remember_me') ?? false;
    if (savedRemember && savedEmail != null && savedEmail.isNotEmpty) {
      setState(() {
        rememberMe = true;
        _emailController.text = savedEmail;
      });
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _cardController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

Future<void> _handleLogin() async {
  if (!_formKey.currentState!.validate()) return;

  setState(() => _isLoading = true);

  try {
    // (Optional on web) persistence already handled earlier in your code
    final userCred = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    final user = userCred.user;
    if (user == null) {
      _showError('Could not sign in. Please try again.');
      return;
    }

    // Fetch role from Firestore: users/{uid}.role
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (!doc.exists) {
      _showError('Profile not found. Contact support.');
      return;
    }

    final data = doc.data();
    final rawRole = (data?['role'] ?? '').toString().trim().toLowerCase();

    // Optional: remember-me email save/clear
    final prefs = await SharedPreferences.getInstance();
    if (rememberMe) {
      await prefs.setString('sd_saved_email', _emailController.text.trim());
      await prefs.setBool('sd_remember_me', true);
    } else {
      await prefs.remove('sd_saved_email');
      await prefs.setBool('sd_remember_me', false);
    }

    if (!mounted) return;

    // Route by role (accepts "student", "instructor" (or the common typo), "admin")
    switch (rawRole) {
      case 'student':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) =>  StudentDashboard()),
        );
        break;

      case 'instructor':
      case 'intsrtuctor': // tolerate the typo if it exists in stored data
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) =>  InstructorDashboard()),
        );
        break;

      case 'admin':
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminDashboard()),
        );
        break;

      default:
        _showError('Unknown role "$rawRole". Contact support.');
        break;
    }
  } on FirebaseAuthException catch (e) {
    _showError(_mapAuthError(e));
  } catch (_) {
    _showError('Something went wrong. Please try again.');
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}


  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address looks invalid.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'user-not-found':
        return 'No account found for that email.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return 'Login failed (${e.code}). Please try again.';
    }
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showError('Enter your email above before tapping reset.');
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showError('Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      _showError(_mapAuthError(e));
    } catch (_) {
      _showError('Could not send reset email. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 🔮 Animated multi-blob gradient background
          RepaintBoundary(
            child: CustomPaint(
              painter: _BlobGradientPainter(animation: _bgController),
              child: const SizedBox.expand(),
            ),
          ),

          // Optional soft vignette for depth
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

          // Foreground content
          SafeArea(
            child: SizedBox.expand(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom,
                  ),
                  child: IntrinsicHeight(
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: ScaleTransition(
                        scale: _cardAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildLogo(),
                            const SizedBox(height: 32),
                            _buildLoginCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.directions_car_rounded,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Welcome Back',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          'Sign in to continue your driving journey',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white.withOpacity(0.8),
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sign In',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildTextField(
              controller: _emailController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _buildPasswordField(),
            const SizedBox(height: 12),
            _buildRememberMeRow(),
            const SizedBox(height: 20),
            _buildLoginButton(),
            const SizedBox(height: 12),
            
            _buildRegisterButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
          prefixIcon:
              Icon(icon, color: Colors.white.withOpacity(0.7), size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your $label';
          }
          if (label == 'Email' && !value.contains('@')) {
            return 'Please enter a valid email';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: TextFormField(
        controller: _passwordController,
        obscureText: obscurePassword,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: 'Password',
          labelStyle:
              TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
          prefixIcon: Icon(Icons.lock_outline,
              color: Colors.white.withOpacity(0.7), size: 18),
          suffixIcon: IconButton(
            icon: Icon(
              obscurePassword ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Colors.white.withOpacity(0.7),
            ),
            onPressed: () {
              setState(() {
                obscurePassword = !obscurePassword;
              });
            },
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Please enter your password';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildRememberMeRow() {
    return Row(
      children: [
        Checkbox(
          value: rememberMe,
          onChanged: (value) {
            setState(() {
              rememberMe = value ?? false;
            });
          },
          fillColor: MaterialStateProperty.all(
            Colors.white.withOpacity(0.8),
          ),
          checkColor: const Color(0xFF6366F1),
        ),
        Text(
          'Remember me',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 13,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: _sendResetLink,
          child: Text(
            'Forgot Password?',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.9),
          foregroundColor: const Color(0xFF6366F1),
          elevation: 8,
          shadowColor: Colors.black.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading) ...[
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
            ],
            const Text(
              'Sign In',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return TextButton(
      onPressed: _navigateToRegister,
      child: RichText(
        text: TextSpan(
          style:
              TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
          children: const [
            TextSpan(text: "Don't have an account? "),
            TextSpan(
              text: 'Sign Up',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuccessDialog(String title) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white.withOpacity(0.95),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: const [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text('Welcome Back!'),
            ],
          ),
          content: Text(title),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // TODO: Navigate to your app's dashboard/home:
                // Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }
}

/// ===== Animated multi-blob gradient painter (same as onboarding) =====
class _BlobGradientPainter extends CustomPainter {
  final Animation<double> animation;

  _BlobGradientPainter({required this.animation}) : super(repaint: animation);

  double _wave(double t, {double amp = 0.25, double phase = 0}) {
    return 0.5 + amp * math.sin(2 * math.pi * (t + phase));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final time = animation.value;

    // Base dark backdrop
    final basePaint = Paint()..color = const Color(0xFF0B1020);
    canvas.drawRect(Offset.zero & size, basePaint);

    // Centers drifting over time
    final c1 = Offset(
      _wave(time, amp: 0.30, phase: 0.00) * size.width,
      _wave(time, amp: 0.22, phase: 0.15) * size.height,
    );
    final c2 = Offset(
      _wave(time, amp: 0.28, phase: 0.35) * size.width,
      _wave(time, amp: 0.24, phase: 0.55) * size.height,
    );
    final c3 = Offset(
      _wave(time, amp: 0.26, phase: 0.65) * size.width,
      _wave(time, amp: 0.20, phase: 0.85) * size.height,
    );
    final c4 = Offset(
      _wave(time, amp: 0.32, phase: 0.20) * size.width,
      _wave(time, amp: 0.18, phase: 0.40) * size.height,
    );

    // Radii
    final r = size.shortestSide;
    final r1 = r * 0.75;
    final r2 = r * 0.70;
    final r3 = r * 0.65;
    final r4 = r * 0.80;

    // Blobs
    final paint1 = Paint()
      ..shader = ui.Gradient.radial(
        c1,
        r1,
        [const Color(0xFF6D28D9).withOpacity(0.65), const Color(0x006D28D9)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    final paint2 = Paint()
      ..shader = ui.Gradient.radial(
        c2,
        r2,
        [const Color(0xFF2563EB).withOpacity(0.60), const Color(0x002563EB)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    final paint3 = Paint()
      ..shader = ui.Gradient.radial(
        c3,
        r3,
        [const Color(0xFFF43F5E).withOpacity(0.55), const Color(0x00F43F5E)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    final paint4 = Paint()
      ..shader = ui.Gradient.radial(
        c4,
        r4,
        [const Color(0xFF06B6D4).withOpacity(0.55), const Color(0x0006B6D4)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;

    canvas.drawCircle(c1, r1, paint1);
    canvas.drawCircle(c2, r2, paint2);
    canvas.drawCircle(c3, r3, paint3);
    canvas.drawCircle(c4, r4, paint4);

    // Subtle top glow
    final highlight = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, size.height),
        [Colors.white.withOpacity(0.05), Colors.transparent],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    canvas.drawRect(Offset.zero & size, highlight);
  }

  @override
  bool shouldRepaint(covariant _BlobGradientPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
