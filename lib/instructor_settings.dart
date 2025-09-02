// lib/instructor_settings.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

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
  final fullName = TextEditingController();   // from users/{uid}.name
  final emailCtrl = TextEditingController();  // display current email (auth / mirror)
  final phone = TextEditingController();      // from users/{uid}.phone
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
      final profDoc = await _db.collection('instructor_profiles').doc(user.uid).get();
      final data = profDoc.data() ?? {};

      final ts = data['dob'];
      if (ts is Timestamp) dob = ts.toDate();

      street.text = (data['address']?['street'] ?? '').toString();
      city.text   = (data['address']?['city'] ?? '').toString();
      state.text  = (data['address']?['state'] ?? '').toString();
      zip.text    = (data['address']?['zip'] ?? '').toString();
      country.text= (data['address']?['country'] ?? '').toString();

      _paymentMethod = (data['payment']?['method'] ?? 'bank').toString();
      bankName.text      = (data['payment']?['bank']?['bankName'] ?? '').toString();
      accountHolder.text = (data['payment']?['bank']?['accountHolder'] ?? '').toString();
      accountNumber.text = (data['payment']?['bank']?['accountNumber'] ?? '').toString();
      routingNumber.text = (data['payment']?['bank']?['routingNumber'] ?? '').toString();
      branch.text        = (data['payment']?['bank']?['branch'] ?? '').toString();
      upiId.text         = (data['payment']?['upi']?['id'] ?? '').toString();
    } catch (e) {
      _showSnack('Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      fullName, emailCtrl, phone, street, city, state, zip, country,
      bankName, accountHolder, accountNumber, routingNumber, branch, upiId
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

    final pwd = await _promptPassword(context, title: 'Re-authenticate', label: 'Current Password');
    if (pwd == null || pwd.isEmpty) return;

    try {
      final cred = EmailAuthProvider.credential(email: _initialEmail ?? (user.email ?? ''), password: pwd);
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

    final current = await _promptPassword(context, title: 'Re-authenticate', label: 'Current Password');
    if (current == null || current.isEmpty) return;

    final newPwd = await _promptPassword(context, title: 'New Password', label: 'New Password');
    if (newPwd == null || newPwd.length < 6) {
      _showSnack('Password must be at least 6 characters.');
      return;
    }

    try {
      final cred = EmailAuthProvider.credential(email: _initialEmail ?? (user.email ?? ''), password: current);
      await user.reauthenticateWithCredential(cred);

      // ^5.x uses named, ^4.x supports positional (named also works in recent versions)
      await user.updatePassword(newPwd);

      _showSnack('Password updated.');
    } on FirebaseAuthException catch (e) {
      _showSnack(e.message ?? 'Failed to change password.');
    } catch (e) {
      _showSnack('Failed to change password: $e');
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) Navigator.of(context).pop();
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

    final pwd = await _promptPassword(context, title: 'Confirm Deletion', label: 'Current Password');
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
    final theme = Theme.of(context);
    final width = MediaQuery.of(context).size.width;
    final isNarrow = width < 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Instructor Settings'),
        centerTitle: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionHeader(theme, 'Account Settings', icon: Icons.manage_accounts_outlined),
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
                                  decoration: const InputDecoration(
                                    hintText: 'name@example.com',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _changeEmail,
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
                              const Expanded(
                                child: Text('********',
                                    style: TextStyle(letterSpacing: 4, color: Colors.black54)),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: _changePassword,
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
                              theme,
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
                                          validator: (v) => v!.isEmpty ? 'Phone is required' : null),
                                      _dateField(context, 'Date of Birth', dob, (d) => setState(() => dob = d)),
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
                  _sectionHeader(theme, 'Payment Preferences',
                      icon: Icons.account_balance_wallet_outlined,
                      trailing: _saveBtn(_savingPayments, _savePayments)),
                  _card(
                    child: Form(
                      key: _paymentKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Preferred Payment Method', style: theme.textTheme.bodyMedium),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ChoiceChip(
                                label: const Text('Bank Transfer'),
                                selected: _paymentMethod == 'bank',
                                onSelected: (_) => setState(() => _paymentMethod = 'bank'),
                              ),
                              ChoiceChip(
                                label: const Text('UPI'),
                                selected: _paymentMethod == 'upi',
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
                  _sectionHeader(theme, 'Account Actions', icon: Icons.warning_amber_outlined),
                  _card(
                    color: Colors.amber.shade50,
                    child: Row(
                      children: [
                        const Icon(Icons.logout, color: Colors.amber),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Logout\nSign out of your account on this device.'),
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
                    color: Colors.red.shade50,
                    child: Row(
                      children: [
                        const Icon(Icons.delete_forever, color: Colors.red),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Delete Account\nPermanently delete your account and all data.'),
                        ),
                        FilledButton(
                          onPressed: _deleteAccount,
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  Widget _sectionHeader(ThemeData theme, String title,
      {IconData? icon, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (icon != null) Icon(icon, size: 20, color: theme.colorScheme.primary),
          if (icon != null) const SizedBox(width: 8),
          Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
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
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        boxShadow: const [BoxShadow(blurRadius: 10, color: Color(0x11000000), offset: Offset(0, 4))],
      ),
      child: child,
    );
  }

  Widget _labeled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
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
        border: const OutlineInputBorder(),
        isDense: true,
      ),
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

  Widget _dateField(
      BuildContext context, String label, DateTime? value, ValueChanged<DateTime?> onChanged) {
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
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Text(text.isEmpty ? 'Tap to select' : text),
      ),
    );
  }

  Widget _fieldset(String title, {required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _saveBtn(bool loading, VoidCallback onPressed) {
    return FilledButton.tonalIcon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.save_outlined),
      label: const Text('Save Changes'),
    );
  }

  Widget _primarySaveButton(
      {required String label, required bool loading, required VoidCallback onPressed}) {
    return FilledButton.icon(
      onPressed: loading ? null : onPressed,
      icon: loading
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_circle_outline),
      label: Text(label),
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
        title: Text(title),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
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
