import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  // Background gradient animation
  late final AnimationController _bgController;

  // Card/content animations
  late final AnimationController _cardController;
  late final Animation<double> _cardAnimation;
  late final Animation<Offset> _slideAnimation;

  bool isStudent = true;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool agreeToTerms = false;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _licenseController = TextEditingController();
  final _experienceController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _cardAnimation = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutBack,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutCubic,
    ));

    _cardController.forward();
  }

  @override
  void dispose() {
    _bgController.dispose();
    _cardController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _licenseController.dispose();
    _experienceController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    if (!agreeToTerms) {
      _showToast('Please agree to the Terms of Service and Privacy Policy.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _registerWithFirebase();
      setState(() => _isLoading = false);

      _showToast(
        'Your ${isStudent ? 'student' : 'instructor'} account has been created. Welcome to SmartDrive!',
        success: true,
      );

      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _showToast(_friendlyAuthError(e));
    } catch (e) {
      setState(() => _isLoading = false);
      _showToast('Registration failed. ${e.toString()}');
    }
  }

  Future<void> _registerWithFirebase() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final displayName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final role = isStudent ? 'student' : 'instructor';
    final status = isStudent ? 'pending' : 'pending';

    final cred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);

    await cred.user?.updateDisplayName(displayName);

    final uid = cred.user!.uid;
    final data = {
      'uid': uid,
      'email': email,
      'name': displayName,
      'phone': phone,
      'role': role,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
      if (!isStudent) 'licenseNo': _licenseController.text.trim(),
      if (!isStudent)
        'yearsExp': int.tryParse(_experienceController.text.trim()) ?? 0,
    };

    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .set(data, SetOptions(merge: true));
  }

  String _friendlyAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Try signing in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is disabled in your Firebase project.';
      default:
        return e.message ?? 'Something went wrong. Please try again.';
    }
  }

  void _navigateBack() => Navigator.pop(context);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated gradient background
          RepaintBoundary(
            child: CustomPaint(
              painter: _BlobGradientPainter(animation: _bgController),
              child: const SizedBox.expand(),
            ),
          ),

          // Soft vignette
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

          // Single window: back button (top-left) + centered form
          SafeArea(
            child: Stack(
              children: [
                // Back button pinned top-left
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    onPressed: _navigateBack,
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 36, minHeight: 36),
                    iconSize: 18,
                    icon: const Icon(
                      Icons.arrow_back_ios_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),

                // Centered registration form
                Align(
                  alignment: Alignment.center,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: ScaleTransition(
                      scale: _cardAnimation,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _buildRegisterCardCompact(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Compact card so it fits without scrolling on most phones
  Widget _buildRegisterCardCompact() {
    const fieldGap = SizedBox(height: 10);
    const sectionGap = SizedBox(height: 12);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildUserTypeToggleCompact(),
            sectionGap,

            _buildTextFieldCompact(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person_outline_rounded,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter Full Name';
                }
                if (v.trim().length < 2) return 'Name looks too short';
                return null;
              },
            ),
            fieldGap,
            _buildTextFieldCompact(
              controller: _emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Please enter Email Address';
                }
                final email = v.trim();
                final ok =
                    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
                return ok ? null : 'Please enter a valid email address';
              },
            ),
            fieldGap,
            _buildTextFieldCompact(
              controller: _phoneController,
              label: 'Phone Number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Please enter Phone Number' : null,
            ),
            sectionGap,

            if (!isStudent)
              _buildTextFieldCompact(
                controller: _licenseController,
                label: 'Instructor License Number',
                icon: Icons.card_membership_outlined,
                validator: (v) {
                  if (!isStudent && (v == null || v.trim().isEmpty)) {
                    return 'License Number is required for Instructors';
                  }
                  return null;
                },
              ),
            if (!isStudent) fieldGap,
            if (!isStudent)
              _buildTextFieldCompact(
                controller: _experienceController,
                label: 'Years of Experience',
                icon: Icons.work_outline_rounded,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (!isStudent) {
                    final n = int.tryParse(v?.trim() ?? '');
                    if (n == null || n < 0) return 'Enter a valid number';
                  }
                  return null;
                },
              ),
            if (!isStudent) sectionGap,

            _buildPasswordFieldCompact(
              controller: _passwordController,
              label: 'Password',
              obscureText: obscurePassword,
              onToggle: () =>
                  setState(() => obscurePassword = !obscurePassword),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter Password';
                if (v.length < 8) {
                  return 'Password must be at least 8 characters';
                }
                return null;
              },
            ),
            fieldGap,
            _buildPasswordFieldCompact(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              obscureText: obscureConfirmPassword,
              onToggle: () => setState(
                  () => obscureConfirmPassword = !obscureConfirmPassword),
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Please confirm your password';
                }
                if (v != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            sectionGap,

            _buildTermsAndConditionsCompact(),
            const SizedBox(height: 12),
            _buildRegisterButtonCompact(),

            // Inline "Already have an account?"
            TextButton(
              onPressed: _navigateBack,
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.85), fontSize: 12),
                  children: const [
                    TextSpan(text: "Already have an account? "),
                    TextSpan(
                      text: 'Sign In',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTypeToggleCompact() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => isStudent = true);
                _cardController..reset()..forward();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isStudent
                      ? Colors.white.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.school_rounded, color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Student',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => isStudent = false);
                _cardController..reset()..forward();
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !isStudent
                      ? Colors.white.withOpacity(0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.person_outline_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text('Instructor',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextFieldCompact({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          prefixIcon:
              Icon(icon, color: Colors.white.withOpacity(0.7), size: 18),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        validator: validator ??
            (value) {
              if (value == null || value.isEmpty) return 'Please enter $label';
              if (label == 'Email Address' &&
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch(value.trim())) {
                return 'Please enter a valid email address';
              }
              return null;
            },
      ),
    );
  }

  Widget _buildPasswordFieldCompact({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle:
              TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13),
          prefixIcon: Icon(Icons.lock_outline,
              color: Colors.white.withOpacity(0.7), size: 18),
          suffixIcon: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              obscureText ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Colors.white.withOpacity(0.7),
            ),
            onPressed: onToggle,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
        validator: validator ??
            (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter $label';
              }
              if (value.length < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
      ),
    );
  }

  Widget _buildTermsAndConditionsCompact() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 18,
          width: 18,
          child: Checkbox(
            value: agreeToTerms,
            onChanged: (value) => setState(() => agreeToTerms = value ?? false),
            fillColor:
                MaterialStateProperty.all(Colors.white.withOpacity(0.85)),
            checkColor: const Color(0xFF6366F1),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => agreeToTerms = !agreeToTerms),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    color: Colors.white.withOpacity(0.85), fontSize: 12),
                children: const [
                  TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      
                    ),
                  ),
                  TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRegisterButtonCompact() {
    return SizedBox(
      height: 48,
      
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleRegister,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.92),
          foregroundColor: const Color(0xFF6366F1),
          elevation: 7,
          shadowColor: Colors.black.withOpacity(0.28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('Create Account',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  SizedBox(width: 6),
                  Icon(Icons.person_add_rounded, size: 18),
                ],
              ),
      ),
    );
  }

  // Toast-like snack
  void _showToast(String msg, {bool success = false}) {
    final bg = Colors.white;
    final txtColor = Colors.black87;
    final iconColor = success ? Colors.green : Colors.pink;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: iconColor,
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  success ? Icons.check : Icons.close,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  msg,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: txtColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===== Animated multi-blob gradient painter (shared) =====
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

    // Moving centers
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

    // Gradient blobs
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
