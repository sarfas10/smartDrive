// lib/my_bookings_page.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Adjust this import to your real path for app_theme.dart
import 'theme/app_theme.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key});

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  // Caches the joined slot info for the current bookings page by booking ids.
  final Map<String, Map<String, dynamic>> _slotCacheByBookingId = {};
  bool _loadingJoin = false;

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final ts = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.2);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: context.c.background,
        appBar: _appBar(context, sw, ts),
        body: Center(
          child: Text('Please log in to view your bookings', style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.c.background,
      appBar: _appBar(context, sw, ts),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('user_id', isEqualTo: user.uid)
            // NOTE: removed orderBy to avoid composite index requirement
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}', style: context.t.bodyMedium?.copyWith(color: AppColors.danger)));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)));
          }

          // Copy and locally sort by created_at (desc)
          final docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? const []);
          docs.sort((a, b) {
            final ad = _toDate((a.data() as Map<String, dynamic>)['created_at']);
            final bd = _toDate((b.data() as Map<String, dynamic>)['created_at']);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1; // nulls go last
            if (bd == null) return -1;
            return bd.compareTo(ad); // newest first
          });

          if (docs.isEmpty) {
            return _emptyState(sw);
          }

          // Perform a batched join to get slot details for these bookings
          return FutureBuilder<Map<String, Map<String, dynamic>>>(
            future: _fetchSlotsForBookings(docs),
            builder: (context, joinSnap) {
              final joined = joinSnap.data ?? _slotCacheByBookingId;

              // Split into upcoming / past using slot end time if available; fallback to slot_day.
              final now = DateTime.now();
              final List<_BookingView> upcoming = [];
              final List<_BookingView> past = [];

              for (final b in docs) {
                final bData = b.data() as Map<String, dynamic>;
                final slot = joined[b.id];
                final when = _bookingDateTime(slot);
                final status = (bData['status'] ?? '').toString().toLowerCase();

                final isPast = when == null ? false : !when.isAfter(now);
                final view = _BookingView(
                  bookingId: b.id,
                  bookingData: bData,
                  slotData: slot,
                  startEnd: _parseTimeRange(slot?['slot_time'], day: _slotDayDate(slot?['slot_day'])),
                  slotDay: _slotDayDate(slot?['slot_day']),
                  status: status,
                );

                if (isPast || status == 'cancelled') {
                  past.add(view);
                } else {
                  upcoming.add(view);
                }
              }

              return Stack(
                children: [
                  ListView(
                    padding: EdgeInsets.all(_scale(sw, 12, 20, 28)),
                    children: [
                      if (upcoming.isNotEmpty) _groupSection(context, sw, 'Upcoming', upcoming),
                      if (past.isNotEmpty) _groupSection(context, sw, 'Past', past),
                    ],
                  ),

                  if (_loadingJoin && joinSnap.connectionState == ConnectionState.waiting)
                    Positioned(
                      right: 16,
                      top: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: context.c.surface,
                          borderRadius: BorderRadius.circular(AppRadii.l),
                          boxShadow: AppShadows.card,
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(context.c.primary)),
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
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, double sw, double ts) {
    return AppBar(
      elevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF10B981), Color(0xFF059669)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
      ),
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back_ios_new,
          color: AppColors.onSurfaceInverse,
          size: _scale(sw, 18, 22, 26),
        ),
        onPressed: () => Navigator.maybePop(context),
        tooltip: 'Back',
      ),
      title: Text(
        '🧾 My Bookings',
        style: AppText.sectionTitle.copyWith(color: AppColors.onSurfaceInverse, fontSize: _scale(sw, 16, 18, 20) * ts),
      ),
    );
  }

  // ------- Batched slot fetch for all bookings in view -------
  Future<Map<String, Map<String, dynamic>>> _fetchSlotsForBookings(
      List<QueryDocumentSnapshot> bookingDocs) async {
    // Return cached if already have all.
    final missing = <String, String>{}; // bookingId -> slotId
    for (final b in bookingDocs) {
      if (_slotCacheByBookingId.containsKey(b.id)) continue;
      final bd = b.data() as Map<String, dynamic>;
      final slotId = (bd['slot_id'] ?? '').toString();
      if (slotId.isNotEmpty) {
        missing[b.id] = slotId;
      } else {
        _slotCacheByBookingId[b.id] = {};
      }
    }
    if (missing.isEmpty) return _slotCacheByBookingId;

    if (mounted) setState(() => _loadingJoin = true);
    try {
      // Chunk slotIds (Firestore whereIn limit often 30).
      const chunk = 30;
      final slotIds = missing.values.toSet().toList();
      final fetched = <String, Map<String, dynamic>>{};
      for (var i = 0; i < slotIds.length; i += chunk) {
        final sub = slotIds.sublist(i, (i + chunk > slotIds.length) ? slotIds.length : i + chunk);
        final snap = await FirebaseFirestore.instance
            .collection('slots')
            .where(FieldPath.documentId, whereIn: sub)
            .get();

        for (final s in snap.docs) {
          fetched[s.id] = s.data();
        }
      }

      // Map back into bookingId => slotData
      missing.forEach((bookingId, slotId) {
        _slotCacheByBookingId[bookingId] = fetched[slotId] ?? {};
      });

      return _slotCacheByBookingId;
    } finally {
      if (mounted) setState(() => _loadingJoin = false);
    }
  }

  // ------- UI Sections -------

  Widget _groupSection(BuildContext context, double sw, String title, List<_BookingView> items) {
    final headerPad = _scale(sw, 10, 12, 14);

    return Container(
      margin: EdgeInsets.only(bottom: _scale(sw, 12, 18, 24)),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: BorderRadius.circular(AppRadii.m),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(headerPad),
            decoration: BoxDecoration(
              color: context.c.background,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
              border: Border(bottom: BorderSide(color: AppColors.divider)),
            ),
            child: Row(
              children: [
                Text(title == 'Upcoming' ? '🗓️' : '📜', style: TextStyle(fontSize: _scale(sw, 14, 16, 18))),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$title (${items.length})',
                    style: context.t.bodyMedium?.copyWith(
                      fontSize: _scale(sw, 12, 13, 14),
                      color: AppColors.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...items.map((i) => _bookingCard(context, sw, i)),
        ],
      ),
    );
  }

  Widget _bookingCard(BuildContext context, double sw, _BookingView v) {
    final data = v.bookingData;
    final slot = v.slotData ?? {};
    final pad = _scale(sw, 12, 14, 16);

    final slotTime = (slot['slot_time'] ?? '').toString();
    final vehicleType = (slot['vehicle_type'] ?? data['vehicle_type'] ?? 'Unknown').toString();
    final instructorName = (slot['instructor_name'] ?? data['instructor_name'] ?? 'Instructor').toString();

    final total = (data['total_cost'] is num) ? (data['total_cost'] as num).toDouble() : 0.0;
    final freeByPlan = data['free_by_plan'] == true;
    final status = (data['status'] ?? '').toString();
    final createdAt = _toDate(data['created_at']);

    final slotDay = v.slotDay;
    final start = v.startEnd?.$1;
    final end = v.startEnd?.$2;

    final dateLine = slotDay != null
        ? DateFormat('EEE, d MMM yyyy').format(slotDay)
        : (createdAt != null ? DateFormat('EEE, d MMM yyyy').format(createdAt) : '--');
    final timeLine = (start != null && end != null)
        ? '${DateFormat('h:mm a').format(start)}–${DateFormat('h:mm a').format(end)}'
        : (slotTime.isNotEmpty ? slotTime : '');

    final statusChip = _statusChip(status, freeByPlan);

    return InkWell(
      onTap: () => _showBookingSheet(context, v),
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.neuBg)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dateBadge(slotDay ?? createdAt, sw),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          vehicleType,
                          style: context.t.titleSmall?.copyWith(
                            fontSize: _scale(sw, 14, 15, 16),
                            fontWeight: FontWeight.w700,
                            color: context.c.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      statusChip,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    instructorName,
                    style: context.t.bodySmall?.copyWith(
                      fontSize: _scale(sw, 11, 12, 13),
                      color: AppColors.onSurfaceMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: _scale(sw, 13, 14, 16), color: AppColors.onSurfaceMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          timeLine.isEmpty ? '—' : timeLine,
                          style: context.t.bodyMedium?.copyWith(
                            fontSize: _scale(sw, 12, 13, 14),
                            color: context.c.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: _scale(sw, 13, 14, 16), color: AppColors.onSurfaceMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dateLine,
                          style: context.t.bodyMedium?.copyWith(
                            fontSize: _scale(sw, 12, 13, 14),
                            color: context.c.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  freeByPlan ? 'FREE' : '₹${total.toStringAsFixed(0)}',
                  style: context.t.bodyMedium?.copyWith(
                    fontSize: _scale(sw, 13, 14, 16),
                    fontWeight: FontWeight.w700,
                    color: freeByPlan ? AppColors.success : context.c.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  createdAt != null ? DateFormat('dd/MM').format(createdAt) : '',
                  style: context.t.bodySmall?.copyWith(
                    fontSize: _scale(sw, 10, 11, 12),
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(double sw) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _scale(sw, 16, 20, 28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🧾', style: TextStyle(fontSize: _scale(sw, 56, 64, 72), color: AppColors.onSurfaceFaint)),
            const SizedBox(height: 16),
            Text(
              'You don’t have any bookings yet',
              style: context.t.bodyLarge?.copyWith(fontSize: _scale(sw, 16, 18, 20), color: AppColors.onSurfaceMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('Go back and book a slot to see it here', style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted)),
          ],
        ),
      ),
    );
  }

  // ------- Bottom sheet with details -------

  void _showBookingSheet(BuildContext context, _BookingView v) {
    final data = v.bookingData;
    final slot = v.slotData ?? {};
    final freeByPlan = data['free_by_plan'] == true;
    final total = (data['total_cost'] is num) ? (data['total_cost'] as num).toDouble() : 0.0;

    final createdAt = _toDate(data['created_at']);
    final paidAmount = (data['paid_amount'] is num) ? (data['paid_amount'] as num).toDouble() : 0.0;
    final status = (data['status'] ?? '').toString();

    final distanceKm = _toDouble(data['distance_km']);
    final surcharge = _toDouble(data['surcharge']);
    final vehicleCost = _toDouble(data['vehicle_cost']);
    final additionalCost = _toDouble(data['additional_cost']);

    final slotDay = v.slotDay;
    final start = v.startEnd?.$1;
    final end = v.startEnd?.$2;
    final timeLine = (start != null && end != null)
        ? '${DateFormat('h:mm a').format(start)}–${DateFormat('h:mm a').format(end)}'
        : (slot['slot_time'] ?? '').toString();
    final dateLine = slotDay != null ? DateFormat('EEE, d MMM yyyy').format(slotDay) : '—';

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: context.c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.l))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Booking Details', style: context.t.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: context.c.onSurface)),
                  const Spacer(),
                  _statusChip(status, freeByPlan),
                ],
              ),
              const SizedBox(height: 10),
              _kv('Date', dateLine),
              _kv('Time', timeLine),
              _kv('Vehicle', (slot['vehicle_type'] ?? data['vehicle_type'] ?? '—').toString()),
              _kv('Instructor', (slot['instructor_name'] ?? data['instructor_name'] ?? '—').toString()),
              const SizedBox(height: 10),
              Divider(color: AppColors.divider),
              const SizedBox(height: 10),
              _kv('Vehicle Cost', '₹${vehicleCost.toStringAsFixed(2)}', strike: freeByPlan),
              _kv('Additional Cost', '₹${additionalCost.toStringAsFixed(2)}', strike: freeByPlan),
              if (!freeByPlan && surcharge > 0) _kv('Distance Surcharge', '₹${surcharge.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Total Amount', style: context.t.bodyMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: context.c.onSurface)),
                  Text(
                    freeByPlan ? 'FREE' : '₹${total.toStringAsFixed(2)}',
                    style: context.t.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.success),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (createdAt != null) _kv('Booked On', DateFormat('d MMM, h:mm a').format(createdAt)),
              if (!freeByPlan) _kv('Paid Amount', '₹${paidAmount.toStringAsFixed(2)}'),
              if (distanceKm > 0) _kv('Distance', '${distanceKm.toStringAsFixed(2)} km'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, {bool strike = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              k,
              style: context.t.bodySmall?.copyWith(fontSize: 13, color: AppColors.onSurfaceMuted, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            v,
            style: context.t.bodyMedium?.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              decoration: strike ? TextDecoration.lineThrough : TextDecoration.none,
              decorationThickness: 2,
              decorationColor: AppColors.errFg,
              color: context.c.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  // ------- Small helpers -------

  static double _scale(double width, double small, double medium, double large) {
    if (width >= 1200) return large;
    if (width >= 800) return medium;
    return small;
  }

  Widget _dateBadge(DateTime? d, double sw) {
    if (d == null) {
      return Container(
        width: _scale(sw, 54, 60, 66),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.neuBg,
          borderRadius: BorderRadius.circular(AppRadii.m),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Text('--', style: context.t.bodySmall?.copyWith(fontSize: 12, color: AppColors.onSurfaceFaint)),
            const SizedBox(height: 4),
            Text('--', style: context.t.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w700, color: context.c.onSurface)),
          ],
        ),
      );
    }

    return Container(
      width: _scale(sw, 54, 60, 66),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.okBg,
        borderRadius: BorderRadius.circular(AppRadii.m),
        border: Border.all(color: AppColors.okBg.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMM').format(d).toUpperCase(),
            style: context.t.bodySmall?.copyWith(fontSize: 12, color: AppColors.okFg, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('d').format(d),
            style: context.t.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w800, color: context.c.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status, bool freeByPlan) {
    Color bg = AppColors.neuBg;
    Color fg = AppColors.neuFg;
    String label = status.isEmpty ? 'confirmed' : status;

    switch (label.toLowerCase()) {
      case 'paid':
        bg = AppColors.okBg;
        fg = AppColors.okFg;
        break;
      case 'confirmed':
        bg = AppColors.neuBg;
        fg = AppColors.brand;
        break;
      case 'cancelled':
        bg = AppColors.errBg;
        fg = AppColors.errFg;
        break;
    }

    if (freeByPlan && (label == 'confirmed')) {
      label = 'FREE • confirmed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        label.toUpperCase(),
        style: context.t.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w800, color: fg, letterSpacing: .6),
      ),
    );
  }

  // Convert Firestore Timestamp/DateTime to DateTime?
  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  double _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    try {
      return double.parse(v.toString());
    } catch (_) {
      return 0.0;
    }
  }

  // Slot helpers
  DateTime? _slotDayDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return null;
  }

  // Returns (start, end) DateTime on slotDay if possible
  (DateTime, DateTime)? _parseTimeRange(dynamic slotTime, {DateTime? day}) {
    if (slotTime == null) return null;
    final raw = slotTime.toString();
    final parts = raw.split(' - ');
    if (parts.length != 2) return null;
    try {
      final d = day;
      final s = DateFormat('hh:mm a').parseStrict(parts[0].trim());
      final e = DateFormat('hh:mm a').parseStrict(parts[1].trim());
      if (d != null) {
        final start = DateTime(d.year, d.month, d.day, s.hour, s.minute);
        final end = DateTime(d.year, d.month, d.day, e.hour, e.minute);
        return (start, end);
      } else {
        final now = DateTime.now();
        final start = DateTime(now.year, now.month, now.day, s.hour, s.minute);
        final end = DateTime(now.year, now.month, now.day, e.hour, e.minute);
        return (start, end);
      }
    } catch (_) {
      return null;
    }
  }

  // Build booking "moment" for grouping (prefer end time on slot_day)
  DateTime? _bookingDateTime(Map<String, dynamic>? slot) {
    if (slot == null) return null;
    final day = _slotDayDate(slot['slot_day']);
    final tr = _parseTimeRange(slot['slot_time'], day: day);
    if (day != null && tr != null) return tr.$2; // end time
    return day; // fallback
  }
}

class _BookingView {
  final String bookingId;
  final Map<String, dynamic> bookingData;
  final Map<String, dynamic>? slotData;
  final (DateTime, DateTime)? startEnd;
  final DateTime? slotDay;
  final String status;

  _BookingView({
    required this.bookingId,
    required this.bookingData,
    required this.slotData,
    required this.startEnd,
    required this.slotDay,
    required this.status,
  });
}
