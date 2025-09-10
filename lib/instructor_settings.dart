// lib/instructor_settings.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/session_service.dart';
import 'login.dart';
import 'messaging_setup.dart';

// Import your design tokens & theme helpers — adjust the package path if needed
import 'theme/app_theme.dart';

class InstructorSettingsPage extends StatefulWidget {
  const InstructorSettingsPage({super.key});
  @override
  State<InstructorSettingsPage> createState() => _InstructorSettingsPageState();
}

class _InstructorSettingsPageState extends State<InstructorSettingsPage> {
  // Firebase
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  // Loading / saving states
  bool _loading = true;
  bool _savingPersonal = false;
  bool _savingPayments = false;

  // Controllers — Personal Information
  final fullName = TextEditingController(); // from users/{uid}.name
  final emailCtrl = TextEditingController(); // display current email (auth / mirror)
  final phone = TextEditingController(); // from users/{uid}.phone
  DateTime? dob; // date of birth (instructor_profiles)
  final street = TextEditingController();
  final city = TextEditingController();
  final state = TextEditingController();
  final zip = TextEditingController();
  final country = TextEditingController();

  // Payment preference
  String _paymentMethod = 'bank'; // 'bank' | 'upi'
  // Bank details
  final bankName = TextEditingController();
  final accountHolder = TextEditingController();
  final accountNumber = TextEditingController();
  final routingNumber = TextEditingController(); // or IFSC
  final branch = TextEditingController();
  // UPI
  final upiId = TextEditingController();

  // Validators
  final _personalKey = GlobalKey<FormState>();
  final _paymentKey = GlobalKey<FormState>();

  // Helpers
  String get _uid => _auth.currentUser!.uid;
  String? _initialEmail;

  @override
  void initState() {
    super.initState();
    _initLoad();
  }

  Future<void> _initLoad() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        _showSnack('You are not signed in.');
        if (mounted) Navigator.of(context).pop();
        return;
      }
      emailCtrl.text = user.email ?? '';
      _initialEmail = user.email;

      // 1) Load from users/{uid}: name (full name) and phone
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      fullName.text = (userData['name'] ?? '').toString();
      phone.text = (userData['phone'] ?? '').toString();

      // 2) Load from instructor_profiles/{uid}: address/dob/payment/etc.
      final profDoc =
          await _db.collection('instructor_profiles').doc(user.uid).get();
      final data = profDoc.data() ?? {};

      final ts = data['dob'];
      if (ts is Timestamp) dob = ts.toDate();

      street.text = (data['address']?['street'] ?? '').toString();
      city.text = (data['address']?['city'] ?? '').toString();
      state.text = (data['address']?['state'] ?? '').toString();
      zip.text = (data['address']?['zip'] ?? '').toString();
      country.text = (data['address']?['country'] ?? '').toString();

      _paymentMethod = (data['payment']?['method'] ?? 'bank').toString();
      bankName.text =
          (data['payment']?['bank']?['bankName'] ?? '').toString();
      accountHolder.text =
          (data['payment']?['bank']?['accountHolder'] ?? '').toString();
      accountNumber.text =
          (data['payment']?['bank']?['accountNumber'] ?? '').toString();
      routingNumber.text =
          (data['payment']?['bank']?['routingNumber'] ?? '').toString();
      branch.text = (data['payment']?['bank']?['branch'] ?? '').toString();
      upiId.text = (data['payment']?['upi']?['id'] ?? '').toString();
    } catch (e) {
      _showSnack('Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      fullName,
      emailCtrl,
      phone,
      street,
      city,
      state,
      zip,
      country,
      bankName,
      accountHolder,
      accountNumber,
      routingNumber,
      branch,
      upiId
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ───────────────────────── Account actions ─────────────────────────

  Future<void> _changeEmail() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final newEmail = emailCtrl.text.trim();

    if (newEmail.isEmpty || newEmail == _initialEmail) {
      _showSnack('No email change detected.');
      return;
    }

    final pwd = await _promptPassword(context,
        title: 'Re-authenticate', label: 'Current Password');
    if (pwd == null || pwd.isEmpty) return;

    try {
      final cred = EmailAuthProvider.credential(
          email: _initialEmail ?? (user.email ?? ''), password: pwd);
      await user.reauthenticateWithCredential(cred);

      // Verification-first flow
      await user.verifyBeforeUpdateEmail(newEmail);
      _showSnack('Verification email sent to $newEmail. Verify to complete email update.');

      // Optional mirror in instructor_profiles
      await _db.collection('instructor_profiles').doc(_uid).set({
        'email': newEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      setState(() => _initialEmail = newEmail);
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Failed to change email.');
    } catch (e) {
      _showSnack('Failed to change email: $e');
    }
  }

  Future<void> _changePassword() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final current = await _promptPassword(context,
        title: 'Re-authenticate', label: 'Current Password');
    if (current == null || current.isEmpty) return;

    final newPwd = await _promptPassword(context,
        title: 'New Password', label: 'New Password');
    if (newPwd == null || newPwd.length < 6) {
      _showSnack('Password must be at least 6 characters.');
      return;
    }

    try {
      final cred = EmailAuthProvider.credential(
          email: _initialEmail ?? (user.email ?? ''), password: current);
      await user.reauthenticateWithCredential(cred);

      await user.updatePassword(newPwd);

      _showSnack('Password updated.');
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Failed to change password.');
    } catch (e) {
      _showSnack('Failed to change password: $e');
    }
  }

  Future<void> _logout({bool wipeAllPrefs = false}) async {
    try {
      // Optional: stop role/status topic notifications if you use them
      try {
        await unsubscribeRoleStatusTopics(alsoAll: false);
      } catch (_) {}

      // Clear saved session keys (userId/role/status)
      await SessionService().clear();

      // Clear remember-me so auto-redirect won’t happen next launch
      final sp = await SharedPreferences.getInstance();
      await sp.remove('sd_saved_email');
      await sp.setBool('sd_remember_me', false);

      // (Optional) hard wipe: nukes all SharedPreferences
      if (wipeAllPrefs) {
        await sp.clear();
      }

      // Firebase sign out
      await _auth.signOut();

      // Go to Login, clear back stack
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      _showSnack('Error logging out: $e');
    }
  }

  Future<void> _deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final confirm = await _confirmDialog(
      context,
      title: 'Delete Account',
      message: 'This will permanently delete your account and profile data.',
      confirmText: 'Delete',
      danger: true,
    );
    if (confirm != true) return;

    final pwd = await _promptPassword(context,
        title: 'Confirm Deletion', label: 'Current Password');
    if (pwd == null || pwd.isEmpty) return;

    try {
      final email = user.email ?? _initialEmail ?? '';
      final cred = EmailAuthProvider.credential(email: email, password: pwd);
      await user.reauthenticateWithCredential(cred);

      await _db.collection('instructor_profiles').doc(_uid).delete();
      await user.delete();
      _showSnack('Account deleted.');
      if (mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Failed to delete account.');
    } catch (e) {
      _showSnack('Failed to delete account: $e');
    }
  }

  // ───────────────────────── Save sections ─────────────────────────

  Future<void> _savePersonal() async {
    if (!(_personalKey.currentState?.validate() ?? false)) return;

    setState(() => _savingPersonal = true);
    try {
      // 1) Update users/{uid} with full name & phone
      await _db.collection('users').doc(_uid).set({
        'name': fullName.text.trim(),
        'phone': phone.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 2) Update instructor_profiles/{uid} with dob + address (+ optional mirror email)
      await _db.collection('instructor_profiles').doc(_uid).set({
        'email': emailCtrl.text.trim(),
        'dob': dob == null ? null : Timestamp.fromDate(dob!),
        'address': {
          'street': street.text.trim(),
          'city': city.text.trim(),
          'state': state.text.trim(),
          'zip': zip.text.trim(),
          'country': country.text.trim(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _showSnack('Personal information saved.');
    } catch (e) {
      _showSnack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _savingPersonal = false);
    }
  }

  Future<void> _savePayments() async {
    if (!(_paymentKey.currentState?.validate() ?? false)) return;

    setState(() => _savingPayments = true);
    try {
      await _db.collection('instructor_profiles').doc(_uid).set({
        'payment': {
          'method': _paymentMethod,
          'bank': {
            'bankName': bankName.text.trim(),
            'accountHolder': accountHolder.text.trim(),
            'accountNumber': accountNumber.text.trim(),
            'routingNumber': routingNumber.text.trim(),
            'branch': branch.text.trim(),
          },
          'upi': {
            'id': upiId.text.trim(),
          },
        },
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _showSnack('Payment preferences saved.');
    } catch (e) {
      _showSnack('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _savingPayments = false);
    }
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 720;

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        title: Text('Instructor Settings', style: AppText.sectionTitle.copyWith(color: context.c.onSurface)),
        centerTitle: false,
        backgroundColor: context.c.surface,
        foregroundColor: context.c.onSurface,
        elevation: 0,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.c.primary),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(context, 'Account Settings',
                      icon: Icons.manage_accounts_outlined),
                  _card(
                    child: Column(
                      children: [
                        _labeled(
                          'Email Address',
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    hintText: 'name@example.com',
                                    filled: true,
                                    fillColor: context.c.surface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _changeEmail,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.c.primary,
                                  foregroundColor: context.c.onPrimary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadii.s)),
                                ),
                                child: const Text('Change Email'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        _labeled(
                          'Password',
                          Row(
                            children: [
                              Expanded(
                                child: Text('********',
                                    style: context.t.bodyMedium?.copyWith(
                                        letterSpacing: 4,
                                        color: AppColors.onSurfaceMuted)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _changePassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.c.primary,
                                  foregroundColor: context.c.onPrimary,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(AppRadii.s)),
                                ),
                                child: const Text('Change Password'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            _sectionHeader(
                              context,
                              'Personal Information',
                              icon: Icons.person_outline,
                              trailing: _saveBtn(_savingPersonal, _savePersonal),
                            ),
                            _card(
                              child: Form(
                                key: _personalKey,
                                child: Column(
                                  children: [
                                    _text('Full Name', fullName, required: true),
                                    const SizedBox(height: 12),
                                    _twoCols(
                                      isNarrow,
                                      _text('Phone Number', phone,
                                          keyboardType: TextInputType.phone,
                                          validator: (v) => v!.isEmpty
                                              ? 'Phone is required'
                                              : null),
                                      _dateField(context, 'Date of Birth', dob,
                                          (d) => setState(() => dob = d)),
                                    ),
                                    const SizedBox(height: 12),
                                    _text('Street Address', street),
                                    const SizedBox(height: 12),
                                    _twoCols(
                                      isNarrow,
                                      _text('City', city),
                                      _text('State', state),
                                    ),
                                    const SizedBox(height: 12),
                                    _twoCols(
                                      isNarrow,
                                      _text('ZIP Code', zip),
                                      _text('Country', country),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _primarySaveButton(
                      label: 'Save Changes',
                      loading: _savingPersonal,
                      onPressed: _savePersonal,
                    ),
                  ),

                  const SizedBox(height: 24),
                  _sectionHeader(context, 'Payment Preferences',
                      icon: Icons.account_balance_wallet_outlined,
                      trailing: _saveBtn(_savingPayments, _savePayments)),
                  _card(
                    child: Form(
                      key: _paymentKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Preferred Payment Method',
                              style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ChoiceChip(
                                label: const Text('Bank Transfer'),
                                selected: _paymentMethod == 'bank',
                                selectedColor: context.c.primary.withOpacity(0.12),
                                backgroundColor: context.c.surface,
                                labelStyle: TextStyle(
                                    color: _paymentMethod == 'bank'
                                        ? context.c.primary
                                        : AppColors.onSurfaceMuted),
                                onSelected: (_) => setState(() => _paymentMethod = 'bank'),
                              ),
                              ChoiceChip(
                                label: const Text('UPI'),
                                selected: _paymentMethod == 'upi',
                                selectedColor: context.c.primary.withOpacity(0.12),
                                backgroundColor: context.c.surface,
                                labelStyle: TextStyle(
                                    color: _paymentMethod == 'upi'
                                        ? context.c.primary
                                        : AppColors.onSurfaceMuted),
                                onSelected: (_) => setState(() => _paymentMethod = 'upi'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_paymentMethod == 'bank') ...[
                            _fieldset(
                              'Bank Details',
                              children: [
                                _text('Bank Name', bankName, required: true),
                                const SizedBox(height: 12),
                                _text('Account Holder Name', accountHolder, required: true),
                                const SizedBox(height: 12),
                                _twoCols(
                                  isNarrow,
                                  _text('Account Number', accountNumber,
                                      keyboardType: TextInputType.number, required: true),
                                  _text('Routing/IFSC', routingNumber, required: true),
                                ),
                                const SizedBox(height: 12),
                                _text('Branch', branch),
                              ],
                            ),
                          ] else ...[
                            _fieldset(
                              'UPI',
                              children: [
                                _text('UPI ID', upiId,
                                    required: true,
                                    validator: (v) {
                                      final s = (v ?? '').trim();
                                      if (s.isEmpty) return 'UPI ID is required';
                                      if (!s.contains('@')) return 'Enter a valid UPI ID';
                                      return null;
                                    }),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _primarySaveButton(
                      label: 'Save Changes',
                      loading: _savingPayments,
                      onPressed: _savePayments,
                    ),
                  ),

                  const SizedBox(height: 24),
                  _sectionHeader(context, 'Account Actions', icon: Icons.warning_amber_outlined),
                  _card(
                    color: AppColors.warnBg,
                    child: Row(
                      children: [
                        Icon(Icons.logout, color: AppColors.warning),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Logout\nSign out of your account on this device.',
                              style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
                        ),
                        FilledButton.tonal(
                          onPressed: _logout,
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _card(
                    color: AppColors.errBg,
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever, color: AppColors.danger),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('Delete Account\nPermanently delete your account and all data.',
                              style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
                        ),
                        FilledButton(
                          onPressed: _deleteAccount,
                          style:
                              FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: context.c.onPrimary),
                          child: const Text('Delete Account'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: null,
    );
  }

  // ───────────────────────── Widgets ─────────────────────────

  Widget _sectionHeader(BuildContext context, String title,
      {IconData? icon, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) Icon(icon, size: 20, color: context.c.primary),
          if (icon != null) const SizedBox(width: 8),
          Text(title,
              style: context.t.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.c.onSurface,
              )),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _card({required Widget child, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? context.c.surface,
        borderRadius: BorderRadius.circular(AppRadii.l),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }

  Widget _labeled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: context.t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600, color: context.c.onSurface)),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _text(
    String label,
    TextEditingController ctrl, {
    TextInputType keyboardType = TextInputType.text,
    bool required = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
        isDense: true,
        filled: true,
        fillColor: context.c.surface,
      ),
      style: context.t.bodyMedium?.copyWith(color: context.c.onSurface),
      validator: validator ??
          (required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
              : null),
    );
  }

  Widget _twoCols(bool isNarrow, Widget a, Widget b) {
    if (isNarrow) {
      return Column(
        children: [
          a,
          const SizedBox(height: 12),
          b,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }

  Widget _dateField(BuildContext context, String label, DateTime? value,
      ValueChanged<DateTime?> onChanged) {
    final text = value == null ? '' : DateFormat('dd-MMM-yyyy').format(value);
    return GestureDetector(
      onTap: () async {
        final now = DateTime.now();
        final initial = value ?? DateTime(now.year - 20, now.month, now.day);
        final picked = await showDatePicker(
          context: context,
          firstDate: DateTime(1930),
          lastDate: DateTime(now.year + 1),
          initialDate: initial,
        );
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
          isDense: true,
          filled: true,
          fillColor: context.c.surface,
        ),
        child: Text(text.isEmpty ? 'Tap to select' : text,
            style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
      ),
    );
  }

  Widget _fieldset(String title, {required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: context.t.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600, color: context.c.onSurface)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _saveBtn(bool loading, VoidCallback onPressed) {
    return FilledButton.tonalIcon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(context.c.primary),
              ),
            )
          : const Icon(Icons.save_outlined),
      label: const Text('Save Changes'),
    );
  }

  Widget _primarySaveButton(
      {required String label, required bool loading, required VoidCallback onPressed}) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(context.c.onPrimary)),
            )
          : const Icon(Icons.check_circle_outline),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: context.c.primary,
        foregroundColor: context.c.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
      ),
    );
  }

  // ───────────────────────── Dialog helpers / UX ─────────────────────────

  Future<String?> _promptPassword(BuildContext context,
      {required String title, required String label}) async {
    final ctrl = TextEditingController();
    String? result;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: context.t.titleMedium?.copyWith(color: context.c.onSurface)),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: context.c.primary))),
          FilledButton(
            onPressed: () {
              result = ctrl.text;
              Navigator.pop(context);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<bool?> _confirmDialog(BuildContext context,
      {required String title,
      required String message,
      String confirmText = 'OK',
      bool danger = false}) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, style: context.t.titleMedium?.copyWith(color: context.c.onSurface)),
        content: Text(message, style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: context.c.primary))),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: context.c.onPrimary)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
