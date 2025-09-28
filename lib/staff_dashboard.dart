// lib/admin/staff_dashboard.dart
import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // <-- added

// Theme (same theme you use elsewhere)
import 'package:smart_drive/theme/app_theme.dart';

// External details pages (same modules used by users_block)
import 'student_details.dart' as details;
import 'instructor_details.dart' as inst;

// Session & messaging helpers (used to clear session and unsubscribe)
import '../services/session_service.dart'; // adjust path if needed
import '../messaging_setup.dart'; // adjust path if needed

// Login screen to return to
import '../login.dart'; // adjust path if needed

// Responsive breakpoint (shared)
const kTableBreakpoint = 720.0;

class StaffDashboardPage extends StatefulWidget {
  const StaffDashboardPage({super.key});

  @override
  State<StaffDashboardPage> createState() => _StaffDashboardPageState();
}

class _StaffDashboardPageState extends State<StaffDashboardPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _compact = false;
  bool _loggingOut = false; // progress indicator for logout

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  // ----------------- Logout flow -----------------
  Future<void> _confirmAndLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('Are you sure you want to sign out of this account?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Log out')),
        ],
      ),
    );

    if (ok != true) return;
    await _performLogout();
  }

  Future<void> _performLogout() async {
    setState(() => _loggingOut = true);

    try {
      // 1) Sign out from Firebase Auth
      await FirebaseAuth.instance.signOut();

      // 2) Optionally unsubscribe from messaging topics. If your messaging_setup
      // exposes an unsubscribeUserSegments() function, this will call it.
      

      // 3) Clear local session / preferences
      try {
        await SessionService().clear();
      } catch (e) {
        debugPrint('Session clear error: $e');
      }

      // 4) Navigate back to LoginScreen (replace history)
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
          transitionDuration: const Duration(milliseconds: 220),
        ),
      );

      // show a small snackbar after navigation won't be visible here because we've replaced the route.
      // If you want a snackbar on the login screen, show it after navigation by passing an argument or using SessionService.
    } catch (e, st) {
      debugPrint('Logout error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not log out: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }
  // ------------------------------------------------

  // Navigation helper (mirrors users_block._openDetails)
  void _openDetails(BuildContext context, String role, String uid) {
    final r = role.toLowerCase().trim();
    final isInstructor =
        r == 'instructor' || r == 'teacher' || r == 'tutor' || r == 'faculty';

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => isInstructor
            ? const inst.InstructorDetailsPage()
            : const details.StudentDetailsPage(),
        settings: RouteSettings(arguments: {'uid': uid}),
        transitionsBuilder: (_, anim, __, child) {
          final slide = Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim);
          return FadeTransition(
            opacity: anim,
            child: SlideTransition(position: slide, child: child),
          );
        },
      ),
    );
  }

  // Build a query filtered by role
  Query _queryForRole(String role) {
    return FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: role)
        .orderBy('name');
  }

  // Client-side search filter
  List<QueryDocumentSnapshot> _applySearch(List<QueryDocumentSnapshot> docs, String query) {
    final s = query.trim().toLowerCase();
    if (s.isEmpty) return docs;
    return docs.where((d) {
      final m = d.data() as Map<String, dynamic>;
      final hay = [
        m['name'],
        m['email'],
        m['phone'],
      ].where((x) => x != null).join(' ').toLowerCase();
      return hay.contains(s);
    }).toList();
  }

  Widget _buildList(BuildContext context, List<QueryDocumentSnapshot> docs) {
    final width = MediaQuery.sizeOf(context).width;
    final isTable = width >= kTableBreakpoint;

    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No records found', style: Theme.of(context).textTheme.titleMedium),
        ),
      );
    }

    if (isTable) {
      // simple table-like rows
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Card(
          color: AppColors.surface,
          elevation: 0,
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final m = doc.data() as Map<String, dynamic>;
              final name = (m['name'] ?? 'Unknown').toString();
              final email = (m['email'] ?? '-').toString();
              final role = (m['role'] ?? '-').toString();
              final status = (m['status'] ?? 'active').toString();
              final uid = (m['uid']?.toString().isNotEmpty ?? false) ? m['uid'].toString() : doc.id;

              return InkWell(
                onTap: () => _openDetails(context, role, uid),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.brand.withOpacity(0.12),
                        child: Text(
                          name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                          style: const TextStyle(color: AppColors.brand),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: AppColors.onSurface)),
                            const SizedBox(height: 4),
                            Text(email, style: const TextStyle(color: AppColors.onSurfaceMuted, fontFeatures: [FontFeature.tabularFigures()])),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(role[0].toUpperCase() + role.substring(1), style: const TextStyle(color: AppColors.onSurface)),
                          const SizedBox(height: 6),
                          Text(status[0].toUpperCase() + status.substring(1), style: const TextStyle(color: AppColors.onSurfaceMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      // mobile list tiles
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final doc = docs[i];
          final m = doc.data() as Map<String, dynamic>;
          final name = (m['name'] ?? 'Unknown').toString();
          final email = (m['email'] ?? '-').toString();
          final role = (m['role'] ?? '-').toString();
          final status = (m['status'] ?? 'active').toString();
          final uid = (m['uid']?.toString().isNotEmpty ?? false) ? m['uid'].toString() : doc.id;

          return Card(
            color: AppColors.surface,
            elevation: 0,
            child: ListTile(
              onTap: () => _openDetails(context, role, uid),
              leading: CircleAvatar(
                backgroundColor: AppColors.brand.withOpacity(0.12),
                child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?', style: const TextStyle(color: AppColors.brand)),
              ),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.onSurface)),
              subtitle: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.onSurfaceMuted, fontFeatures: [FontFeature.tabularFigures()])),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(role[0].toUpperCase() + role.substring(1), style: const TextStyle(color: AppColors.onSurface)),
                  const SizedBox(height: 6),
                  Text(status[0].toUpperCase() + status.substring(1), style: const TextStyle(color: AppColors.onSurfaceMuted)),
                ],
              ),
            ),
          );
        },
      );
    }
  }

  Widget _tabStreamBuilder(String role) {
    final query = _queryForRole(role);
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = _applySearch(snapshot.data!.docs, _searchController.text);
        return _buildList(context, docs);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // simple app bar with tabs (no menu)
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        centerTitle: false,
        elevation: 0,
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.brand,
          labelColor: AppColors.onSurface,
          tabs: const [
            Tab(text: 'Students'),
            Tab(text: 'Instructors'),
          ],
        ),
        actions: [
          // Logout button
          IconButton(
            tooltip: 'Log out',
            onPressed: _loggingOut ? null : _confirmAndLogout,
            icon: _loggingOut
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.logout),
            color: AppColors.onSurface,
          ),
        ],
      ),
      // No drawer/menu as requested
      body: Column(
        children: [
          // Search + compact toggle row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => _onSearchChanged(),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.onSurfaceFaint),
                      hintText: 'Search students or instructors…',
                      hintStyle: const TextStyle(color: AppColors.onSurfaceFaint),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

              ],
            ),
          ),

          // Divider
          const Divider(height: 1, color: AppColors.divider),

          // Tab views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _tabStreamBuilder('student'),
                _tabStreamBuilder('instructor'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
