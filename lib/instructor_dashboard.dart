// instructor_dashboard.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_drive/attendance.dart';
import 'package:smart_drive/instructor_settings.dart';
import 'package:smart_drive/students_list_page.dart';
import 'package:smart_drive/upload_document_page.dart'; // NEW
import 'package:url_launcher/url_launcher.dart';
import 'package:smart_drive/instructor_slots.dart';

class InstructorDashboardPage extends StatelessWidget {
  const InstructorDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF6F7FB),
      body: SafeArea(child: _DashboardBody()),
    );
  }
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody({super.key});

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  User? get _user => _auth.currentUser;
  String _status = 'active';
  Map<String, dynamic> _me = {};
  bool _loading = true;

  // local, per-session dismiss for the warning banner
  bool _dismissedSetupWarning = false;

  @override
  void initState() {
    super.initState();
    _loadMe();
  }

  Future<void> _loadMe() async {
    final uid = _user?.uid;
    if (uid == null) return setState(() => _loading = false);
    final snap = await _db.collection('users').doc(uid).get();
    final m = snap.data() ?? {};
    setState(() {
      _me = m;
      _status = (m['status'] ?? 'active').toString();
      _loading = false;
    });
  }

  DateTime get _todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _todayEnd => _todayStart.add(const Duration(days: 1));

  Stream<DocumentSnapshot<Map<String, dynamic>>> _meDoc(String uid) {
    return _db.collection('users').doc(uid).snapshots();
  }

  // NEW: live profile doc stream for completeness checks
  Stream<DocumentSnapshot<Map<String, dynamic>>> _profileDoc(String uid) {
    return _db.collection('instructor_profiles').doc(uid).snapshots();
  }

  Stream<int> _activeStudentsCount() {
    return _db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((s) => s.docs.length);
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _todaySlots() {
    if (_user == null) return const Stream.empty();
    return _db
        .collection('slots')
        .where('instructorId', isEqualTo: _user!.uid)
        .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(_todayStart))
        .where('startAt', isLessThan: Timestamp.fromDate(_todayEnd))
        .orderBy('startAt')
        .snapshots()
        .map((s) => s.docs);
  }

  Future<Map<String, dynamic>?> _studentById(String uid) async {
    if (uid.isEmpty) return null;
    final d = await _db.collection('users').doc(uid).get();
    return d.data();
  }

  // ───────────── Completeness checks (tweak rules if needed) ─────────────
  bool _isPersonalComplete(Map<String, dynamic> usersDoc, Map<String, dynamic> profDoc) {
    final name = (usersDoc['name'] ?? '').toString().trim();
    final phone = (usersDoc['phone'] ?? '').toString().trim();
    final addr = (profDoc['address'] as Map?)?.cast<String, dynamic>() ?? const {};
    final street = (addr['street'] ?? '').toString().trim();
    final city = (addr['city'] ?? '').toString().trim();
    // Require: name + phone + at least street & city
    return name.isNotEmpty && phone.isNotEmpty && street.isNotEmpty && city.isNotEmpty;
  }

  bool _isPaymentComplete(Map<String, dynamic> profDoc) {
    final payment = (profDoc['payment'] as Map?)?.cast<String, dynamic>() ?? const {};
    final method = (payment['method'] ?? '').toString();
    if (method == 'upi') {
      final upi = (payment['upi'] as Map?)?.cast<String, dynamic>() ?? const {};
      final id = (upi['id'] ?? '').toString().trim();
      return id.isNotEmpty;
    }
    // treat anything else as bank
    final bank = (payment['bank'] as Map?)?.cast<String, dynamic>() ?? const {};
    final bankName = (bank['bankName'] ?? '').toString().trim();
    final accountHolder = (bank['accountHolder'] ?? '').toString().trim();
    final accountNumber = (bank['accountNumber'] ?? '').toString().trim();
    final routingNumber = (bank['routingNumber'] ?? '').toString().trim();
    return bankName.isNotEmpty &&
        accountHolder.isNotEmpty &&
        accountNumber.isNotEmpty &&
        routingNumber.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user?.uid;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (uid == null) return const Center(child: Text('Not signed in'));

    return StreamBuilder(
      stream: _meDoc(uid),
      builder: (context, snap) {
        final m = snap.data?.data() ?? _me;
        final name = (m['name'] ?? 'Instructor').toString();
        final email = (m['email'] ?? '').toString();
        final active = (m['status'] ?? 'active').toString().toLowerCase() == 'active';
        final role = 'instructor';

        // Wrap the rest in a second stream for the profile doc
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _profileDoc(uid),
          builder: (context, profSnap) {
            final prof = profSnap.data?.data() ?? <String, dynamic>{};

            final personalOk = _isPersonalComplete(m, prof);
            final paymentOk = _isPaymentComplete(prof);
            final needsSetup = !(personalOk && paymentOk) && !_dismissedSetupWarning;

            return CustomScrollView(
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  pinned: true,
                  elevation: 0,
                  title: const Text('Instructor Dashboard'),
                  actions: [
                    _InstructorBell(uid: uid, role: role, userStatus: _status),
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: _openSettings,
                    ),
                    const SizedBox(width: 8),
                  ],
                ),

                // Profile header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: _ProfileHeader(
                      initials: _initials(name),
                      name: name,
                      email: email,
                      active: active,
                    ),
                  ),
                ),

                // NEW: Setup warning banner
                if (needsSetup)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: _WarningCard(
                        personalOk: personalOk,
                        paymentOk: paymentOk,
                        onFixNow: _openSettings,
                        onDismiss: () => setState(() => _dismissedSetupWarning = true),
                      ),
                    ),
                  ),

                // Metric cards
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: StreamBuilder<
                              List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                            stream: _todaySlots(),
                            builder: (context, s) {
                              final slots = s.data ?? const [];
                              final cap = (m['maxDailySlots'] ?? 0) as int;
                              final value =
                                  cap > 0 ? '${slots.length}/$cap' : '${slots.length}';
                              return _MetricCard(
                                icon: Icons.event_available,
                                iconBg: const Color(0xFFE9F0FF),
                                title: "Today's Slots",
                                value: value,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StreamBuilder<int>(
                            stream: _activeStudentsCount(),
                            builder: (context, s) {
                              final total = s.data ?? 0;
                              return _MetricCard(
                                icon: Icons.groups_2_outlined,
                                iconBg: const Color(0xFFEAF7F0),
                                title: 'Active Students',
                                value: '$total',
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Action tiles
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        _ActionTile(
                          icon: Icons.event_note,
                          iconColor: Colors.purple,
                          title: 'Manage Slots',
                          subtitle: 'Manage scheduled sessions and availability',
                          onTap: _openManageSlots,
                        ),
                        const SizedBox(height: 12),
                        _ActionTile(
                          icon: Icons.check_circle,
                          iconColor: const Color(0xFF2E7D32),
                          title: 'Mark Attendance',
                          subtitle: 'Record student attendance and completion',
                          onTap: _openMarkAttendance,
                        ),
                        const SizedBox(height: 12),
                        _ActionTile(
                          icon: Icons.trending_up,
                          iconColor: const Color(0xFF1565C0),
                          title: 'View Student Progress',
                          subtitle: 'Track learning milestones and skills',
                          onTap: _openStudentProgress,
                        ),
                        const SizedBox(height: 12),
                        // NEW Upload Documents card
                        _ActionTile(
                          icon: Icons.upload_file_rounded,
                          iconColor: const Color(0xFF2D5BFF),
                          title: 'Upload Documents',
                          subtitle: 'Share study materials and files with students',
                          onTap: _openUploadDocuments,
                        ),
                      ],
                    ),
                  ),
                ),

                // Today's schedule
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: const [
                        Icon(Icons.access_time, size: 18, color: Colors.black87),
                        SizedBox(width: 8),
                        Text("Today's Schedule",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: Colors.black87,
                            )),
                      ],
                    ),
                  ),
                ),

                StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  stream: _todaySlots(),
                  builder: (context, s) {
                    final slots = s.data ?? const [];
                    if (s.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    if (slots.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16, 8, 16, 32),
                          child: _EmptyCard(message: 'No sessions scheduled for today.'),
                        ),
                      );
                    }
                    return SliverList.separated(
                      itemCount: slots.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final d = slots[i].data();
                        final ts = (d['startAt'] as Timestamp).toDate();
                        final status = (d['status'] ?? 'confirmed') as String;
                        final studentId = (d['studentId'] ?? '') as String;
                        final skill = (d['skill'] ?? d['note'] ?? '') as String;

                        return FutureBuilder<Map<String, dynamic>?>(
                          future: _studentById(studentId),
                          builder: (context, s2) {
                            final studentName =
                                (s2.data?['name'] ?? 'Student').toString();
                            return _ScheduleTile(
                              time: _fmtTime(ts),
                              name: studentName,
                              subtitle: skill,
                              status: status,
                            );
                          },
                        );
                      },
                    );
                  },
                ),

                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
        );
      },
    );
  }

  // Navigation hooks
  void _openUploadDocuments() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UploadDocumentPage()),
    );
  }

  void _openManageSlots() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InstructorSlotsBlock()),
    );
  }

  void _openMarkAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AttendencePage()),
    );
  }

  void _openStudentProgress() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StudentsListPage()),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const InstructorSettingsPage()),
    );
  }
}

/// ─────────────────────────── UI widgets ───────────────────────────

class _ProfileHeader extends StatelessWidget {
  final String initials;
  final String name;
  final String email;
  final bool active;

  const _ProfileHeader({
    required this.initials,
    required this.name,
    required this.email,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF4C63D2),
              child: Text(
                initials,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(email, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              ),
            ),
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFF2E7D32) : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  active ? 'Active' : 'Inactive',
                  style: TextStyle(
                    color: active ? const Color(0xFF2E7D32) : Colors.grey,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// NEW: prominent warning card
class _WarningCard extends StatelessWidget {
  final bool personalOk;
  final bool paymentOk;
  final VoidCallback onFixNow;
  final VoidCallback onDismiss;

  const _WarningCard({
    required this.personalOk,
    required this.paymentOk,
    required this.onFixNow,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final needPersonal = !personalOk;
    final needPayment = !paymentOk;

    return Card(
      elevation: 0,
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF57C00)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Action needed before payouts',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (needPersonal) 'Complete your Personal Information',
                      if (needPayment) 'Set up your Payment Preference',
                    ].join(' • '),
                    style: TextStyle(color: Colors.orange.shade900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Payouts will not be processed until setup is complete.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: onFixNow,
                        icon: const Icon(Icons.settings),
                        label: const Text('Open Settings'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF57C00),
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: onDismiss,
                        icon: const Icon(Icons.close),
                        label: const Text('Dismiss'),
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
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final String value;

  const _MetricCard({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.all(10),
              child: Icon(icon, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.1)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
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

class _ScheduleTile extends StatelessWidget {
  final String time;
  final String name;
  final String subtitle;
  final String status;

  const _ScheduleTile({
    required this.time,
    required this.name,
    required this.subtitle,
    required this.status,
  });

  Color get _dotColor {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF9A825);
      case 'confirmed':
        return const Color(0xFF2E7D32);
      default:
        return Colors.grey;
    }
  }

  Color get _chipBg {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFFFF4E0);
      case 'confirmed':
        return const Color(0xFFEAF7F0);
      default:
        return const Color(0xFFF1F3F6);
    }
  }

  Color get _chipText {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFF9E6400);
      case 'confirmed':
        return const Color(0xFF1B5E20);
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Card(
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 86,
                child: Text(time, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              const SizedBox(width: 8),
              Container(
                width: 6, height: 6,
                margin: const EdgeInsets.only(top: 8),
                decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(color: _chipBg, borderRadius: BorderRadius.circular(999)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Text(status.toLowerCase(),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _chipText)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String message;
  const _EmptyCard({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.black45),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.black54)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ───────────────────── Notification bell (enhanced like StudentDashboard) ───

class _InstructorBell extends StatelessWidget {
  final String uid;
  final String role;       // 'instructor'
  final String userStatus; // 'active' | 'pending'

  const _InstructorBell({
    required this.uid,
    required this.role,
    required this.userStatus,
  });

  bool _isTargeted(Map<String, dynamic> m) {
    // segments (legacy)
    final List segs = (m['segments'] as List?) ?? const ['all'];
    final Set<String> S = segs.map((e) => e.toString().toLowerCase()).toSet();

    // direct target_uids
    final List targets = (m['target_uids'] as List?) ?? const [];
    final bool direct = targets.map((e) => e.toString()).contains(uid);

    // time window gating
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

    final readsStream =
        fs.collection('users').doc(uid).collection('notif_reads').snapshots();

    final notifsQuery = fs
        .collection('notifications')
        .orderBy('created_at', descending: true)
        .limit(30)
        .snapshots();

    final anchorKey = GlobalKey();

    return StreamBuilder<QuerySnapshot>(
      stream: readsStream,
      builder: (context, readsSnap) {
        final readIds = <String>{
          if (readsSnap.hasData) ...readsSnap.data!.docs.map((d) => d.id),
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
            final unreadCount = targeted.where((d) => !readIds.contains(d.id)).length;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  key: anchorKey,
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () => _openMenu(context, anchorKey, targeted, readIds),
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
      // Fallback
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to mark read: $e')));
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

/// ─────────────────────────── Helpers ───────────────────────────

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return 'IN';
  if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
  return (parts.first.characters.take(1).toString() +
          parts.last.characters.take(1).toString())
      .toUpperCase();
}

String _fmtTime(DateTime dt) {
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$h:$m $ampm';
}
