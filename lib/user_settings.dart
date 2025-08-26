import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart'; // your login screen

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => _UserSettingsScreenState();
}

class _UserSettingsScreenState extends State<UserSettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Form key for input validation
  final _profileFormKey = GlobalKey<FormState>();

  User? currentUser;
  Map<String, dynamic>? userData;

  /// Resolved from `plans/{planId}`, includes 'id'
  Map<String, dynamic>? currentPlan;

  /// From `plans` collection, each with its 'id'
  List<Map<String, dynamic>> availablePlans = [];

  bool isLoading = true;

  // ---- Lifecycle ----
  @override
  void initState() {
    super.initState();
    currentUser = _auth.currentUser;
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ---- Data loading ----
  Future<void> _loadUserData() async {
    if (currentUser == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      // Load user profile
      final userDoc =
          await _firestore.collection('users').doc(currentUser!.uid).get();

      if (userDoc.exists) {
        final data = userDoc.data();
        if (data != null) {
          userData = data;
          _nameController.text = (data['name'] ?? '').toString();
          _emailController.text =
              (data['email'] ?? currentUser!.email ?? '').toString();
        }
      }

      // Load current plan (user_plans/{userId} → planId → plans/{planId})
      await _loadCurrentPlan();

      // Load available plans
      await _loadAvailablePlans();
    } catch (e) {
      _showErrorDialog('Error loading user data: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Single-doc schema: read from `user_plans/{userId}` and resolve planId.
  Future<void> _loadCurrentPlan() async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) {
        currentPlan = null;
        return;
      }

      final userPlanDoc =
          await _firestore.collection('user_plans').doc(uid).get();

      if (!userPlanDoc.exists) {
        currentPlan = null; // No plan doc created yet
        return;
      }

      final data = userPlanDoc.data() as Map<String, dynamic>;
      final planId = (data['planId'] ?? '').toString().trim();
      if (planId.isEmpty) {
        currentPlan = null;
        return;
      }

      final planDoc = await _firestore.collection('plans').doc(planId).get();
      if (!planDoc.exists || planDoc.data() == null) {
        currentPlan = null;
        return;
      }

      currentPlan = {'id': planDoc.id, ...planDoc.data()!};
    } catch (e) {
      // keep UI stable
      // ignore: avoid_print
      print('Error loading current plan: $e');
      currentPlan = null;
    }
  }

  /// Reads all plans; orders by price if present
  Future<void> _loadAvailablePlans() async {
    try {
      Query query = _firestore.collection('plans');

      // If you have an active flag, you can filter:
      // query = query.where('isActive', isEqualTo: true);

      try {
        query = query.orderBy('price');
      } catch (_) {
        // price may not exist or no index—skip ordering
      }

      final snap = await query.get();
      availablePlans = snap.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>;
            return {'id': d.id, ...data};
          })
          .toList()
          .cast<Map<String, dynamic>>();
    } catch (e) {
      // ignore: avoid_print
      print('Error loading available plans: $e');
      availablePlans = [];
    }
  }

  // ---- Actions ----
  Future<void> _updateProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;

    if (currentUser == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);
      final newEmail = _emailController.text.trim();

      // Update email in Firebase Auth if changed
      if (newEmail != (currentUser!.email ?? '')) {
        await currentUser!.verifyBeforeUpdateEmail(newEmail);
        _showSuccessSnack(
            'Verification email sent to $newEmail. Verify to complete email update.');
      }

      // Update Firestore profile
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'name': _nameController.text.trim(),
        'email': newEmail,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (newEmail == (currentUser!.email ?? '')) {
        _showSuccessSnack('Profile updated');
      }

      await _loadUserData();
    } catch (e) {
      _showErrorDialog('Error updating profile: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      _showErrorDialog('All password fields are required');
      return;
    }
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showErrorDialog('New passwords do not match');
      return;
    }
    if (_newPasswordController.text.length < 6) {
      _showErrorDialog('New password must be at least 6 characters');
      return;
    }
    if (currentUser == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      final credential = EmailAuthProvider.credential(
        email: currentUser!.email!,
        password: _currentPasswordController.text,
      );
      await currentUser!.reauthenticateWithCredential(credential);
      await currentUser!.updatePassword(_newPasswordController.text);

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      _showSuccessSnack('Password changed');
    } catch (e) {
      _showErrorDialog('Error changing password: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /// Updates the SINGLE document: `user_plans/{userId}`.
  /// Does NOT create a document if missing; shows a helpful error instead.
  Future<void> _upgradePlan(String newPlanId) async {
    final uid = currentUser?.uid;
    if (uid == null) {
      _toLogin();
      return;
    }

    try {
      if (mounted) setState(() => isLoading = true);

      final userPlanRef = _firestore.collection('user_plans').doc(uid);

      // Update only; if doc doesn't exist, throw & inform user.
      await userPlanRef.update({
        'planId': newPlanId,
        'isActive': true, // keep active flag if you use it elsewhere
        'active': true,   // optional legacy flag
        'startDate': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _showSuccessSnack('Plan updated');
      await _loadCurrentPlan();
      if (mounted) setState(() {});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        _showErrorDialog(
          'No plan document found at user_plans/$uid.\n'
          'Create this document once with id = userId, e.g. { "planId": "<planId>", "isActive": true }. '
          'After that, you can change plans from here.',
        );
      } else {
        _showErrorDialog('Error updating plan: ${e.message ?? e.code}');
      }
    } catch (e) {
      _showErrorDialog('Error updating plan: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _auth.signOut();
      _toLogin();
    } catch (e) {
      _showErrorDialog('Error logging out: $e');
    }
  }

  // ---- UI helpers ----
  void _toLogin() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Something went wrong'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  void _showSuccessSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showChangePasswordSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(
            bottom: bottom,
            left: 16,
            right: 16,
            top: 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetTitle('Change Password'),
              const SizedBox(height: 8),
              TextField(
                controller: _currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm New Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _currentPasswordController.clear();
                        _newPasswordController.clear();
                        _confirmPasswordController.clear();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _changePassword();
                      },
                      child: const Text('Change'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showPlansSheet() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetTitle('Available Plans'),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availablePlans.length,
                    itemBuilder: (context, index) {
                      final plan = availablePlans[index];
                      final isCurrent = currentPlan?['id'] == plan['id'];
                      final name = (plan['name'] ?? 'Unnamed Plan').toString();
                      final description =
                          (plan['description'] ?? '').toString();
                      final price = plan['price'];
                      final priceText =
                          price is num ? '₹${price.toStringAsFixed(0)}' : '₹—';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.workspace_premium),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600)),
                                    if (description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(description),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(priceText,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              isCurrent
                                  ? Chip(
                                      label: const Text('Current'),
                                      backgroundColor: Colors.green.shade100,
                                    )
                                  : ElevatedButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _upgradePlan(plan['id'].toString());
                                      },
                                      child: const Text('Select'),
                                    ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- Build ----
  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 360;
    final pagePadding = EdgeInsets.all(isSmall ? 12 : 16);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 980;

                    return Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: SingleChildScrollView(
                          padding: pagePadding,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Header card with avatar + summary
                              _HeaderCard(
                                name: _nameController.text.trim().isEmpty
                                    ? (currentUser?.email ?? 'User')
                                    : _nameController.text.trim(),
                                email: _emailController.text,
                              ),
                              const SizedBox(height: 16),

                              // Responsive content:
                              if (isWide) ...[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: _LeftColumn(
                                        profileFormKey: _profileFormKey,
                                        nameController: _nameController,
                                        emailController: _emailController,
                                        onSaveProfile: _updateProfile,
                                        onChangePassword:
                                            _showChangePasswordSheet,
                                      ),
                                    ),
                                    const SizedBox(width: 20),
                                    Expanded(
                                      child: _RightColumn(
                                        currentPlan: currentPlan,
                                        onShowPlans: _showPlansSheet,
                                        onLogout: _logout,
                                      ),
                                    ),
                                  ],
                                ),
                              ] else ...[
                                // Mobile: NO Expanded/Flexible inside the scroll view
                                _LeftColumn(
                                  profileFormKey: _profileFormKey,
                                  nameController: _nameController,
                                  emailController: _emailController,
                                  onSaveProfile: _updateProfile,
                                  onChangePassword: _showChangePasswordSheet,
                                ),
                                const SizedBox(height: 16),
                                _RightColumn(
                                  currentPlan: currentPlan,
                                  onShowPlans: _showPlansSheet,
                                  onLogout: _logout,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

// ======= UI building blocks =======

class _HeaderCard extends StatelessWidget {
  final String name;
  final String email;

  const _HeaderCard({
    required this.name,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1f2937), const Color(0xFF111827)]
              : [const Color(0xFFE3F2FD), const Color(0xFFEEF7FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF374151) : const Color(0xFFBBDEFB),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.color
                            ?.withOpacity(0.7),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _CardSection({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              ),
            ],
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _CurrentPlanTile extends StatelessWidget {
  final String name;
  final String description;
  final dynamic price;

  const _CurrentPlanTile({
    required this.name,
    required this.description,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    final priceText =
        price is num ? '₹${(price as num).toStringAsFixed(0)}' : '₹—';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.star_rate_rounded, color: Colors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Current Plan: $name',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(description),
                ],
                const SizedBox(height: 4),
                Text(
                  'Price: $priceText',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700));
  }
}

class _LeftColumn extends StatelessWidget {
  final GlobalKey<FormState> profileFormKey;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final VoidCallback onSaveProfile;
  final VoidCallback onChangePassword;

  const _LeftColumn({
    required this.profileFormKey,
    required this.nameController,
    required this.emailController,
    required this.onSaveProfile,
    required this.onChangePassword,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CardSection(
          title: 'Profile',
          subtitle: 'Update your name and email address',
          child: Form(
            key: profileFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Please enter your email';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onSaveProfile,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save Changes'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _CardSection(
          title: 'Security',
          subtitle: 'Change your account password',
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onChangePassword,
              icon: const Icon(Icons.lock_reset),
              label: const Text('Change Password'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RightColumn extends StatelessWidget {
  final Map<String, dynamic>? currentPlan;
  final VoidCallback onShowPlans;
  final VoidCallback onLogout;

  const _RightColumn({
    required this.currentPlan,
    required this.onShowPlans,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _CardSection(
          title: 'Subscription',
          subtitle: 'View or change your plan anytime',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (currentPlan != null)
                _CurrentPlanTile(
                  name: (currentPlan!['name'] ?? currentPlan!['id']).toString(),
                  description: (currentPlan!['description'] ?? '').toString(),
                  price: currentPlan!['price'],
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Text(
                    'No active plan found',
                    style: TextStyle(
                      color: Colors.orange.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: onShowPlans,
                icon: const Icon(Icons.upgrade),
                label: Text(currentPlan != null ? 'Change Plan' : 'Select Plan'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CardSection(
          title: 'Logout',
          subtitle: 'Sign out from this device',
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Logout'),
                    content: const Text('Are you sure you want to logout?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onLogout();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
