// attendance_block_standalone.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';


class AttendencePage extends StatelessWidget {
  const AttendencePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: const SafeArea(child: AttendanceBlock()),
    );
  }
}


const _kBrand = Color(0xFF4C63D2);
const _kGap = 12.0;

class AttendanceBlock extends StatefulWidget {
  const AttendanceBlock({super.key});
  @override
  State<AttendanceBlock> createState() => _AttendanceBlockState();
}

class _AttendanceBlockState extends State<AttendanceBlock> {
  DateTime _selectedDate = _atMidnight(DateTime.now());
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all'; // all | present | absent
  Timer? _debounce;

  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _attendanceCache = {};
  List<QueryDocumentSnapshot> _slotDocs = const [];

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);
  String _dateKey(DateTime d) => DateFormat('yyyyMMdd').format(d);
  DateTime get _startOfDay => _selectedDate;
  DateTime get _endOfDay => _selectedDate.add(const Duration(days: 1));

  Future<void> _pickDate(BuildContext ctx) async {
    final picked = await showDatePicker(
      context: ctx,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = _atMidnight(picked);
        _attendanceCache.clear();
      });
    }
  }

  Future<void> _preloadAttendanceForDay() async {
    final qs = await FirebaseFirestore.instance
        .collection('attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(_endOfDay))
        .get();

    _attendanceCache.clear();
    for (final d in qs.docs) {
      final m = d.data();
      final bookingId = (m['bookingId'] ?? '').toString();
      if (bookingId.isNotEmpty) _attendanceCache[bookingId] = m;
    }
  }

  Future<void> _preloadUsers(Iterable<QueryDocumentSnapshot> slots) async {
    final userIds = <String>{};
    for (final s in slots) {
      final m = s.data() as Map<String, dynamic>;
      if ((m['status'] ?? '') != 'booked') continue;
      final uid = (m['booked_by'] ?? '').toString();
      if (uid.isNotEmpty && !_userCache.containsKey(uid)) userIds.add(uid);
    }

    Future<void> loadUsersChunked(List<String> ids) async {
      const chunkSize = 10;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(i, (i + chunkSize).clamp(0, ids.length));
        final qs = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in qs.docs) {
          _userCache[d.id] = d.data();
        }
      }
    }

    await Future.wait([
      if (userIds.isNotEmpty) loadUsersChunked(userIds.toList()),
      _preloadAttendanceForDay(),
    ]);
  }

  String _displayUser(Map<String, dynamic>? u) {
    if (u == null) return '-';
    final name = (u['name'] ?? '').toString();
    final phone = (u['phone'] ?? '').toString();
    if (name.isNotEmpty && phone.isNotEmpty) return '$name ($phone)';
    return name.isNotEmpty ? name : (phone.isNotEmpty ? phone : '-');
  }

  Map<String, dynamic> _attendanceForBooking(String bookingId) {
    return _attendanceCache[bookingId] ?? const {};
  }

  String _statusForBooking(String bookingId) {
    final a = _attendanceForBooking(bookingId);
    final s = (a['status'] ?? '').toString().toLowerCase();
    if (s == 'present') return 'present';
    if (s == 'absent') return 'absent';
    return 'unmarked';
  }

  bool _matchesFilters({
    required String bookingId,
    required Map<String, dynamic>? user,
    required String status,
  }) {
    final normalized = status == 'unmarked' ? 'absent' : status;
    final q = _searchCtrl.text.trim().toLowerCase();
    if (_statusFilter != 'all' && normalized != _statusFilter) return false;
    if (q.isEmpty) return true;
    final name = (user?['name'] ?? '').toString().toLowerCase();
    final phone = (user?['phone'] ?? '').toString().toLowerCase();
    if (bookingId.toLowerCase().contains(q)) return true;
    if (name.contains(q)) return true;
    if (phone.contains(q)) return true;
    return false;
  }

  // ── Write attendance (with slot_day & slot_time) + delete booking ─────────
  Future<void> _setAttendance({
    required String bookingId,
    required String userId,
    required DateTime slotDay, // day of slot
    required String slotTime,  // time of slot
    required String status,
  }) async {
    final dayAtMidnight = _atMidnight(slotDay);
    final docId = '${_dateKey(dayAtMidnight)}_$bookingId';

    final attRef = FirebaseFirestore.instance.collection('attendance').doc(docId);
    final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(bookingId);

    final payload = {
      'bookingId': bookingId,
      'userId': userId,
      'slot_day': Timestamp.fromDate(dayAtMidnight),
      'slot_time': slotTime,
      'date': Timestamp.fromDate(dayAtMidnight),
      'status': status,
      'marked_by': 'admin',
      'updated_at': FieldValue.serverTimestamp(),
    };

    try {
      final batch = FirebaseFirestore.instance.batch();
      batch.set(attRef, payload, SetOptions(merge: true));
      batch.delete(bookingRef);
      await batch.commit();
    } catch (e) {
      try {
        await attRef.set(payload, SetOptions(merge: true));
      } catch (_) {}
    }

    // Update local cache/UI immediately
    _attendanceCache[bookingId] = {
      'bookingId': bookingId,
      'userId': userId,
      'slot_day': Timestamp.fromDate(dayAtMidnight),
      'slot_time': slotTime,
      'date': Timestamp.fromDate(dayAtMidnight),
      'status': status,
      'marked_by': 'admin',
      'updated_at': Timestamp.now(),
    };

    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Marked $status and moved to attendance'),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
        ),
      );
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final qSlots = FirebaseFirestore.instance
        .collection('slots')
        .where('slot_day', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay))
        .where('slot_day', isLessThan: Timestamp.fromDate(_endOfDay))
        .orderBy('slot_day');

    final dateTitle = DateFormat('dd MMM, yyyy').format(_selectedDate).toUpperCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Top Search Bar ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search student / phone / booking id',
              border: const OutlineInputBorder(),
              isDense: true,
              filled: true,
              suffixIcon: (_searchCtrl.text.isEmpty)
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 220), () {
                if (mounted) setState(() {});
              });
            },
          ),
        ),

        // ── Header Row: Date + Icons ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(child: TableHeader(title: dateTitle)),
              IconButton(
                tooltip: 'Pick date',
                onPressed: () => _pickDate(context),
                icon: const Icon(Icons.calendar_today),
              ),
              PopupMenuButton<String>(
                tooltip: 'Filter',
                icon: const Icon(Icons.filter_list),
                initialValue: _statusFilter,
                onSelected: (v) => setState(() => _statusFilter = v),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'all', child: Text('All')),
                  PopupMenuItem(value: 'present', child: Text('Present')),
                  PopupMenuItem(value: 'absent', child: Text('Absent')),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Body ────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StreamBuilder<QuerySnapshot>(
              stream: qSlots.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const _Loading();
                }
                if (snap.hasError) {
                  return const _EmptyState(
                    icon: Icons.error_outline,
                    lines: ['Could not load slots'],
                  );
                }

                final all = snap.data?.docs ?? const [];
                final booked = all.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  return (m['status'] ?? '') == 'booked';
                }).toList();

                if (booked.isEmpty) {
                  _slotDocs = booked;
                  return const _EmptyState(
                    icon: Icons.event_busy,
                    lines: ['No booked slots for this date.'],
                  );
                }

                _slotDocs = booked;

                return FutureBuilder<void>(
                  future: _preloadUsers(booked),
                  builder: (context, loadSnap) {
                    if (loadSnap.connectionState != ConnectionState.done) {
                      return const _Loading();
                    }

                    // Counters
                    int present = 0, absent = 0, unmarked = 0;
                    for (final s in booked) {
                      final m = s.data() as Map<String, dynamic>;
                      final bookingId = (m['booking_id'] ?? '').toString();
                      final st = _statusForBooking(bookingId);
                      if (st == 'present') {
                        present++;
                      } else if (st == 'absent') {
                        absent++;
                      } else {
                        unmarked++;
                      }
                    }

                    // ── Metrics row ───────────────────────────────────────
                    final metrics = Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: const [
                            _MetricTile(header: 'Present', value: '', color: Colors.green), // placeholders
                          ],
                        ),
                      ),
                    );

                    // Build rows
                    final rows = <List<Widget>>[];
                    for (final s in booked) {
                      final m = s.data() as Map<String, dynamic>;
                      final dateTs = m['slot_day'] as Timestamp?;
                      final date = dateTs?.toDate() ?? _selectedDate;

                      final bookingId = (m['booking_id'] ?? '').toString();
                      final userId = (m['booked_by'] ?? '').toString();
                      final slotTime = (m['slot_time'] ?? '').toString();
                      final instructorName = (m['instructor_name'] ?? '').toString();
                      final user = _userCache[userId];
                      final status = _statusForBooking(bookingId);

                      if (!_matchesFilters(
                        bookingId: bookingId,
                        user: user,
                        status: status == 'unmarked' ? 'absent' : status,
                      )) continue;

                      rows.add([
                        // Slot (time + instructor)
                        Text(
                          [slotTime, if (instructorName.isNotEmpty) '· $instructorName'].join(' '),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Student
                        Row(
                          children: [
                            _Avatar(name: (user?['name'] ?? '').toString()),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _displayUser(user),
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),

                        // Booking ID
                        Text(
                          bookingId.isEmpty ? '-' : bookingId,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),

                        // Date
                        Text(
                          DateFormat('dd MMM yyyy').format(date),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),

                        // Status chip
                        StatusBadge(
                          text: status == 'unmarked' ? 'unmarked' : status,
                          type: status == 'present'
                              ? 'approved'
                              : status == 'absent'
                                  ? 'rejected'
                                  : 'default',
                        ),

                        // Actions
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Mark Present',
                              icon: const Icon(Icons.check_circle),
                              onPressed: (bookingId.isEmpty || userId.isEmpty || status == 'present')
                                  ? null
                                  : () => _setAttendance(
                                        bookingId: bookingId,
                                        userId: userId,
                                        slotDay: date,
                                        slotTime: slotTime,
                                        status: 'present',
                                      ),
                            ),
                            IconButton(
                              tooltip: 'Mark Absent',
                              icon: const Icon(Icons.cancel),
                              onPressed: (bookingId.isEmpty || userId.isEmpty || status == 'absent')
                                  ? null
                                  : () => _setAttendance(
                                        bookingId: bookingId,
                                        userId: userId,
                                        slotDay: date,
                                        slotTime: slotTime,
                                        status: 'absent',
                                      ),
                            ),
                          ],
                        ),
                      ]);
                    }

                    // Update metric values now that counts are known
                    final metricTiles = Row(
                      children: [
                        _MetricTile(header: 'Present', value: present.toString(), color: Colors.green),
                        const SizedBox(width: 10),
                        _MetricTile(header: 'Absent', value: absent.toString(), color: Colors.red),
                        const SizedBox(width: 10),
                        _MetricTile(header: 'Unmarked', value: unmarked.toString(), color: Colors.orange),
                        const SizedBox(width: 10),
                        const _MetricTile(header: 'Total', value: '', color: _kBrand),
                        _MetricTile(header: 'Total', value: booked.length.toString(), color: _kBrand),
                      ],
                    );

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: metricTiles,
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minWidth: 1080),
                              child: DataTableWrap(
                                columns: const ['Slot', 'Student', 'Booking ID', 'Date', 'Status', 'Actions'],
                                rows: rows,
                                columnWidths: const [240, 320, 180, 160, 140, 160],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── UI pieces (standalone replacements for ui_common) ─────────────────────────

class TableHeader extends StatelessWidget {
  final String title;
  const TableHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _kBrand.withOpacity(0.45),
                    _kBrand.withOpacity(0.10),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final String type; // 'approved' | 'rejected' | 'default'
  const StatusBadge({super.key, required this.text, required this.type});

  Color get _base {
    switch (type) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return _kBrand;
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = _base;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: base.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: base.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: base,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class DataTableWrap extends StatelessWidget {
  final List<String> columns;
  final List<List<Widget>> rows;
  final List<double>? columnWidths;

  const DataTableWrap({
    super.key,
    required this.columns,
    required this.rows,
    this.columnWidths,
  });

  @override
  Widget build(BuildContext context) {
    assert(rows.every((r) => r.length == columns.length),
        'Each row must have exactly ${columns.length} cells');

    final widths = (columnWidths != null && columnWidths!.length == columns.length)
        ? columnWidths!
        : List<double>.filled(columns.length, 180);

    final header = Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300),
          bottom: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Row(
        children: List.generate(columns.length, (i) {
          return _Cell(
            width: widths[i],
            child: Text(
              columns[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
            ),
          );
        }),
      ),
    );

    final body = Column(
      children: List.generate(rows.length, (rIdx) {
        final row = rows[rIdx];
        final bg = rIdx % 2 == 0 ? Colors.white : Colors.grey.shade50;
        return Container(
          color: bg,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(row.length, (cIdx) {
              return _Cell(
                width: widths[cIdx],
                child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  child: row[cIdx],
                ),
              );
            }),
          ),
        );
      }),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            header,
            body,
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final double width;
  final Widget child;
  const _Cell({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: width),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: child,
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String header;
  final String value;
  final Color color;
  const _MetricTile({required this.header, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(header, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;
  const _Avatar({required this.name});

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final label = name.trim().isEmpty ? '?' : _initials(name);
    return CircleAvatar(
      radius: 12,
      backgroundColor: _kBrand.withOpacity(0.12),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _kBrand)),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: const [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('Loading…'),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final List<String> lines;
  const _EmptyState({required this.icon, required this.lines});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 40, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          for (final l in lines) Text(l, style: TextStyle(color: Colors.grey.shade700)),
        ]),
      ),
    );
  }
}
