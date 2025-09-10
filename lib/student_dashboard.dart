// lib/student_dashboard.dart
import 'dart:math';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_drive/downloadables.dart';
import 'package:smart_drive/upload_document_page.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:smart_drive/UserAttendancePanel.dart';
import 'package:smart_drive/mock_tests_list_page.dart';
import 'package:smart_drive/user_materials_page.dart';
import 'package:smart_drive/user_settings.dart';
import 'package:smart_drive/user_slot_booking.dart';
// removed upload_document_page import — onboarding form used instead
import 'package:smart_drive/onboarding_forms.dart';
import 'package:smart_drive/test_booking_page.dart';

// THEME
import 'package:smart_drive/theme/app_theme.dart';

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

  // local hide flag for onboarding banner (not persisted)
  bool _hideOnboardingBanner = false;

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

  // photo stream from user_profiles/{uid}.photo_url
  Stream<String?> _photoUrlStream(String uid) {
    return _firestore
        .collection('user_profiles')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['photo_url'] as String?)?.trim())
        .distinct();
  }

  // planId stream from user_plans/{uid}.planId (shown as-is)
  Stream<String?> _planIdStream(String uid) {
    return _firestore
        .collection('user_plans')
        .doc(uid)
        .snapshots()
        .map((snap) => (snap.data()?['planId'] as String?)?.toString())
        .distinct();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    final uid = _auth.currentUser?.uid;
    final role = (userData['role'] ?? 'student').toString();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Pinned top bar
            SliverAppBar(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.onSurface,
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

            // ── Name card with photo + planId string (live)
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
                        planIdString: null,
                      );
                    }
                    return StreamBuilder<String?>(
                      stream: _photoUrlStream(uid),
                      builder: (context, photoSnap) {
                        final photoUrl = photoSnap.data;
                        return StreamBuilder<String?>(
                          stream: _planIdStream(uid),
                          builder: (context, planSnap) {
                            final planId = planSnap.data;
                            return _NameCard(
                              name: (userData['name'] ?? 'Student').toString(),
                              email: (userData['email'] ?? '').toString(),
                              role: role,
                              photoUrl: photoUrl,
                              planIdString: planId,
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),

            // ── Onboarding banner (shown for pending users)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  children: [
                    if (!_hideOnboardingBanner && userStatus.toLowerCase() == 'pending')
                      _onboardingBanner(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Quick Actions (always enabled)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('Quick Actions'),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.calendar_month,
                            color: AppColors.warning,
                            title: 'Book Slot',
                            onTap: _navigateToSlotBooking,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.access_time,
                            color: AppColors.accentTeal,
                            title: 'Attendance Tracker',
                            onTap: _navigateToAttendance,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.menu_book,
                            color: AppColors.info,
                            title: 'Study Materials',
                            onTap: _navigateToStudyMaterials,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PrimaryTile(
                            icon: Icons.book_online,
                            color: AppColors.purple,
                            title: 'Test Booking',
                            onTap: _navigateToTestBooking,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── More options
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
                      iconColor: AppColors.primary,
                      title: 'Upload Documents',
                      subtitle: 'Add or manage KYC and other files',
                      onTap: _navigateToUploadDocuments,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.download_rounded,
                      iconColor: AppColors.slate,
                      title: 'Downloadables',
                      subtitle: 'Forms, PDFs, guides & resources',
                      onTap: _navigateToDownloadables,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: Icons.receipt,
                      iconColor: AppColors.brown,
                      title: 'Invoice History',
                      subtitle: 'See your payment receipts and invoices',
                      onTap: _navigateToInvoices,
                    ),
                    const SizedBox(height: 12),
                    // Moved: Questionaries (was Mock Tests)
                    _ActionTile(
                      icon: Icons.quiz,
                      iconColor: AppColors.purple,
                      title: 'Questionaries',
                      subtitle: 'Attempt practice questionnaires and previous tests',
                      onTap: _navigateToQuestionaries,
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
  void _navigateToSlotBooking() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserSlotBooking()));
  }

  void _navigateToStudyMaterials() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const UserMaterialsPage()));
  }

  void _navigateToMockTests() {
    // kept for backward compatibility
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MockTestsListPage()));
  }

  void _navigateToQuestionaries() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MockTestsListPage()));
  }

  void _navigateToTestBooking() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TestBookingPage()));
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
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadablesPage()));
  }

  void _navigateToSettings() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserSettingsScreen()));
  }

  // CTA used by onboarding banner
  void _navigateToCompleteOnboarding() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingForm()));
  }

  // ── Onboarding banner widget (local dismiss only)
  Widget _onboardingBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.m),
      child: Container(
        color: AppColors.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // icon / left
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(AppRadii.s),
                ),
                child: Icon(Icons.info_outline, color: AppColors.warning),
              ),

              const SizedBox(width: 12),

              // text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Complete onboarding', style: AppText.tileTitle),
                    const SizedBox(height: 4),
                    Text(
                      'Your account is pending — finish uploading documents to get full access.',
                      style: AppText.tileSubtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // action
              TextButton(
                onPressed: _navigateToCompleteOnboarding,
                child: const Text('Complete onboarding', style: TextStyle(fontWeight: FontWeight.w600)),
              ),

              // dismiss
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => setState(() => _hideOnboardingBanner = true),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      ),
    );
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
        const Icon(Icons.tune_rounded, size: 18, color: AppColors.onSurface),
        const SizedBox(width: 8),
        Text(text, style: AppText.sectionTitle),
      ],
    );
  }
}

class _NameCard extends StatelessWidget {
  final String name;
  final String email;
  final String role;
  final String? photoUrl;

  // plan (plain string)
  final String? planIdString;

  const _NameCard({
    required this.name,
    required this.email,
    required this.role,
    this.photoUrl,
    required this.planIdString,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          gradient: AppGradients.nameCard,
          border: Border.all(color: Colors.white.withOpacity(0.12), width: 0.8),
          boxShadow: AppShadows.elevatedDark,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _GrainPainter(opacity: 0.06)),
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
                        const Text('Welcome back,', style: TextStyle(color: AppColors.onSurfaceInverseMuted, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.onSurfaceInverse,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$email | ${role.toLowerCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.onSurfaceInverseMuted, fontSize: 12, letterSpacing: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.workspace_premium, size: 16, color: AppColors.onSurfaceInverseMuted),
                            const SizedBox(width: 6),
                            Text(
                              'Plan: ${planIdString == null || planIdString!.isEmpty ? '—' : planIdString!}',
                              style: const TextStyle(color: AppColors.onSurfaceInverse, fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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
    final bg = AppColors.onSurfaceInverse.withOpacity(0.14);
    if (photoUrl == null || photoUrl!.isEmpty) {
      return CircleAvatar(
        radius: 36,
        backgroundColor: bg,
        child: const Icon(Icons.person, color: AppColors.onSurfaceInverse, size: 38),
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

  const _PrimaryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  static const double _kTileHeight = 150;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.l),
        onTap: onTap,
        child: SizedBox(
          height: _kTileHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(AppRadii.m),
                  ),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.tileTitle,
                ),
              ],
            ),
          ),
        ),
      ),
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
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.m),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadii.m),
                ),
                padding: const EdgeInsets.all(10),
                child: Icon(icon, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.tileTitle),
                    const SizedBox(height: 4),
                    Text(subtitle, style: AppText.tileSubtitle),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceFaint),
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

    DateTime? asDt(dynamic v) {
      if (v == null) return null;
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }
    final now = DateTime.now();
    final scheduledAt = asDt(m['scheduled_at']) ?? asDt(m['created_at']);
    final expiresAt   = asDt(m['expires_at']);
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

    final readsStream = fs
        .collection('users')
        .doc(uid)
        .collection('notif_reads')
        .snapshots();

    final notifsQuery = fs
        .collection('notifications')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: readsStream,
      builder: (context, readsSnap) {
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

            final now = DateTime.now();
            final sevenDays = const Duration(days: 7);

            final List<QueryDocumentSnapshot> visible = targeted.where((d) {
              final readAt = readAtMap[d.id];
              if (readAt == null) return true;
              return now.difference(readAt) <= sevenDays;
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
                    visible,
                    readAtMap.keys.toSet(),
                  ),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(color: AppColors.onSurfaceInverse, fontSize: 10),
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
    final RenderBox? overlay = Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
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
                  color: isRead ? AppColors.onSurfaceMuted : AppColors.danger,
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
                          Text(whenTxt, style: AppText.hintSmall),
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
