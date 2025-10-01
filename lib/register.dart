// lib/register_screen.dart
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'reusables/branding.dart'; // AppBrand, AppBrandingRow

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
  late final Animation<double> _cardScale;
  late final Animation<Offset> _cardSlide;

  bool isStudent = true;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool agreeToTerms = false;
  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _licenseController = TextEditingController();
  final _experienceController = TextEditingController();

  // Focus nodes
  final _nameNode = FocusNode();
  final _emailNode = FocusNode();
  final _phoneNode = FocusNode();
  final _licenseNode = FocusNode();
  final _expNode = FocusNode();
  final _passNode = FocusNode();
  final _confirmNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    _cardController = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );

    _cardScale = CurvedAnimation(
      parent: _cardController,
      curve: Curves.easeOutBack,
    );

    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.16),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
    );

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

    _nameNode.dispose();
    _emailNode.dispose();
    _phoneNode.dispose();
    _licenseNode.dispose();
    _expNode.dispose();
    _passNode.dispose();
    _confirmNode.dispose();

    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // Actions
  // ────────────────────────────────────────────────────────────────────────────

  Future<void> _handleRegister() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;
    if (!agreeToTerms) {
      _toast('Please agree to the Terms of Service and Privacy Policy.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _registerWithFirebase();

      if (!mounted) return;
      setState(() => _isLoading = false);

      _toast(
        'Your ${isStudent ? 'student' : 'instructor'} account has been created. Welcome to ${AppBrand.appName}!',
        success: true,
      );

      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _toast(_friendlyAuthError(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _toast('Registration failed. ${e.toString()}');
    }
  }

  /// Register user, create users doc and optionally user_plans.
  /// This version allocates a concurrency-safe enrolment number of the form
  /// "<seq>/<year>" by using a Firestore transaction on `settings/app_settings`.
  /// It also creates an admin_notifications entry and increments an unread counter.
  Future<void> _registerWithFirebase() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    final displayName = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final role = isStudent ? 'student' : 'instructor';

    // 1) Create auth user
    final cred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(email: email, password: password);

    await cred.user?.updateDisplayName(displayName);
    final uid = cred.user!.uid;

    // 2) Allocate enrolment number in a transaction
    final settingsRef =
        FirebaseFirestore.instance.collection('settings').doc('app_settings');

    final now = DateTime.now();
    final currentYear = now.year;

    final enrolmentResult =
        await FirebaseFirestore.instance.runTransaction<Map<String, dynamic>>(
            (tx) async {
      final snap = await tx.get(settingsRef);

      int lastYear = 0;
      int lastSeq = 0;

      if (snap.exists) {
        final data = snap.data()!;
        lastYear = (data['last_enrolment_year'] is int)
            ? data['last_enrolment_year'] as int
            : (data['last_enrolment_year'] is String
                ? int.tryParse(data['last_enrolment_year']) ?? 0
                : 0);
        lastSeq = (data['last_enrolment_seq'] is int)
            ? data['last_enrolment_seq'] as int
            : (data['last_enrolment_seq'] is String
                ? int.tryParse(data['last_enrolment_seq']) ?? 0
                : 0);
      }

      // NEW: Do NOT reset sequence at new year. Always increment the global sequence.
      int nextSeq = lastSeq + 1;
      if (nextSeq <= 0) nextSeq = 1; // safety

      tx.set(settingsRef, {
        'last_enrolment_year': currentYear,
        'last_enrolment_seq': nextSeq,
        'last_enrolment_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return {
        'year': currentYear,
        'seq': nextSeq,
      };
    });

    final seq = enrolmentResult['seq'] as int;
    final year = enrolmentResult['year'] as int;
    final enrolmentNumber = '$seq/$year';

    // 3) Create/merge user profile document with enrolment_number
    final data = <String, dynamic>{
      'uid': uid,
      'email': email,
      'name': displayName,
      'phone': phone,
      'role': role,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'enrolment_number': enrolmentNumber,
      if (!isStudent) 'licenseNo': _licenseController.text.trim(),
      if (!isStudent)
        'yearsExp': int.tryParse(_experienceController.text.trim()) ?? 0,
    };

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set(data, SetOptions(merge: true));

    // 4) If student, also create a user_plans record
    if (isStudent) {
      final planDoc = <String, dynamic>{
        'userId': uid,
        'planId': 'pay-per-use',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('user_plans')
          .doc(uid)
          .set(planDoc, SetOptions(merge: true));
    }

    // -------------------------
    // 5) Create admin notification + increment unread counter (batched)
    // -------------------------
    final notifColl =
        FirebaseFirestore.instance.collection('admin_notifications');
    final newNotifRef = notifColl.doc(); // auto-id

    final notifType =
        isStudent ? 'new_student_registration' : 'new_instructor_registration';
    final title =
        isStudent ? 'New student registration' : 'New instructor registration';
    final message = isStudent
        ? '$displayName registered as a student.'
        : '$displayName applied as an instructor.';

    final notifPayload = <String, dynamic>{
      'type': notifType,
      'title': title,
      'message': message,
      'userId': uid,
      'userName': displayName,
      'userEmail': email,
      'userPhone': phone,
      'enrolment_number': enrolmentNumber,
      'role': role,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      // optional: useful to quickly route admin UI to the user
      'userDocPath': userRef.path,
      // you can add more metadata like 'source': 'mobile_app' etc.
    };

    // Use a batch so the notification and unread counter update happen together.
    final batch = FirebaseFirestore.instance.batch();
    batch.set(newNotifRef, notifPayload);

    // Increment a simple unread counter in settings/app_settings (create if missing)
    batch.set(settingsRef, {
      'admin_unread_notifications': FieldValue.increment(1),
      'last_notification_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await batch.commit();

    // Done
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

  // ────────────────────────────────────────────────────────────────────────────
  // UI
  // ────────────────────────────────────────────────────────────────────────────

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
                  colors: [Colors.transparent, Colors.black.withOpacity(0.06)],
                  stops: const [0.7, 1.0],
                ),
              ),
            ),
          ),

          // Layout with back button, branding outside, and form card
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Stack(
                children: [
                  // Back button
                  Positioned(
                    top: 8,
                    left: 0,
                    child: IconButton(
                      onPressed: _navigateBack,
                      padding: const EdgeInsets.all(6),
                      constraints:
                          const BoxConstraints(minWidth: 36, minHeight: 36),
                      iconSize: 18,
                      icon: const Icon(
                        Icons.arrow_back_ios_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Back',
                    ),
                  ),

                  // Branding (outside)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        SizedBox(height: 8),
                        AppBrandingRow(
                          logoSize: 42,
                          nameSize: 22,
                          spacing: 10,
                          textColor: Colors.white,
                        ),
                      ],
                    ),
                  ),

                  // Card
                  Align(
                    alignment: Alignment.center,
                    child: SlideTransition(
                      position: _cardSlide,
                      child: ScaleTransition(
                        scale: _cardScale,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _GlassCard(child: _buildRegisterCard()),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterCard() {
  const fieldGap = SizedBox(height: 12);
  const sectionGap = SizedBox(height: 14);

  // Limit the height of the card so the scroll view has a sensible viewport.
  final maxCardHeight = MediaQuery.of(context).size.height * 0.78;
  final bottomInset = MediaQuery.of(context).viewInsets.bottom + 14; // safe bottom padding for keyboard

  return ConstrainedBox(
    constraints: BoxConstraints(maxHeight: maxCardHeight),
    child: SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(bottom: bottomInset, left: 2, right: 2, top: 2),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.disabled,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Subtitle
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                key: ValueKey(isStudent),
                isStudent
                    ? 'Create your student account'
                    : 'Apply as an instructor',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 18),

            _buildUserTypeToggle(),
            sectionGap,

            // Full name
            _buildTextField(
              controller: _nameController,
              focusNode: _nameNode,
              nextNode: _emailNode,
              label: 'Full Name',
              icon: Icons.person_outline_rounded,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Please enter Full Name';
                if (t.length < 2) return 'Name looks too short';
                return null;
              },
              autofillHints: const [AutofillHints.name],
            ),
            fieldGap,

            // Email
            _buildTextField(
              controller: _emailController,
              focusNode: _emailNode,
              nextNode: _phoneNode,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) {
                final email = v?.trim() ?? '';
                if (email.isEmpty) return 'Please enter Email Address';
                final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                    .hasMatch(email.toLowerCase());
                return ok ? null : 'Please enter a valid email address';
              },
              autofillHints: const [AutofillHints.email],
            ),
            fieldGap,

            // Phone
            _buildTextField(
              controller: _phoneController,
              focusNode: _phoneNode,
              nextNode: isStudent ? _passNode : _licenseNode,
              label: 'Phone Number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]'))
              ],
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return 'Please enter Phone Number';
                if (t.replaceAll(RegExp(r'\D'), '').length < 7) {
                  return 'Enter a valid phone number';
                }
                return null;
              },
              autofillHints: const [AutofillHints.telephoneNumber],
            ),
            sectionGap,

            // Instructor-only fields
            if (!isStudent)
              _buildTextField(
                controller: _licenseController,
                focusNode: _licenseNode,
                nextNode: _expNode,
                label: 'Instructor License Number',
                icon: Icons.card_membership_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) {
                    return 'License Number is required for Instructors';
                  }
                  return null;
                },
              ),
            if (!isStudent) fieldGap,

            if (!isStudent)
              _buildTextField(
                controller: _experienceController,
                focusNode: _expNode,
                nextNode: _passNode,
                label: 'Years of Experience',
                icon: Icons.work_outline_rounded,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  final n = int.tryParse(v?.trim() ?? '');
                  if (n == null || n < 0) return 'Enter a valid number';
                  return null;
                },
              ),
            if (!isStudent) sectionGap,

            // Password
            _buildPasswordField(
              controller: _passwordController,
              focusNode: _passNode,
              nextNode: _confirmNode,
              label: 'Password',
              obscureText: obscurePassword,
              onToggle: () => setState(() => obscurePassword = !obscurePassword),
              textInputAction: TextInputAction.next,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter Password';
                if (v.length < 8) return 'Password must be at least 8 characters';
                return null;
              },
              autofillHints: const [AutofillHints.newPassword],
            ),
            fieldGap,

            // Confirm Password
            _buildPasswordField(
              controller: _confirmPasswordController,
              focusNode: _confirmNode,
              label: 'Confirm Password',
              obscureText: obscureConfirmPassword,
              onToggle: () =>
                  setState(() => obscureConfirmPassword = !obscureConfirmPassword),
              textInputAction: TextInputAction.done,
              validator: (v) {
                if (v == null || v.isEmpty) {
                  return 'Please confirm your password';
                }
                if (v != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
              onFieldSubmitted: (_) => _handleRegister(),
              autofillHints: const [AutofillHints.newPassword],
            ),
            sectionGap,

            _buildTermsAndConditions(),
            const SizedBox(height: 14),
            _buildRegisterButton(),

            // Inline "Already have an account?"
            TextButton(
              onPressed: _navigateBack,
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12.5,
                  ),
                  children: const [
                    TextSpan(text: "Already have an account? "),
                    TextSpan(
                      text: 'Sign In',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Extra bottom spacing so the last button isn't glued to the bottom on small screens
            SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}


  // ── UI atoms (cleaned)
  Widget _buildUserTypeToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Row(
        children: [
          _togglePill(
            active: isStudent,
            icon: Icons.school_rounded,
            label: 'Student',
            onTap: () {
              if (!isStudent) {
                setState(() => isStudent = true);
                _cardController
                  ..reset()
                  ..forward();
              }
            },
          ),
          const SizedBox(width: 6),
          _togglePill(
            active: !isStudent,
            icon: Icons.person_outline_rounded,
            label: 'Instructor',
            onTap: () {
              if (isStudent) {
                setState(() => isStudent = false);
                _cardController
                  ..reset()
                  ..forward();
              }
            },
          ),
        ],
      ),
    );
  }

  Expanded _togglePill({
    required bool active,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 18),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    FocusNode? nextNode,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    List<String>? autofillHints,
  }) {
    return _FieldShell(
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onFieldSubmitted: (_) {
          if (nextNode != null) FocusScope.of(context).requestFocus(nextNode);
        },
        autofillHints: autofillHints,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        inputFormatters: inputFormatters,
        decoration: _decoration(label, icon),
        validator: validator ??
            (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter $label';
              }
              if (label == 'Email Address' &&
                  !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                      .hasMatch(value.trim().toLowerCase())) {
                return 'Please enter a valid email address';
              }
              return null;
            },
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool obscureText,
    required VoidCallback onToggle,
    FocusNode? focusNode,
    FocusNode? nextNode,
    TextInputAction textInputAction = TextInputAction.next,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
    List<String>? autofillHints,
  }) {
    return _FieldShell(
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscureText,
        textInputAction: textInputAction,
        onFieldSubmitted: (s) {
          if (onFieldSubmitted != null) {
            onFieldSubmitted(s);
            return;
          }
          if (nextNode != null) {
            FocusScope.of(context).requestFocus(nextNode);
          }
        },
        autofillHints: autofillHints,
        style: const TextStyle(color: Colors.white, fontSize: 13.5),
        decoration: _decoration(label, Icons.lock_outline).copyWith(
          suffixIcon: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              obscureText ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: Colors.white.withOpacity(0.75),
            ),
            onPressed: onToggle,
            tooltip: obscureText ? 'Show password' : 'Hide password',
          ),
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

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle:
          TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13.5),
      prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
      border: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      errorStyle: const TextStyle(fontSize: 11.5, height: 1.2),
    );
  }

  Widget _buildTermsAndConditions() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: 18,
          width: 18,
          child: Checkbox(
            value: agreeToTerms,
            onChanged: _isLoading
                ? null
                : (value) => setState(() => agreeToTerms = value ?? false),
            fillColor:
                WidgetStateProperty.all(Colors.white.withOpacity(0.95)),
            checkColor: const Color(0xFF4C63D2),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _isLoading
                ? null
                : () => setState(() => agreeToTerms = !agreeToTerms),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 12.5,
                ),
                children: const [
                  TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
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

  Widget _buildRegisterButton() {
    final canSubmit = !_isLoading && agreeToTerms;

    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: canSubmit ? _handleRegister : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: canSubmit
              ? Colors.white.withOpacity(0.98)
              : Colors.white.withOpacity(0.55),
          foregroundColor: const Color(0xFF0F172A),
          elevation: canSubmit ? 10 : 0,
          shadowColor: Colors.black.withOpacity(0.28),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _isLoading
              ? const SizedBox(
                  key: ValueKey('spinner'),
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'Create Account',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.person_add_rounded, size: 18),
                  ],
                ),
        ),
      ),
    );
  }

  // Toast-like snack
  void _toast(String msg, {bool success = false}) {
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
                color: Colors.black.withOpacity(0.12),
                blurRadius: 10,
                offset: const Offset(0, 6),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: txtColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
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

// ─────────────────────────────────────────────────────────────────────────────
// Frosted glass card wrapper (cleaner visual than raw container)
// ─────────────────────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Field shell to keep height flexible for errors while preserving look
// ─────────────────────────────────────────────────────────────────────────────
class _FieldShell extends StatelessWidget {
  const _FieldShell({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      // No fixed height: lets error text breathe
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.20), width: 1),
      ),
      padding: const EdgeInsets.only(left: 0, right: 0), // input has padding
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Animated multi-blob gradient painter
// ─────────────────────────────────────────────────────────────────────────────
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
