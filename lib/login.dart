import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_drive/admin_dashboard.dart';
import 'package:smart_drive/instructor_dashboard.dart';
import 'package:smart_drive/student_dashboard.dart';
import 'package:smart_drive/reusables/branding.dart';

import 'register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // Background gradient animation
  late final AnimationController _bgController;

  // Card/content animations
  late final AnimationController _cardController;
  late final Animation<double> _scaleIn;
  late final Animation<Offset> _slideUp;
  late final Animation<double> _fadeIn;

  bool obscurePassword = true;
  bool rememberMe = false;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Focus nodes for better keyboard handling
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _scaleIn = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutBack,
    );

    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutCubic,
    ));

    _fadeIn = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOut,
    );

    _cardController.forward();
    _restoreRemembered();
  }

  Future<void> _restoreRemembered() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('sd_saved_email');
    final savedRemember = prefs.getBool('sd_remember_me') ?? false;
    if (savedRemember && (savedEmail?.isNotEmpty ?? false)) {
      setState(() {
        rememberMe = true;
        _emailController.text = savedEmail!;
      });
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _cardController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool _validateInputs() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _showToast('Please enter your email', isError: true);
      return false;
    }

    if (!email.contains('@') || !email.contains('.')) {
      _showToast('Please enter a valid email address', isError: true);
      return false;
    }

    if (password.isEmpty) {
      _showToast('Please enter your password', isError: true);
      return false;
    }

    return true;
  }

  Future<void> _handleLogin() async {
    // Dismiss keyboard
    _emailFocusNode.unfocus();
    _passwordFocusNode.unfocus();
    
    if (!_validateInputs()) return;

    setState(() => _isLoading = true);

    try {
      final userCred = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = userCred.user;
      if (user == null) {
        _showToast('Could not sign in. Please try again.', isError: true);
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        _showToast('Profile not found. Contact support.', isError: true);
        return;
      }

      final data = doc.data();
      final rawRole = (data?['role'] ?? '').toString().trim().toLowerCase();

      final prefs = await SharedPreferences.getInstance();
      if (rememberMe) {
        await prefs.setString('sd_saved_email', _emailController.text.trim());
        await prefs.setBool('sd_remember_me', true);
      } else {
        await prefs.remove('sd_saved_email');
        await prefs.setBool('sd_remember_me', false);
      }

      if (!mounted) return;

      Widget next;
      switch (rawRole) {
        case 'student':
          next = StudentDashboard();
          break;
        case 'instructor':
        case 'intsrtuctor': // handle typo
          next = const InstructorDashboard();
          break;
        case 'admin':
          next = const AdminDashboard();
          break;
        default:
          _showToast('Unknown role "$rawRole". Contact support.', isError: true);
          return;
      }

      await Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => next,
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 220),
      ));
    } on FirebaseAuthException catch (e) {
      _showToast(_mapAuthError(e), isError: true);
    } catch (_) {
      _showToast('Something went wrong. Please try again.', isError: true);
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
    _emailFocusNode.unfocus();
    _passwordFocusNode.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  void _showToast(String message, {bool isError = false}) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        isError: isError,
        onDismiss: () => overlayEntry.remove(),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // Auto dismiss after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  Future<void> _sendResetLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showToast('Enter your email above before tapping reset.', isError: true);
      return;
    }
    try {
      await _auth.sendPasswordResetEmail(email: email);
      _showToast('Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      _showToast(_mapAuthError(e), isError: true);
    } catch (_) {
      _showToast('Could not send reset email. Try again.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Prevent the body from resizing when keyboard appears
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const RepaintBoundary(child: _AnimatedBackground()),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.2,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.05),
                  ],
                  stops: const [0.7, 1.0],
                ),
              ),
            ),
          ),
          // Use Positioned instead of SafeArea for better control
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            bottom: 0,
            child: SingleChildScrollView(
              // Add keyboard padding manually
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: 24.0,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 
                             MediaQuery.of(context).padding.vertical - 48,
                ),
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideUp,
                    child: ScaleTransition(
                      scale: _scaleIn,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLogo(),
                          const SizedBox(height: 28),
                          _buildLoginCard(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading)
            IgnorePointer(
              ignoring: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  // === BRANDING ===
  Widget _buildLogo() {
    return Column(
      children: const [
        AppLogo(size: 92),
        SizedBox(height: 10),
        AppNameText(size: 26, color: Colors.white),
        SizedBox(height: 6),
        Text(
          'Welcome Back',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Email field
              _buildTextField(
                controller: _emailController,
                focusNode: _emailFocusNode,
                hint: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
              ),
              const SizedBox(height: 16),

              // Password field
              _buildPasswordField(),
              const SizedBox(height: 16),

              _buildRememberMeRow(),
              const SizedBox(height: 18),
              _buildLoginButton(),
              const SizedBox(height: 10),
              _buildRegisterButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.done,
    Function(String)? onFieldSubmitted,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autocorrect: false,
        enableSuggestions: false,
        textAlign: TextAlign.left, // Left align text
        style: const TextStyle(
          color: Colors.white, 
          fontSize: 14,
          decorationThickness: 0,
        ),
        cursorColor: Colors.white,
        cursorWidth: 2,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 14,
          ),
          prefixIcon: Icon(
            icon, 
            color: Colors.white.withValues(alpha: 0.72), 
            size: 18
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onSubmitted: onFieldSubmitted,
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20), width: 1),
      ),
      child: TextField(
        controller: _passwordController,
        focusNode: _passwordFocusNode,
        obscureText: obscurePassword,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.left, // Left align text
        onSubmitted: (_) => _handleLogin(),
        style: const TextStyle(
          color: Colors.white, 
          fontSize: 14,
          decorationThickness: 0,
        ),
        cursorColor: Colors.white,
        cursorWidth: 2,
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.72), 
            fontSize: 14
          ),
          prefixIcon: Icon(
            Icons.lock_outline,
            color: Colors.white.withValues(alpha: 0.72),
            size: 18,
          ),
          suffixIcon: IconButton(
            splashRadius: 18,
            icon: Icon(
              obscurePassword ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Colors.white.withValues(alpha: 0.72),
            ),
            onPressed: () => setState(() => obscurePassword = !obscurePassword),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildRememberMeRow() {
    return Row(
      children: [
        Checkbox(
          value: rememberMe,
          onChanged: (value) => setState(() => rememberMe = value ?? false),
          fillColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) {
              return Colors.white.withValues(alpha: 0.95);
            }
            return Colors.white.withValues(alpha: 0.8);
          }),
          checkColor: const Color(0xFF6366F1),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(
          'Remember me',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 13,
          ),
        ),
        const Spacer(),
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
          onPressed: _sendResetLink,
          child: const Text(
            'Forgot Password?',
            style: TextStyle(
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
          backgroundColor: Colors.white.withValues(alpha: 0.95),
          foregroundColor: const Color(0xFF6366F1),
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.30),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: _isLoading
              ? Row(
                  key: const ValueKey('loading'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Signing you in…',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey('signin'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Sign In',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildRegisterButton() {
    return TextButton(
      onPressed: _navigateToRegister,
      child: RichText(
        text: TextSpan(
          style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          children: const [
            TextSpan(text: "Don't have an account? "),
            TextSpan(
              text: 'Sign Up',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Toast Widget
class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: widget.isError 
                    ? Colors.red.shade600.withValues(alpha: 0.95)
                    : Colors.green.shade600.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    widget.isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _dismiss,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===== Lightweight animated background =====
class _AnimatedBackground extends StatelessWidget {
  const _AnimatedBackground();

  @override
  Widget build(BuildContext context) {
    return const _BlobGradient(animDuration: Duration(seconds: 18));
  }
}

class _BlobGradient extends StatefulWidget {
  final Duration animDuration;
  const _BlobGradient({required this.animDuration});

  @override
  State<_BlobGradient> createState() => _BlobGradientState();
}

class _BlobGradientState extends State<_BlobGradient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.animDuration)
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => CustomPaint(
          painter: _BlobGradientPainter(animation: _ctrl),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

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

    // Drift centers
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
        [const Color(0xFF6D28D9).withValues(alpha: 0.65), const Color(0x006D28D9)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    final paint2 = Paint()
      ..shader = ui.Gradient.radial(
        c2,
        r2,
        [const Color(0xFF2563EB).withValues(alpha: 0.60), const Color(0x002563EB)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    final paint3 = Paint()
      ..shader = ui.Gradient.radial(
        c3,
        r3,
        [const Color(0xFFF43F5E).withValues(alpha: 0.55), const Color(0x00F43F5E)],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    final paint4 = Paint()
      ..shader = ui.Gradient.radial(
        c4,
        r4,
        [const Color(0xFF06B6D4).withValues(alpha: 0.55), const Color(0x0006B6D4)],
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
        [Colors.white.withValues(alpha: 0.05), Colors.transparent],
        const [0.0, 1.0],
      )
      ..blendMode = BlendMode.plus;
    canvas.drawRect(Offset.zero & size, highlight);
  }

  @override
  bool shouldRepaint(covariant _BlobGradientPainter oldDelegate) =>
      oldDelegate.animation != animation;
}