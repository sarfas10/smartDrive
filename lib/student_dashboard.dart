// student_dashboard.dart
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:smart_drive/UserAttendancePanel.dart';
import 'package:smart_drive/mock_tests_list_page.dart';
import 'package:smart_drive/onboarding_forms.dart';
import 'package:smart_drive/user_materials_page.dart';
import 'package:smart_drive/user_settings.dart';
import 'package:smart_drive/user_slot_booking.dart';
import 'package:smart_drive/upload_document_page.dart';

/// ───────────────────── Background grain painter ─────────────────────
class _GrainPainter extends CustomPainter {
  final double opacity;
  _GrainPainter({this.opacity = 0.06});
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = Random(7);
    final dotPaint = Paint()..color = Colors.white.withOpacity(opacity);
    final count = (size.width * size.height / 220).toInt();
    for (int i = 0; i < count; i++) {
      final dx = rnd.nextDouble() * size.width;
      final dy = rnd.nextDouble() * size.height;
      final r = rnd.nextDouble() * 0.8 + 0.2;
      canvas.drawCircle(Offset(dx, dy), r, dotPaint);
    }
    final brush = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white24, Colors.transparent, Colors.white12],
        stops: [0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size)
      ..blendMode = BlendMode.overlay
      ..color = Colors.white.withOpacity(opacity * 0.5);
    canvas.drawRect(Offset.zero & size, brush);
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) => oldDelegate.opacity != opacity;
}

/// ───────────────────────────────── Student Dashboard ────────────────────────────────
class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});
  @override
  _StudentDashboardState createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String userStatus = '';
  Map<String, dynamic> userData = {};
  bool isLoading = true;

  // anchor for bell menu
  final GlobalKey _bellAnchorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          setState(() {
            userData = doc.data() as Map<String, dynamic>;
            userStatus = (userData['status'] ?? 'pending').toString();
            isLoading = false;
          });
          await _ensurePlanRollOver(user.uid);
        } else {
          setState(() => isLoading = false);
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _ensurePlanRollOver(String uid) async {
    try {
      final upRef = _firestore.collection('user_plans').doc(uid);
      final upSnap = await upRef.get();
      if (!upSnap.exists) {
        debugPrint('[PlanRollOver] No user_plans doc for $uid');
        return;
      }
      final up = upSnap.data() ?? {};
      final String? planId = (up['planId'] as String?)?.trim();
      final int slotsUsed = (up['slots_used'] is num) ? (up['slots_used'] as num).toInt() : 0;
      if (planId == null || planId.isEmpty) {
        debugPrint('[PlanRollOver] No planId set for $uid');
        return;
      }
      final planRef = _firestore.collection('plans').doc(planId);
      final planSnap = await planRef.get();
      if (!planSnap.exists) {
        debugPrint('[PlanRollOver] Plan $planId not found for $uid');
        return;
      }
      final plan = planSnap.data() ?? {};
      final bool isPayPerUse = (plan['isPayPerUse'] == true);
      final int slots = (plan['slots'] is num) ? (plan['slots'] as num).toInt() : 0;

      if (!isPayPerUse && slots != 0 && slotsUsed >= slots) {
        final ppuQuery = await _firestore
            .collection('plans')
            .where('isPayPerUse', isEqualTo: true)
            .limit(1)
            .get();
        if (ppuQuery.docs.isEmpty) {
          debugPrint('[PlanRollOver] No pay-per-use plan available. Aborting rollover.');
          return;
        }
        final newPlanId = ppuQuery.docs.first.id;
        await upRef.update({
          'planId': newPlanId,
          'switched_from_plan': planId,
          'switched_at': FieldValue.serverTimestamp(),
        });
        debugPrint('[PlanRollOver] User $uid switched to pay-per-use plan $newPlanId.');
      }
    } catch (e) {
      debugPrint('[PlanRollOver] Error: $e');
    }
  }

  // photo stream from user_profiles/{uid}.photo_url
  Stream<String?> _photoUrlStream(String uid) {
    return _firestore
        .collection('user_profiles')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['photo_url'] as String?)?.trim())
        .distinct();
  }

  void _showAccessBlockedSnack() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Your account isn’t active yet. Complete onboarding to use Quick Actions.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F7FB),
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final uid = _auth.currentUser?.uid;
    final role = (userData['role'] ?? 'student').toString();
    final bool isActive = userStatus.toLowerCase() == 'active';

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Pinned top bar
            SliverAppBar(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              pinned: true,
              elevation: 0,
              title: const Text('Student Dashboard'),
              actions: [
                if (uid != null)
                  NotificationBell(
                    uid: uid,
                    role: role.toLowerCase(),
                    userStatus: userStatus.toLowerCase(),
                    anchorKey: _bellAnchorKey,
                  ),
                // transparent icon to hold anchor key
                IconButton(
                  key: _bellAnchorKey,
                  icon: const Icon(Icons.notifications_none_rounded, color: Colors.transparent),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _navigateToSettings,
                ),
                const SizedBox(width: 8),
              ],
            ),

            // ── Gradient name card with Cloudinary photo
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Builder(
                  builder: (_) {
                    if (uid == null) {
                      return _NameCard(
                        name: (userData['name'] ?? 'Student').toString(),
                        email: (userData['email'] ?? '').toString(),
                        role: role,
                        photoUrl: null,
                      );
                    }
                    return StreamBuilder<String?>(
                      stream: _photoUrlStream(uid),
                      builder: (context, snap) {
                        final photoUrl = snap.data;
                        return _NameCard(
                          name: (userData['name'] ?? 'Student').toString(),
                          email: (userData['email'] ?? '').toString(),
                          role: role,
                          photoUrl: photoUrl,
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // ── Onboarding banner if pending (or any non-active status)
            // When active, keep a small spacer so Quick Actions stay properly positioned
            if (!isActive)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _PendingBanner(onComplete: _navigateToOnboarding),
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Primary navigation options (Quick Actions) — RESTRICTED when not active
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Quick Actions'),
                    const SizedBox(height: 12),

                    // Row 1
                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.calendar_month,
                            color: Colors.orange,
                            title: 'Book Slot',
                            enabled: isActive,
                            disabledNote: 'Activate to book slots',
                            onTap: _navigateToSlotBooking,
                            onTapDisabled: _showAccessBlockedSnack,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.access_time,
                            color: const Color(0xFF00695C),
                            title: 'Attendance Tracker',
                            enabled: isActive,
                            disabledNote: 'Activate to track attendance',
                            onTap: _navigateToAttendance,
                            onTapDisabled: _showAccessBlockedSnack,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Row 2
                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.menu_book,
                            color: const Color(0xFF1565C0),
                            title: 'Study Materials',
                            enabled: isActive,
                            disabledNote: 'Activate to view materials',
                            onTap: _navigateToStudyMaterials,
                            onTapDisabled: _showAccessBlockedSnack,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.quiz,
                            color: const Color(0xFF6A1B9A),
                            title: 'Mock Tests',
                            enabled: isActive,
                            disabledNote: 'Activate to attempt tests',
                            onTap: _navigateToMockTests,
                            onTapDisabled: _showAccessBlockedSnack,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── More options (kept accessible)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('More Options'),
                    const SizedBox(height: 12),

                    _ActionTile(
                      icon: Icons.upload_file_rounded,
                      iconColor: const Color(0xFF2D5BFF),
                      title: 'Upload Documents',
                      subtitle: 'Add or manage KYC and other files',
                      onTap: _navigateToUploadDocuments,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.download_rounded,
                      iconColor: const Color(0xFF455A64),
                      title: 'Downloadables',
                      subtitle: 'Forms, PDFs, guides & resources',
                      onTap: _navigateToDownloadables,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.receipt,
                      iconColor: const Color(0xFF5D4037),
                      title: 'Invoice History',
                      subtitle: 'See your payment receipts and invoices',
                      onTap: _navigateToInvoices,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ── Navigation hooks
  void _navigateToOnboarding() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => OnboardingForm()));
  }

  void _navigateToSlotBooking() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSlotBooking()));
  }

  void _navigateToStudyMaterials() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserMaterialsPage()));
  }

  void _navigateToMockTests() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MockTestsListPage()));
  }

  void _navigateToUploadDocuments() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadDocumentPage()));
  }

  void _navigateToAttendance() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserAttendancePage()));
  }

  void _navigateToInvoices() {
    debugPrint('Navigate to Invoices');
  }

  void _navigateToDownloadables() {
    // TODO: Wire to your page if available:
    // Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadablesPage()));
    debugPrint('Navigate to Downloadables');
  }

  void _navigateToSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserSettingsScreen()));
  }
}

/// ──────────────────── UI pieces ────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tune_rounded, size: 18, color: Colors.black87),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

class _NameCard extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final String? photoUrl;
  const _NameCard({required this.name, required this.email, required this.role, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment(-0.9, -0.9), end: Alignment(0.9, 0.9),
            colors: [Color(0xFF2B2B2D), Color(0xFF3A3B3E), Color(0xFF1F2022)],
            stops: [0.0, 0.55, 1.0],
          ),
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.45), blurRadius: 14, offset: const Offset(0, 8)),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GrainPainter(opacity: 0.06)),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.08), width: 0.6),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Row(
                children: [
                  _Avatar(photoUrl: photoUrl),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Welcome back,', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.95), fontSize: 20, fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(color: Colors.black.withOpacity(0.4), offset: const Offset(0.6, 0.6), blurRadius: 1.2),
                                    Shadow(color: Colors.white.withOpacity(0.12), offset: const Offset(-0.4, -0.4), blurRadius: 1.0),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$email | ${role.toLowerCase()}',
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, letterSpacing: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  const _Avatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    final bg = Colors.white.withOpacity(0.14);
    if (photoUrl == null || photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 36,
        backgroundColor: bg,
        child: const Icon(Icons.person, color: Colors.white, size: 38),
      );
    }
    return CircleAvatar(
      radius: 36,
      backgroundColor: bg,
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          width: 72,
          height: 72,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white, size: 38),
          frameBuilder: (context, child, frame, wasSyncLoaded) {
            if (wasSyncLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  final VoidCallback onComplete;
  const _PendingBanner({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Color(0xFFF57C00), size: 24),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Please complete your profile onboarding to access all features',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
            ElevatedButton(
              onPressed: onComplete,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF57C00), foregroundColor: Colors.white),
              child: const Text('Complete'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Primary big tiles (two per row)
class _PrimaryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  // Access control + UX
  final bool enabled;
  final String? disabledNote;
  final VoidCallback? onTapDisabled;

  const _PrimaryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.enabled = true,
    this.disabledNote,
    this.onTapDisabled,
  });

  static const double _kTileHeight = 150;      // <- fixed height for consistency
  static const double _kNoteHeight = 30;       // <- reserved space for note (2 lines approx)

  @override
  Widget build(BuildContext context) {
    final card = Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        height: _kTileHeight, // enforce consistent tile height
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 6),
              // Always reserve space for the note; fade it out when enabled
              SizedBox(
                height: _kNoteHeight,
                child: AnimatedOpacity(
                  opacity: (!enabled && (disabledNote?.isNotEmpty ?? false)) ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      (disabledNote?.isNotEmpty ?? false) ? disabledNote! : ' ', // keep space
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        // Tap handling
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled ? onTap : (onTapDisabled ?? () {}),
            child: card,
          ),
        ),
        // Lock overlay
        if (!enabled)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withOpacity(0.55),
                ),
              ),
            ),
          ),
        if (!enabled)
          Positioned(
            right: 10,
            top: 10,
            child: Tooltip(
              message: 'Locked — complete onboarding',
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text('Locked', style: TextStyle(fontSize: 11, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===============================
/// Notification bell
/// ===============================
class NotificationBell extends StatelessWidget {
  final String uid;
  final String role;       // 'student' | 'instructor'
  final String userStatus; // 'active' | 'pending'
  final GlobalKey anchorKey;

  const NotificationBell({
    super.key,
    required this.uid,
    required this.role,
    required this.userStatus,
    required this.anchorKey,
  });

  bool _isTargeted(Map<String, dynamic> m) {
    final List segs = (m['segments'] as List?) ?? const ['all'];
    final Set<String> S = segs.map((e) => e.toString().toLowerCase()).toSet();

    final List targets = (m['target_uids'] as List?) ?? const [];
    final bool direct = targets.map((e) => e.toString()).contains(uid);

    DateTime? _asDt(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }
    final now = DateTime.now();
    final scheduledAt = _asDt(m['scheduled_at']) ?? _asDt(m['created_at']);
    final expiresAt   = _asDt(m['expires_at']);
    final withinTime  = (scheduledAt == null || !scheduledAt.isAfter(now)) &&
                        (expiresAt == null   ||  expiresAt.isAfter(now));

    final bool segmentHit =
        S.contains('all') ||
        (S.contains('students') && role == 'student') ||
        (S.contains('instructors') && role == 'instructor') ||
        (S.contains('active') && userStatus == 'active') ||
        (S.contains('pending') && userStatus == 'pending');

    return withinTime && (direct || segmentHit);
  }

  @override
  Widget build(BuildContext context) {
    final fs = FirebaseFirestore.instance;

    // Reads (to know which are read + when)
    final readsStream = fs
        .collection('users')
        .doc(uid)
        .collection('notif_reads')
        .snapshots();

    // Latest notifications
    final notifsQuery = fs
        .collection('notifications')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: readsStream,
      builder: (context, readsSnap) {
        // Map of notifId -> readAt timestamp
        final Map<String, DateTime?> readAtMap = {
          if (readsSnap.hasData)
            for (final d in readsSnap.data!.docs)
              d.id: (() {
                final m = (d.data() as Map).cast<String, dynamic>();
                final v = m['readAt'];
                if (v is Timestamp) return v.toDate();
                if (v is DateTime) return v;
                return null;
              })(),
        };

        return StreamBuilder<QuerySnapshot>(
          stream: notifsQuery,
          builder: (context, notifSnap) {
            final targeted = <QueryDocumentSnapshot>[];
            if (notifSnap.hasData) {
              for (final d in notifSnap.data!.docs) {
                final m = (d.data() as Map).cast<String, dynamic>();
                if (_isTargeted(m)) targeted.add(d);
              }
            }

            // Hide read notifications after 7 days from readAt
            final now = DateTime.now();
            final sevenDays = const Duration(days: 7);

            final List<QueryDocumentSnapshot> visible = targeted.where((d) {
              final readAt = readAtMap[d.id];
              if (readAt == null) return true; // unread → always show
              return now.difference(readAt) <= sevenDays; // keep if read ≤ 7d
            }).toList();

            final int unreadCount =
                visible.where((d) => !readAtMap.containsKey(d.id)).length;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () => _openMenu(
                    context,
                    anchorKey,
                    visible,                     // pass only visible notifs
                    readAtMap.keys.toSet(),      // for "isRead" checks
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD32F2F),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    GlobalKey anchorKey,
    List<QueryDocumentSnapshot> targeted,
    Set<String> readIds,
  ) async {
    final RenderBox? box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final RenderBox? overlay = Overlay.of(context, rootOverlay: true)?.context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      // fallback
      await showModalBottomSheet(
        context: context,
        builder: (_) => _NotificationsList(
          targeted: targeted,
          readIds: readIds,
          onTapItem: (id, url) async {
            await _markRead(context, id);
            if (url != null && url.isNotEmpty) {
              final uri = Uri.tryParse(url);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            }
            Navigator.pop(context);
          },
        ),
      );
      return;
    }

    final Offset topRight = box.localToGlobal(Offset(box.size.width, 0), ancestor: overlay);
    final Offset bottomRight = box.localToGlobal(Offset(box.size.width, box.size.height), ancestor: overlay);

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(topRight, bottomRight),
      Offset.zero & overlay.size,
    );

    final double menuWidth = math.min(MediaQuery.of(context).size.width * 0.92, 340);

    await showMenu(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: menuWidth,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: _NotificationsList(
                  targeted: targeted,
                  readIds: readIds,
                  onTapItem: (id, url) async {
                    await _markRead(context, id);
                    Navigator.pop(context);
                    if (url != null && url.isNotEmpty) {
                      final uri = Uri.tryParse(url);
                      if (uri != null) {
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _markRead(BuildContext context, String notifId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('notif_reads')
          .doc(notifId)
          .set({'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to mark read: $e')));
    }
  }
}

class _NotificationsList extends StatelessWidget {
  final List<QueryDocumentSnapshot> targeted;
  final Set<String> readIds;
  final Future<void> Function(String id, String? url) onTapItem;

  const _NotificationsList({
    required this.targeted,
    required this.readIds,
    required this.onTapItem,
  });

  String _formatWhen(dynamic ts) {
    DateTime? dt;
    if (ts == null) return '—';
    if (ts is Timestamp) dt = ts.toDate();
    if (ts is DateTime) dt = ts;
    if (dt == null) return '—';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (targeted.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('No notifications')),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: targeted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final d = targeted[i];
        final m = (d.data() as Map).cast<String, dynamic>();
        final title = (m['title'] ?? '-') as String;
        final msg = (m['message'] ?? '') as String;
        final url = (m['action_url'] ?? '').toString();
        final ts = (m['scheduled_at'] ?? m['created_at']) as dynamic;
        final whenTxt = _formatWhen(ts);
        final isRead = readIds.contains(d.id);

        return InkWell(
          onTap: () => onTapItem(d.id, null),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  isRead ? Icons.notifications_none : Icons.notifications_active,
                  size: 22,
                  color: isRead ? Colors.grey : Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface,
                          )),
                      const SizedBox(height: 2),
                      Text(
                        msg,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface.withOpacity(.75),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(whenTxt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const Spacer(),
                          if (url.isNotEmpty)
                            TextButton(
                              onPressed: () => onTapItem(d.id, url),
                              child: const Text('Open'),
                            ),
                          if (!isRead)
                            TextButton(
                              onPressed: () => onTapItem(d.id, null),
                              child: const Text('Mark as read'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
