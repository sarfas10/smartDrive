// user_attendance_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserAttendancePage extends StatelessWidget {
  const UserAttendancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: const Text('My Attendance', style: TextStyle(color: Colors.black)),
      ),
      body: const SafeArea(child: UserAttendancePanel()),
    );
  }
}

/// Core panel
class UserAttendancePanel extends StatefulWidget {
  const UserAttendancePanel({super.key});
  @override
  State<UserAttendancePanel> createState() => _UserAttendancePanelState();
}

class _UserAttendancePanelState extends State<UserAttendancePanel> {
  // ── Theme accents ──────────────────────────────────────────────────────────
  static const Color kPresent = Color(0xFF2E7D32); // green 800
  static const Color kAbsent  = Color(0xFFD32F2F); // red 700
  static const Color kCard    = Colors.white;
  static const Color kText    = Colors.black87;   // main text
  static const Color kTextDim = Colors.black54;   // secondary text

  // ── Month + filters ────────────────────────────────────────────────────────
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  String _statusFilter = 'all'; // all | present | absent

  // ── Identity resolution ────────────────────────────────────────────────────
  String? _attendanceUserId;
  bool _resolvingUser = true;
  String? _resolveError;

  DateTime get _startOfRange => DateTime(_month.year, _month.month, 1);
  DateTime get _endOfRange   => DateTime(_month.year, _month.month + 1, 1); // exclusive

  @override
  void initState() {
    super.initState();
    _resolveCurrentUserId();
  }

  Future<void> _resolveCurrentUserId() async {
    try {
      final authUser = FirebaseAuth.instance.currentUser;
      if (authUser == null) {
        setState(() { _resolvingUser = false; _resolveError = 'not-signed-in'; });
        return;
      }

      try {
        final snap = await FirebaseFirestore.instance.collection('users').doc(authUser.uid).get();
        if (snap.exists) {
          final data = snap.data() as Map<String, dynamic>;
          final useId  = (data['useId']?.toString().trim() ?? '');
          final userId = (data['userId']?.toString().trim() ?? '');
          _attendanceUserId = useId.isNotEmpty ? useId : (userId.isNotEmpty ? userId : authUser.uid);
        } else {
          _attendanceUserId = authUser.uid;
        }
      } catch (_) {
        _attendanceUserId = authUser.uid;
      }

      setState(() { _resolvingUser = false; _resolveError = null; });
    } catch (e) {
      setState(() { _resolvingUser = false; _resolveError = 'failed:${e.toString()}'; });
    }
  }

  Future<void> _pickMonth(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2023),
      lastDate: DateTime(2032),
      helpText: 'Pick any date in the month',
      builder: (context, child) {
        // Force light sheet for consistency
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Colors.black,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _month = DateTime(picked.year, picked.month, 1));
  }

  void _prevMonth() => setState(() => _month = DateTime(_month.year, _month.month - 1, 1));
  void _nextMonth() => setState(() => _month = DateTime(_month.year, _month.month + 1, 1));

  @override
  Widget build(BuildContext context) {
    if (_resolvingUser) return const _UA_Loading();

    if (_resolveError == 'not-signed-in') {
      return const _UA_EmptyState(icon: Icons.lock_outline, lines: ['Please sign in to view your attendance.']);
    }
    if (_attendanceUserId == null) {
      return const _UA_EmptyState(icon: Icons.error_outline, lines: ['Could not resolve user.', 'Please try again.']);
    }

    // NO COMPOSITE INDEX NEEDED: only use date range + orderBy(date)
    final q = FirebaseFirestore.instance
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfRange))
        .where('date', isLessThan: Timestamp.fromDate(_endOfRange))
        .orderBy('date', descending: true);

    final monthTitle = DateFormat('MMMM yyyy').format(_month);

    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 680;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    monthTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: kText,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .2,
                        ),
                  ),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _IconBtn(tooltip: 'Previous month', icon: Icons.chevron_left, onTap: _prevMonth, color: kText),
                      _IconBtn(tooltip: 'Next month', icon: Icons.chevron_right, onTap: _nextMonth, color: kText),
                      _IconBtn(tooltip: 'Pick month', icon: Icons.calendar_today, onTap: () => _pickMonth(context), color: kText),
                      const SizedBox(width: 6),
                      _StatusDropdown(
                        value: _statusFilter,
                        onChanged: (v) => setState(() => _statusFilter = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Body
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: StreamBuilder<QuerySnapshot>(
                  stream: q.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) return const _UA_Loading();
                    if (snap.hasError) {
                      final err = snap.error?.toString();
                      return _UA_EmptyState(icon: Icons.error_outline, lines: ['Could not load attendance.', if (err != null) err]);
                    }

                    // Map docs → sessions (gracefully handle optional fields)
                    final sessions = <_Session>[];
                    for (final d in (snap.data?.docs ?? const [])) {
                      final m = d.data() as Map<String, dynamic>;
                      final ts = (m['date'] ?? m['slot_day']);
                      if (ts is! Timestamp) continue;

                      final day = ts.toDate();
                      final userId   = (m['userId'] ?? '').toString();

                      // CLIENT-SIDE filter to this user (avoids composite index)
                      if (userId != _attendanceUserId) continue;

                      final status   = (m['status'] ?? '').toString().toLowerCase();
                      final slotTime = (m['slot_time'] ?? '').toString();
                      final markedBy = (m['markedBy'] ?? m['marked_by'] ?? '').toString();
                      final updated  = m['updatedAt'] is Timestamp ? (m['updatedAt'] as Timestamp).toDate() : null;

                      sessions.add(_Session(
                        userId: userId,
                        date: DateTime(day.year, day.month, day.day),
                        slotTime: slotTime,
                        status: status.isEmpty ? 'unmarked' : status,
                        markedBy: markedBy,
                        updatedAt: updated,
                      ));
                    }

                    if (sessions.isEmpty) {
                      return const _UA_EmptyState(icon: Icons.event_busy, lines: ['No attendance found for this month.']);
                    }

                    // Stats (sessions-based)
                    var presentSessions = 0, absentSessions = 0;
                    for (final s in sessions) {
                      if (s.status == 'present') presentSessions++;
                      if (s.status == 'absent')  absentSessions++;
                    }
                    final totalSessions = presentSessions + absentSessions;
                    final presentRate = totalSessions == 0 ? 0.0 : (presentSessions / totalSessions) * 100.0;

                    // Listing filter + order
                    final filtered = _statusFilter == 'all'
                        ? sessions
                        : sessions.where((s) => s.status == _statusFilter).toList();

                    filtered.sort((a, b) {
                      final cmp = b.date.compareTo(a.date);
                      if (cmp != 0) return cmp;
                      return b.slotTime.compareTo(a.slotTime);
                    });

                    return CustomScrollView(
                      slivers: [
                        // Overview card
                        SliverToBoxAdapter(
                          child: _OverviewCard(
                            present: presentSessions,
                            absent: absentSessions,
                            total: totalSessions,
                            presentRatePercent: presentRate,
                            presentColor: kPresent,
                            absentColor: kAbsent,
                            cardColor: kCard,
                            isNarrow: isNarrow,
                            textColor: kText,
                            textDim: kTextDim,
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),

                        // Session list
                        SliverList.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, i) => _SessionCard(
                            s: filtered[i],
                            presentColor: kPresent,
                            absentColor: kAbsent,
                            textColor: kText,
                            textDim: kTextDim,
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact dropdown used in header
class _StatusDropdown extends StatelessWidget {
  final String value; // 'all' | 'present' | 'absent'
  final ValueChanged<String> onChanged;
  const _StatusDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const entries = <MapEntry<String, String>>[
      MapEntry('all', 'All'),
      MapEntry('present', 'Present'),
      MapEntry('absent', 'Absent'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7), // light bg
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black87.withOpacity(.15)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black87),
          style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
          dropdownColor: Colors.white,
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          items: [
            for (final e in entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value),
              )
          ],
        ),
      ),
    );
  }
}

/// Data holder
class _Session {
  final String userId;
  final DateTime date;
  final String slotTime;
  final String status;   // present | absent | unmarked
  final String markedBy; // optional
  final DateTime? updatedAt; // optional
  _Session({
    required this.userId,
    required this.date,
    required this.slotTime,
    required this.status,
    required this.markedBy,
    required this.updatedAt,
  });
}

// ───────────────────────── UI Helpers ─────────────────────────

class _IconBtn extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  const _IconBtn({required this.tooltip, required this.icon, required this.onTap, required this.color});
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 22, color: color), // explicitly black
        onPressed: onTap,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      );
}

// ───────────────────── Overview (Donut) Card ────────────────────

class _OverviewCard extends StatelessWidget {
  final int present, absent, total;
  final double presentRatePercent;
  final Color presentColor, absentColor, cardColor;
  final bool isNarrow;
  final Color textColor, textDim;

  const _OverviewCard({
    required this.present,
    required this.absent,
    required this.total,
    required this.presentRatePercent,
    required this.presentColor,
    required this.absentColor,
    required this.cardColor,
    required this.isNarrow,
    required this.textColor,
    required this.textDim,
  });

  @override
  Widget build(BuildContext context) {
    final chartSize = isNarrow ? 220.0 : 260.0;
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        children: [
          Text('Attendance Overview',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 8),
          // Donut + center label
          SizedBox(
            height: chartSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                _DonutChart(
                  segments: [
                    _DonutSegment(value: present.toDouble(), color: presentColor),
                    _DonutSegment(value: absent.toDouble(),  color: absentColor),
                  ],
                  trackColor: Colors.grey.shade200,
                  thickness: 28,
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${presentRatePercent.isNaN ? 0 : presentRatePercent.toStringAsFixed(1)}%',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.black54 )),
                    const SizedBox(height: 2),
                    const Text('Present Rate', style: TextStyle(fontSize: 12, color: Colors.black54)),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Legend
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _LegendDot(color: presentColor, label: 'Present ($present)', textColor: textColor),
              _LegendDot(color: absentColor,  label: 'Absent ($absent)',  textColor: textColor),
            ],
          ),
          const SizedBox(height: 12),
          // Quick stats
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _QuickStat(label: 'Total Sessions', value: '$total', textColor: textColor, textDim: textDim),
              _QuickStat(label: 'Attendance Rate', value: '${presentRatePercent.isNaN ? 0 : presentRatePercent.toStringAsFixed(1)}%', textColor: textColor, textDim: textDim),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final Color textColor;
  const _LegendDot({required this.color, required this.label, required this.textColor});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(fontSize: 13, color: textColor)),
    ]);
  }
}

class _QuickStat extends StatelessWidget {
  final String label, value;
  final Color textColor, textDim;
  const _QuickStat({required this.label, required this.value, required this.textColor, required this.textDim});
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 12, color: textDim)),
    ]);
  }
}

class _DonutSegment {
  final double value;
  final Color color;
  const _DonutSegment({required this.value, required this.color});
}

class _DonutChart extends StatelessWidget {
  final List<_DonutSegment> segments;
  final Color trackColor;
  final double thickness;
  const _DonutChart({required this.segments, required this.trackColor, required this.thickness});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutChartPainter(segments: segments, trackColor: trackColor, thickness: thickness),
      size: Size.infinite,
    );
  }
}

class _DonutChartPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final Color trackColor;
  final double thickness;
  _DonutChartPainter({required this.segments, required this.trackColor, required this.thickness});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - 4;

    final bg = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.butt;
    canvas.drawCircle(center, radius, bg);

    final total = segments.fold<double>(0, (s, e) => s + (e.value <= 0 ? 0 : e.value));
    if (total <= 0) return;

    var start = -math.pi / 2; // start at top
    for (final seg in segments) {
      final v = seg.value <= 0 ? 0 : seg.value;
      if (v == 0) continue;
      final sweep = (v / total) * 2 * math.pi;
      final p = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = thickness
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.segments != segments || old.trackColor != trackColor || old.thickness != thickness;
}

// ───────────────────── Session Card Item ───────────────────────

class _SessionCard extends StatelessWidget {
  final _Session s;
  final Color presentColor;
  final Color absentColor;
  final Color textColor;
  final Color textDim;

  const _SessionCard({
    required this.s,
    required this.presentColor,
    required this.absentColor,
    required this.textColor,
    required this.textDim,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy').format(s.date);
    final slot    = s.slotTime.isEmpty ? '-' : s.slotTime;

    final (chipColor, chipText) = switch (s.status) {
      'present' => (presentColor, 'PRESENT'),
      'absent'  => (absentColor, 'ABSENT'),
      _         => (Colors.grey, 'UNMARKED'),
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 6))],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          // Top row: status chip + date
          Row(
            children: [
              _StatusChip(text: chipText, color: chipColor),
              const Spacer(),
              Text(dateStr, style: TextStyle(fontSize: 12, color: textDim)),
            ],
          ),
          const SizedBox(height: 10),
          // Details rows
          _DetailRow(icon: Icons.access_time, label: 'Session Time', value: slot, textColor: textColor, textDim: textDim),
          if (s.markedBy.trim().isNotEmpty)
            _DetailRow(icon: Icons.person, label: 'Marked by', value: s.markedBy, textColor: textColor, textDim: textDim),
          if (s.updatedAt != null)
            _DetailRow(
              icon: Icons.update,
              label: 'Last Updated',
              value: DateFormat('MMM dd, yyyy - hh:mm a').format(s.updatedAt!),
              textColor: textColor,
              textDim: textDim,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text; final Color color;
  const _StatusChip({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: .4)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon; final String label; final String value;
  final Color textColor; final Color textDim;
  const _DetailRow({required this.icon, required this.label, required this.value, required this.textColor, required this.textDim});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: textDim), // slightly dimmer than pure black
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: textDim)),
          const SizedBox(width: 10),
          Expanded(child: Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor))),
        ],
      ),
    );
  }
}

// ───────────────────── States ─────────────────────

class _UA_Loading extends StatelessWidget {
  const _UA_Loading();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Loading…', style: TextStyle(color: Colors.black87)),
        ]),
      ),
    );
  }
}

class _UA_EmptyState extends StatelessWidget {
  final IconData icon;
  final List<String> lines;
  const _UA_EmptyState({required this.icon, required this.lines});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: Colors.black54),
          const SizedBox(height: 12),
          for (final l in lines)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(l, style: const TextStyle(color: Colors.black54))),
        ]),
      ),
    );
  }
}
