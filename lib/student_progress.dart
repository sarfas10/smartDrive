// lib/student_progress.dart
//
// Student profile + progress page.
// - Overview: contact/personal info + documents (no separate Documents tab)
// - Progress: attendance pie + test metrics driven by your test_attempts schema
//
// Firestore (as per your screenshots):
// users/{uid}: displayName|name, email, phone|mobile, dob, courseName|course,
//              plan, enrolledAt|createdAt (Timestamp/String)
// attendance:  { userId|uid, date|day (Timestamp), status: 'present'|'absent' }
// test_attempts:
//   { student_id, pool_id, score (0..100), total (int), correct (int),
//     status ('completed'...), started_at, completed_at }
// test_pool/{pool_id}: { title, passing_score_pct, ... }
// documents:   { userId, name|title, url|link, type|category('kyc'|'other'), verified(bool) }

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class StudentProgressPage extends StatefulWidget {
  const StudentProgressPage({super.key, this.studentId});
  final String? studentId; // if null -> current user

  @override
  State<StudentProgressPage> createState() => _StudentProgressPageState();
}

class _StudentProgressPageState extends State<StudentProgressPage>
    with SingleTickerProviderStateMixin {
  static const _kBrand = Color(0xFF4C63D2);

  late final TabController _tab;

  String? _uid;
  Map<String, dynamic>? _user;
  DateTime? _enrolledAt;

  // Attendance aggregates
  int _present = 0;
  int _absent = 0;

  // Test aggregates (per your schema)
  int _attempts = 0;            // number of attempts (status == completed)
  double _avgScore = 0;         // mean of score (0..100)
  int _sumCorrect = 0;          // sum(correct)
  int _sumQuestions = 0;        // sum(total)
  List<_Attempt> _recent = [];  // last few attempts with pool titles

  // Documents (in Overview)
  List<_DocItem> _kycDocs = const [];
  List<_DocItem> _otherDocs = const [];

  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final auth = FirebaseAuth.instance;
      final id = widget.studentId ?? auth.currentUser?.uid;
      if (id == null) {
        setState(() {
          _loading = false;
          _loadError = 'Not signed in.';
        });
        return;
      }
      _uid = id;

      // 1) user profile
      final u = await FirebaseFirestore.instance.collection('users').doc(_uid).get();
      _user = u.data() ?? {};
      _enrolledAt = _ts(_user?['enrolledAt']) ??
          _ts(_user?['createdAt']) ??
          _ts(_user?['enrolled_at']);

      // 2) attendance
      await _loadAttendanceAgg();

      // 3) tests (matches your screenshots)
      await _loadTestsFromSchema();

      // 4) documents
      await _loadDocuments();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  DateTime? _ts(dynamic v) {
    if (v == null) return null;
    try {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
    } catch (_) {}
    return null;
  }

  Future<void> _loadAttendanceAgg() async {
    final col = FirebaseFirestore.instance.collection('attendance');

    // keep tolerant to userId/uid
    QuerySnapshot<Map<String, dynamic>>? q =
        await col.where('userId', isEqualTo: _uid).get().catchError((_) => null);
    if (q == null || q.docs.isEmpty) {
      q = await col.where('uid', isEqualTo: _uid).get().catchError((_) => null);
    }

    int p = 0, a = 0;
    for (final d in q?.docs ?? const []) {
      final m = d.data();
      final s = (m['status'] ?? m['state'] ?? '').toString().toLowerCase();
      if (s.startsWith('p')) p++;
      else if (s.startsWith('a')) a++;
    }
    _present = p;
    _absent = a;
  }

  Future<void> _loadTestsFromSchema() async {
  final attemptsCol = FirebaseFirestore.instance.collection('test_attempts');

  QuerySnapshot<Map<String, dynamic>> q;
  try {
    q = await attemptsCol
        .where('student_id', isEqualTo: _uid)
        .orderBy('completed_at', descending: true)
        .get();
  } on FirebaseException catch (e) {
    if (e.code == 'failed-precondition') {
      // No composite index yet — fetch without order and sort locally.
      q = await attemptsCol.where('student_id', isEqualTo: _uid).get();
    } else {
      rethrow;
    }
  }

  // If we didn’t get server-side ordering, sort here.
  final docs = q.docs..sort((a, b) {
    final da = _ts(a.data()['completed_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final db = _ts(b.data()['completed_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return db.compareTo(da); // desc
  });

  int count = 0;
  double scoreSum = 0;
  int sumCorrect = 0;
  int sumTotal = 0;

  final poolIds = <String>{};
  final recent = <_Attempt>[];

  for (final d in docs) {
    final m = d.data();
    if ((m['status'] ?? '').toString().toLowerCase() != 'completed') continue;

    final score = (m['score'] ?? 0);
    final total = (m['total'] ?? 0);
    final correct = (m['correct'] ?? 0);
    final poolId = (m['pool_id'] ?? '').toString();
    final completedAt = _ts(m['completed_at']) ?? _ts(m['ended_at']) ?? DateTime.now();

    count++;
    scoreSum += (score is num ? score.toDouble() : 0.0);
    sumCorrect += (correct is num ? correct.toInt() : 0);
    sumTotal += (total is num ? total.toInt() : 0);

    if (poolId.isNotEmpty) poolIds.add(poolId);
    if (recent.length < 5) {
      recent.add(_Attempt(
        poolId: poolId,
        poolTitle: '',
        scorePct: (score is num) ? score.toDouble() : 0,
        completedAt: completedAt,
      ));
    }
  }

  // Resolve pool titles
  final titles = <String, String>{};
  for (final id in poolIds) {
    try {
      final p = await FirebaseFirestore.instance.collection('test_pool').doc(id).get();
      final data = p.data();
      if (data != null) titles[id] = (data['title'] ?? '').toString();
    } catch (_) {}
  }
  for (var i = 0; i < recent.length; i++) {
    final r = recent[i];
    recent[i] = r.copyWith(poolTitle: titles[r.poolId] ?? r.poolId);
  }

  setState(() {
    _attempts = count;
    _avgScore = count == 0 ? 0 : (scoreSum / count);
    _sumCorrect = sumCorrect;
    _sumQuestions = sumTotal;
    _recent = recent;
  });
}


  Future<void> _loadDocuments() async {
    final q = await FirebaseFirestore.instance
        .collection('documents')
        .where('userId', isEqualTo: _uid)
        .get()
        .catchError((_) => null);

    final kyc = <_DocItem>[];
    final others = <_DocItem>[];

    for (final d in q?.docs ?? const []) {
      final m = d.data();
      final name = (m['name'] ?? m['title'] ?? 'Document').toString();
      final url = (m['url'] ?? m['link'] ?? '').toString();
      final type = (m['type'] ?? m['category'] ?? '').toString().toLowerCase();
      final verified = (m['verified'] ?? false) == true;

      final item = _DocItem(name: name, url: url, verified: verified, type: type);
      if (type == 'kyc' ||
          type.contains('aadhaar') ||
          type.contains('aadhar') ||
          type.contains('pan') ||
          type.contains('id') ||
          name.toLowerCase().contains('kyc')) {
        kyc.add(item);
      } else {
        others.add(item);
      }
    }

    // optional KYC URLs on user doc
    final aadhaarUrl =
        (_user?['aadhaarUrl'] ?? _user?['aadharUrl'] ?? '').toString();
    final panUrl = (_user?['panUrl'] ?? '').toString();
    if (aadhaarUrl.isNotEmpty) {
      kyc.add(_DocItem(name: 'Aadhaar', url: aadhaarUrl, verified: true, type: 'kyc'));
    }
    if (panUrl.isNotEmpty) {
      kyc.add(_DocItem(name: 'PAN', url: panUrl, verified: true, type: 'kyc'));
    }

    _kycDocs = _dedupDocs(kyc);
    _otherDocs = _dedupDocs(others);
  }

  List<_DocItem> _dedupDocs(List<_DocItem> list) {
    final map = <String, _DocItem>{};
    for (final it in list) {
      final key = it.url.isNotEmpty ? it.url : '${it.name}-${it.type}-${it.verified}';
      map[key] = it;
    }
    return map.values.toList();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (_user?['displayName'] ?? _user?['name'] ?? '—').toString();
    final course = (_user?['courseName'] ?? _user?['course'] ?? '—').toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('Student Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _buildError(_loadError!)
              : Column(
                  children: [
                    _buildHeaderCard(theme, name, course),
                    const SizedBox(height: 8),
                    Container(
                      color: Colors.white,
                      child: TabBar(
                        controller: _tab,
                        labelColor: _kBrand,
                        unselectedLabelColor: Colors.black54,
                        indicatorColor: _kBrand,
                        tabs: const [Tab(text: 'Overview'), Tab(text: 'Progress')],
                      ),
                    ),
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [
                          _buildOverviewTab(theme),
                          _buildProgressTab(theme),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  // ─── Header

  Widget _buildHeaderCard(ThemeData theme, String name, String course) {
    final percent = _attendancePct;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
        child: Column(
          children: [
            Row(
              children: [
                _AvatarInitials(name: name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: theme.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(course, style: theme.textTheme.bodySmall!.copyWith(color: Colors.black54)),
                      const SizedBox(height: 2),
                      Text('Enrolled: ${_fmtDate(_enrolledAt)}',
                          style: theme.textTheme.bodySmall!.copyWith(color: Colors.black45)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _GreenProgressBar(value: percent, label: 'Attendance Rate'),
          ],
        ),
      ),
    );
  }

  // ─── Overview

  Widget _buildOverviewTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard(
          title: 'Contact Information',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _kv('Email', (_user?['email'] as String?) ?? '—'),
              const SizedBox(height: 6),
              _kv('Phone', (_user?['phone'] ?? _user?['mobile']) as String?),
            ],
          ),
        ),
        _sectionCard(
          title: 'Personal Information',
          child: Wrap(
            runSpacing: 8,
            children: [
              _kv('Date of Birth',
                  _fmtDate(_ts(_user?['dob']) ?? _ts(_user?['dateOfBirth']))),
              const SizedBox(width: 24),
              _kv('Plan', (_user?['plan'] as String?) ?? '—'),
            ],
          ),
        ),
        _sectionCard(
          title: 'Documents',
          subtitle: 'KYC & Other Uploads',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _docsGroup('KYC Documents', _kycDocs),
              const SizedBox(height: 10),
              _docsGroup('Other Uploads', _otherDocs),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  // ─── Progress

  Widget _buildProgressTab(ThemeData theme) {
    final present = _present;
    final absent = _absent;
    final accuracy = _sumQuestions == 0 ? 0 : (_sumCorrect / _sumQuestions) * 100.0;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _sectionCard(
          title: 'Attendance',
          child: Row(
            children: [
              SizedBox(width: 120, height: 120, child: _AttendancePie(present: present, absent: absent)),
              const SizedBox(width: 16),
              Expanded(
                child: Wrap(
                  runSpacing: 8,
                  children: [
                    _statLine('Present', '$present days'),
                    _statLine('Absent', '$absent days'),
                    _statLine('Attendance Rate', _attendancePctText),
                  ],
                ),
              ),
            ],
          ),
        ),
        _sectionCard(
          title: 'Tests',
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _statBlock('Attempts', '$_attempts')),
                  const SizedBox(width: 12),
                  Expanded(child: _statBlock('Avg. Score', '${_avgScore.toStringAsFixed(1)}%')),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _statBlock('Questions', '$_sumQuestions')),
                  const SizedBox(width: 12),
                  Expanded(child: _statBlock('Correct', '$_sumCorrect')),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Recent Attempts', style: Theme.of(context).textTheme.bodyMedium!
                    .copyWith(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              if (_recent.isEmpty)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No attempts yet', style: TextStyle(color: Colors.black45, fontSize: 12)),
                )
              else
                Column(
                  children: _recent.map((a) => _attemptRow(a)).toList(),
                ),
              const SizedBox(height: 10),
              _statLine('Overall Accuracy', '${accuracy.toStringAsFixed(1)}%'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _attemptRow(_Attempt a) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFEDEFF4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        title: Text(a.poolTitle.isEmpty ? a.poolId : a.poolTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(_fmtDate(a.completedAt), style: const TextStyle(fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F6FF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('${a.scorePct.toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  // ─── shared UI helpers

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : DateFormat('dd MMM, yyyy • hh:mm a').format(d);

  Widget _sectionCard({required String title, String? subtitle, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _kv(String k, String? v) {
    final s = v ?? '';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        Flexible(
          child: Text(s.isEmpty ? '—' : s,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _statBlock(String title, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E6FF)),
      ),
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _statLine(String title, String value) {
    return Row(
      children: [
        Expanded(child: Text(title, style: const TextStyle(color: Colors.black54))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _docsGroup(String title, List<_DocItem> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Text('No documents', style: TextStyle(fontSize: 12, color: Colors.black45)),
        ...items.map((d) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFEDEFF4)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            title: Text(d.name, style: const TextStyle(fontSize: 14)),
            subtitle: Text(d.verified ? 'Verified' : 'Unverified',
                style: TextStyle(fontSize: 12, color: d.verified ? const Color(0xFF2E7D32) : Colors.black45)),
            trailing: IconButton(
              icon: const Icon(Icons.open_in_new, size: 20),
              onPressed: d.url.isEmpty ? null : () => _openUrl(d.url),
              tooltip: 'Open',
            ),
          ),
        )),
      ],
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  double get _attendancePct {
    final total = _present + _absent;
    if (total == 0) return 0;
    return _present / total;
  }

  String get _attendancePctText => '${(_attendancePct * 100).toStringAsFixed(0)}%';

  Widget _buildError(String msg) => Center(
    child: Padding(padding: const EdgeInsets.all(24), child: Text(msg, textAlign: TextAlign.center)),
  );
}

// ─── Visual bits

class _AvatarInitials extends StatelessWidget {
  const _AvatarInitials({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'S'
        : name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty)
            .take(2).map((s) => s[0].toUpperCase()).join();
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0xFFE9EDFF),
      child: Text(initials,
          style: const TextStyle(color: Color(0xFF4C63D2), fontWeight: FontWeight.w700)),
    );
  }
}

class _GreenProgressBar extends StatelessWidget {
  const _GreenProgressBar({required this.value, required this.label});
  final double value; // 0..1
  final String label;

  @override
  Widget build(BuildContext context) {
    final pct = (value * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3FFF4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0F2E9)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 12,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(color: const Color(0xFFE8F8EC)),
                    FractionallySizedBox(
                      widthFactor: value.clamp(0, 1),
                      child: Container(color: const Color(0xFFB5E3C1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pct%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AttendancePie extends StatelessWidget {
  const _AttendancePie({required this.present, required this.absent});
  final int present;
  final int absent;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PiePainter(present: present, absent: absent),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${present + absent}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            const SizedBox(height: 2),
            const Text('days', style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter({required this.present, required this.absent});
  final int present;
  final int absent;

  @override
  void paint(Canvas canvas, Size size) {
    final total = (present + absent).clamp(1, 1 << 30);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;

    final bg = Paint()..style = PaintingStyle.stroke..strokeWidth = 18..color = const Color(0xFFEDEFF4);
    final pPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 18..color = const Color(0xFF4CAF50);
    final aPaint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round..strokeWidth = 18..color = const Color(0xFFEF5350);

    canvas.drawCircle(center, radius, bg);

    final pSweep = 2 * math.pi * (present / total);
    final aSweep = 2 * math.pi * (absent / total);
    final rect = Rect.fromCircle(center: center, radius: radius);
    const start = -math.pi / 2;

    if (present > 0) canvas.drawArc(rect, start, pSweep, false, pPaint);
    if (absent > 0)  canvas.drawArc(rect, start + pSweep, aSweep, false, aPaint);

    final legendY = size.height - 14;
    _legend(canvas, Offset(8, legendY), const Color(0xFF4CAF50), 'Present');
    _legend(canvas, Offset(size.width / 2, legendY), const Color(0xFFEF5350), 'Absent');
  }

  void _legend(Canvas canvas, Offset at, Color color, String label) {
    final paint = Paint()..color = color;
    final tp = TextPainter(
      textDirection: ui.TextDirection.ltr,
      text: TextSpan(text: label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
    )..layout();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(at.dx, at.dy - 7, 10, 10), const Radius.circular(2)), paint);
    tp.paint(canvas, Offset(at.dx + 14, at.dy - 10));
  }

  @override
  bool shouldRepaint(covariant _PiePainter old) =>
      old.present != present || old.absent != absent;
}

// ─── Models

class _DocItem {
  final String name;
  final String url;
  final bool verified;
  final String type;
  const _DocItem({required this.name, required this.url, required this.verified, required this.type});
}

class _Attempt {
  final String poolId;
  final String poolTitle;
  final double scorePct;
  final DateTime? completedAt;

  const _Attempt({
    required this.poolId,
    required this.poolTitle,
    required this.scorePct,
    required this.completedAt,
  });

  _Attempt copyWith({String? poolId, String? poolTitle, double? scorePct, DateTime? completedAt}) {
    return _Attempt(
      poolId: poolId ?? this.poolId,
      poolTitle: poolTitle ?? this.poolTitle,
      scorePct: scorePct ?? this.scorePct,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
