import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Reuse your existing helpers (DataTableWrap, StatusBadge, TableHeader, etc.)
import 'ui_common.dart';

const _kBrand = Color(0xFF4C63D2);

class AttendanceBlock extends StatefulWidget {
  const AttendanceBlock({super.key});
  @override
  State<AttendanceBlock> createState() => _AttendanceBlockState();
}

class _AttendanceBlockState extends State<AttendanceBlock> {
  // ── Filters / UI state ─────────────────────────────────────────────────────
  DateTime _selectedDate = _atMidnight(DateTime.now());
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all'; // all | present | absent
  Timer? _debounce;

  // ── Simple caches per snapshot to reduce reads ─────────────────────────────
  final Map<String, Map<String, dynamic>> _userCache = {};
  final Map<String, Map<String, dynamic>> _slotCache = {};
  final Map<String, Map<String, dynamic>> _attendanceCache = {};

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
        _attendanceCache.clear(); // change day => clear cache
      });
    }
  }

  // Load attendance docs for the selected date into cache (keyed by bookingId)
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
      _attendanceCache[bookingId] = m;
    }
  }

  // Batched preload users/slots to avoid N+1 reads for each row
  Future<void> _preloadUsersAndSlots(Iterable<QueryDocumentSnapshot> bookings) async {
    final userIds = <String>{};
    final slotIds = <String>{};

    for (final b in bookings) {
      final m = b.data() as Map<String, dynamic>;
      final uid = (m['userId'] ?? '').toString(); // <-- adjust if field differs
      final sid = (m['slotId'] ?? '').toString(); // <-- adjust if field differs
      if (uid.isNotEmpty && !_userCache.containsKey(uid)) userIds.add(uid);
      if (sid.isNotEmpty && !_slotCache.containsKey(sid)) slotIds.add(sid);
    }

    // Firestore whereIn limit is 10; chunk if needed
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

    Future<void> loadSlotsChunked(List<String> ids) async {
      const chunkSize = 10;
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.sublist(i, (i + chunkSize).clamp(0, ids.length));
        final qs = await FirebaseFirestore.instance
            .collection('slots')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in qs.docs) {
          _slotCache[d.id] = d.data();
        }
      }
    }

    await Future.wait([
      if (userIds.isNotEmpty) loadUsersChunked(userIds.toList()),
      if (slotIds.isNotEmpty) loadSlotsChunked(slotIds.toList()),
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

  String _displaySlot(Map<String, dynamic>? s) {
    if (s == null) return '-';
    final title = (s['title'] ?? '').toString();
    final time = (s['timeRange'] ?? '').toString();
    if (title.isNotEmpty && time.isNotEmpty) return '$title · $time';
    return title.isNotEmpty ? title : (time.isNotEmpty ? time : '-');
  }

  Map<String, dynamic> _attendanceForBooking(String bookingId) {
    return _attendanceCache[bookingId] ?? const {};
  }

  String _statusForBooking(String bookingId) {
    final a = _attendanceForBooking(bookingId);
    final s = (a['status'] ?? '').toString().toLowerCase();
    if (s == 'present') return 'present';
    if (s == 'absent') return 'absent';
    return 'absent'; // default view
  }

  bool _matchesFilters({
    required String bookingId,
    required Map<String, dynamic>? user,
    required String status,
  }) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (_statusFilter != 'all' && status != _statusFilter) return false;

    if (q.isEmpty) return true;

    final name = (user?['name'] ?? '').toString().toLowerCase();
    final phone = (user?['phone'] ?? '').toString().toLowerCase();
    if (bookingId.toLowerCase().contains(q)) return true;
    if (name.contains(q)) return true;
    if (phone.contains(q)) return true;
    return false;
  }

  Future<void> _setAttendance({
    required String bookingId,
    required String userId,
    required String slotId,
    required DateTime date,
    required String status, // 'present'|'absent'
  }) async {
    final docId = '${_dateKey(date)}_$bookingId';
    final ref = FirebaseFirestore.instance.collection('attendance').doc(docId);
    await ref.set({
      'bookingId': bookingId,
      'userId': userId,
      'slotId': slotId,
      'date': Timestamp.fromDate(_atMidnight(date)),
      'status': status,
      'marked_by': 'admin', // TODO: swap with actual admin id/name if available
      'updated_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // reflect immediately in local cache for snappy UI
    _attendanceCache[bookingId] = {
      'bookingId': bookingId,
      'userId': userId,
      'slotId': slotId,
      'date': Timestamp.fromDate(_atMidnight(date)),
      'status': status,
      'marked_by': 'admin',
      'updated_at': Timestamp.now(),
    };
    if (mounted) setState(() {});
  }

  // ── Main build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final qBookings = FirebaseFirestore.instance
        .collection('bookings')
        // If you only want confirmed bookings, uncomment next line and adjust:
        // .where('status', isEqualTo: 'confirmed')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(_startOfDay))
        .where('date', isLessThan: Timestamp.fromDate(_endOfDay))
        .orderBy('date'); // ensure index exists for date + where

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Header ───────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: TableHeader(
                  title: 'Attendance — ${DateFormat('EEE, dd MMM yyyy').format(_selectedDate)}',
                  // You can adjust TableHeader in your ui_common to support trailing widgets, or place controls here
                ),
              ),
              const SizedBox(width: 12),
              _ChipButton(
                icon: Icons.calendar_today,
                label: 'Change date',
                onTap: () => _pickDate(context),
              ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search student name / phone / booking id',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), () {
                      if (mounted) setState(() {});
                    });
                  },
                ),
              ),
              DropdownButton<String>(
                value: _statusFilter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'present', child: Text('Present')),
                  DropdownMenuItem(value: 'absent', child: Text('Absent')),
                ],
                onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
              ),
              TextButton.icon(
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _statusFilter = 'all';
                }),
                icon: const Icon(Icons.refresh),
                label: const Text('Reset'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Body: bookings of selected day → rows ────────────────────────────
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: StreamBuilder<QuerySnapshot>(
              stream: qBookings.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No bookings for this date.'));
                }

                // Preload related docs & attendance, then build rows
                return FutureBuilder<void>(
                  future: _preloadUsersAndSlots(docs),
                  builder: (context, loadSnap) {
                    if (loadSnap.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final rows = <List<Widget>>[];
                    for (final b in docs) {
                      final m = b.data() as Map<String, dynamic>;
                      final bookingId = b.id;
                      final userId = (m['userId'] ?? '').toString(); // <-- adjust if your field differs
                      final slotId = (m['slotId'] ?? '').toString(); // <-- adjust if your field differs
                      final dateTs = m['date'] as Timestamp?;
                      final date = dateTs?.toDate() ?? _selectedDate;

                      final user = _userCache[userId];
                      final slot = _slotCache[slotId];
                      final status = _statusForBooking(bookingId);

                      if (!_matchesFilters(
                        bookingId: bookingId,
                        user: user,
                        status: status,
                      )) {
                        continue;
                      }

                      rows.add([
                        // Slot
                        Text(_displaySlot(slot), overflow: TextOverflow.ellipsis),
                        // Student
                        Text(_displayUser(user), overflow: TextOverflow.ellipsis),
                        // Booking Id (or phone)
                        Text(bookingId, overflow: TextOverflow.ellipsis),
                        // Date
                        Text(DateFormat('dd MMM yyyy').format(date)),
                        // Status badge
                        StatusBadge(
                          text: status == 'present' ? 'present' : 'absent',
                          type: status == 'present' ? 'approved' : 'rejected',
                        ),
                        // Actions
                        Wrap(
                          spacing: 8,
                          children: [
                            ElevatedButton(
                              onPressed: status == 'present'
                                  ? null
                                  : () => _setAttendance(
                                        bookingId: bookingId,
                                        userId: userId,
                                        slotId: slotId,
                                        date: date,
                                        status: 'present',
                                      ),
                              child: const Text('Mark Present'),
                            ),
                            OutlinedButton(
                              onPressed: status == 'absent'
                                  ? null
                                  : () => _setAttendance(
                                        bookingId: bookingId,
                                        userId: userId,
                                        slotId: slotId,
                                        date: date,
                                        status: 'absent',
                                      ),
                              child: const Text('Mark Absent'),
                            ),
                          ],
                        ),
                      ]);
                    }

                    return DataTableWrap(
                      columns: const ['Slot', 'Student', 'Booking ID', 'Date', 'Status', 'Actions'],
                      rows: rows,
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

// ── Small UI helper for header buttons ───────────────────────────────────────
class _ChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ChipButton({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kBrand.withOpacity(0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: _kBrand),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
