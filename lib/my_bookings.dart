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
  bool _cancelling = false;

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
        stream: FirebaseFirestore.instance.collection('bookings').where('user_id', isEqualTo: user.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}', style: context.t.bodyMedium?.copyWith(color: AppColors.danger)));
          }
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)));
          }

          final docs = List<QueryDocumentSnapshot>.from(snap.data?.docs ?? const []);
          docs.sort((a, b) {
            final ad = _toDate((a.data() as Map<String, dynamic>)['created_at']);
            final bd = _toDate((b.data() as Map<String, dynamic>)['created_at']);
            if (ad == null && bd == null) return 0;
            if (ad == null) return 1;
            if (bd == null) return -1;
            return bd.compareTo(ad);
          });

          if (docs.isEmpty) return _emptyState(sw);

          final now = DateTime.now();
          final List<_BookingView> upcoming = [];
          final List<_BookingView> past = [];

          for (final b in docs) {
            final bData = Map<String, dynamic>.from(b.data() as Map<String, dynamic>);

            // Use slot_time/slot_day/vehicle_type/instructor_name stored on the booking document itself
            // Debug (helpful while testing)
            debugPrint('[_buildBookingView] booking=${b.id} booking.slot_id="${bData['slot_id']}" booking.slot_time="${bData['slot_time'] ?? '(none)'}" slot_day="${bData['slot_day'] ?? '(none)'}" vehicle="${bData['vehicle_type'] ?? '(none)'}" instructor="${bData['instructor_name'] ?? '(none)'}"');

            final when = _bookingDateTime(bData);
            final status = (bData['status'] ?? '').toString().toLowerCase();

            final isPast = when == null ? false : !when.isAfter(now);
            final view = _BookingView(
              bookingId: b.id,
              bookingData: bData,
              // We no longer keep a separate slotData; null indicates nothing extra beyond booking
              slotData: null,
              startEnd: _parseTimeRange(bData['slot_time'], day: _slotDayDate(bData['slot_day'])) ??
                  _parseTimeRange(bData['slot_time'], day: _slotDayDate(bData['slot_day'])),
              slotDay: _slotDayDate(bData['slot_day']),
              status: status,
            );

            if (isPast || status == 'cancelled') {
              past.add(view);
            } else {
              upcoming.add(view);
            }
          }

          return ListView(
            padding: EdgeInsets.all(_scale(sw, 12, 20, 28)),
            children: [
              _infoBanner(sw),
              const SizedBox(height: 12),
              if (upcoming.isNotEmpty) _groupSection(context, sw, 'Upcoming', upcoming),
              if (past.isNotEmpty) _groupSection(context, sw, 'Past', past),
            ],
          );
        },
      ),
    );
  }

  Widget _infoBanner(double sw) {
    return Container(
      padding: EdgeInsets.all(_scale(sw, 12, 14, 16)),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppRadii.s),
        border: Border.all(color: AppColors.warnBg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Refunds (if any) are collected in-hand at the office. Please inform the office about your cancellation after cancelling here.',
              style: context.t.bodySmall?.copyWith(fontSize: _scale(sw, 12, 13, 14), color: AppColors.warnFg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
    final pad = _scale(sw, 12, 14, 16);

    // Now always prefer booking's fields (slot_time/slot_day/vehicle_type/instructor_name)
    final effectiveSlotDay = v.slotDay ?? _slotDayDate(data['slot_day']) ?? _toDate(data['created_at']);
    final effectiveRange = v.startEnd ?? _parseTimeRange(data['slot_time'], day: _slotDayDate(data['slot_day']));

    final vehicleType = (data['vehicle_type'] ?? 'Unknown').toString();
    final instructorName = (data['instructor_name'] ?? 'Instructor').toString();
    final slotTimeRaw = (data['slot_time'] ?? '').toString();

    final total = (data['total_cost'] is num) ? (data['total_cost'] as num).toDouble() : 0.0;
    final freeByPlan = data['free_by_plan'] == true;
    final status = (data['status'] ?? '').toString();
    final createdAt = _toDate(data['created_at']);

    final start = effectiveRange?.$1;
    final end = effectiveRange?.$2;

    final dateLine = effectiveSlotDay != null ? DateFormat('EEE, d MMM yyyy').format(effectiveSlotDay) : (createdAt != null ? DateFormat('EEE, d MMM yyyy').format(createdAt) : '--');
    final timeLine = (start != null && end != null) ? '${DateFormat('h:mm a').format(start)}–${DateFormat('h:mm a').format(end)}' : (slotTimeRaw.isNotEmpty ? slotTimeRaw : '');

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
            _dateBadge(effectiveSlotDay ?? createdAt, sw),
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

  void _showBookingSheet(BuildContext context, _BookingView v) {
    final data = v.bookingData;
    final freeByPlan = data['free_by_plan'] == true;
    final total = (data['total_cost'] is num) ? (data['total_cost'] as num).toDouble() : 0.0;

    final createdAt = _toDate(data['created_at']);
    final paidAmount = (data['paid_amount'] is num) ? (data['paid_amount'] as num).toDouble() : 0.0;
    final status = (data['status'] ?? '').toString();

    final distanceKm = _toDouble(data['distance_km']);
    final surcharge = _toDouble(data['surcharge']);
    final vehicleCost = _toDouble(data['vehicle_cost']);
    final additionalCost = _toDouble(data['additional_cost']);

    // Use booking fields for display
    final slotDay = v.slotDay ?? _slotDayDate(data['slot_day']) ?? _toDate(data['created_at']);
    final start = v.startEnd?.$1 ?? _parseTimeRange(data['slot_time'], day: _slotDayDate(data['slot_day']))?.$1;
    final end = v.startEnd?.$2 ?? _parseTimeRange(data['slot_time'], day: _slotDayDate(data['slot_day']))?.$2;
    final timeLine = (start != null && end != null)
        ? '${DateFormat('h:mm a').format(start)}–${DateFormat('h:mm a').format(end)}'
        : (data['slot_time'] ?? '').toString();
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
              _kv('Vehicle', (data['vehicle_type'] ?? '—').toString()),
              _kv('Instructor', (data['instructor_name'] ?? '—').toString()),
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
              if (status.toLowerCase() != 'cancelled') ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _cancelling
                            ? null
                            : () async {
                                // 1) Ask for confirmation using a dialog
                                final ok = await showDialog<bool>(
                                  context: ctx, // use the bottom sheet context for dialog parent
                                  builder: (dctx) => AlertDialog(
                                    title: Text('Confirm cancellation', style: context.t.titleMedium),
                                    content: Text('Are you sure you want to cancel this booking? Refunds (if any) are collected in-hand at the office. Please inform the office after cancelling.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: Text('No')),
                                      TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: Text('Yes, Cancel')),
                                    ],
                                  ),
                                );

                                if (ok != true) return;

                                // 2) Close the bottom sheet immediately (same effect as tapping outside)
                                try {
                                  if (Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
                                } catch (e) {
                                  debugPrint('Failed to pop bottom sheet: $e');
                                }

                                // 3) Show a simple modal circular progress indicator (no container/text)
                                showDialog<void>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (progressCtx) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                                );

                                // 4) Perform cancellation
                                try {
                                  setState(() => _cancelling = true);
                                  await _cancelBookingAndDelete(v.bookingId, v.bookingData);

                                  // Dismiss progress dialog
                                  try {
                                    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                                  } catch (e) {
                                    debugPrint('Failed to pop progress dialog: $e');
                                  }

                                  if (mounted) _snack('Booking cancelled. Please inform the office for refunds (if any).', color: AppColors.success);
                                } on FirebaseException catch (fe) {
                                  // Dismiss progress dialog
                                  try {
                                    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                                  } catch (e) {
                                    debugPrint('Failed to pop progress dialog on error: $e');
                                  }
                                  _snack('Cancellation failed: ${fe.message ?? fe.code}', color: AppColors.danger);
                                } catch (e, st) {
                                  // Dismiss progress dialog
                                  try {
                                    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
                                  } catch (e2) {
                                    debugPrint('Failed to pop progress dialog on error: $e2');
                                  }
                                  _snack('Cancellation failed: ${e.toString()}', color: AppColors.danger);
                                  debugPrint('Cancellation error: $e\n$st');
                                } finally {
                                  if (mounted) setState(() => _cancelling = false);
                                }
                              },
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_cancelling ? 'Cancelling…' : 'Cancel Booking', style: context.t.bodyMedium?.copyWith(color: AppColors.onSurfaceInverse)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelBookingAndDelete(String bookingId, Map<String, dynamic> bookingData) async {
    final fs = FirebaseFirestore.instance;
    final bookingRef = fs.collection('bookings').doc(bookingId);
    final slotId = (bookingData['slot_id'] ?? '').toString();
    final slotRef = slotId.isNotEmpty ? fs.collection('slots').doc(slotId) : null;
    final userId = (bookingData['user_id'] ?? '').toString();
    final userPlanRef = userId.isNotEmpty ? fs.collection('user_plans').doc(userId) : null;

    await fs.runTransaction((tx) async {
      final bSnap = await tx.get(bookingRef);
      if (!bSnap.exists) return;

      final currentBooking = bSnap.data() as Map<String, dynamic>? ?? {};
      final wasFreeByPlan = (currentBooking['free_by_plan'] == true);

      Map<String, dynamic>? sData;
      if (slotRef != null) {
        final sSnap = await tx.get(slotRef);
        if (sSnap.exists) sData = sSnap.data() as Map<String, dynamic>?;
      }

      Map<String, dynamic>? upData;
      if (wasFreeByPlan && userPlanRef != null) {
        final upSnap = await tx.get(userPlanRef);
        if (upSnap.exists) upData = upSnap.data() as Map<String, dynamic>?;
      }

      // Delete booking doc
      tx.delete(bookingRef);

      // If slot doc references this booking, free it
      if (slotRef != null && sData != null) {
        final bookingIdInSlot = (sData['booking_id'] ?? '').toString();
        if (bookingIdInSlot.isNotEmpty && bookingIdInSlot == bookingRef.id) {
          tx.update(slotRef, {
            'status': 'available',
            'booked_by': FieldValue.delete(),
            'booking_id': FieldValue.delete(),
            'booked_at': FieldValue.delete(),
          });
        }
      }

      // If booking used a free plan slot, decrement user's slots_used
      if (wasFreeByPlan && userPlanRef != null && upData != null) {
        final used = (upData['slots_used'] ?? 0);
        int usedInt = 0;
        if (used is num) usedInt = used.toInt();
        final next = (usedInt > 0) ? usedInt - 1 : 0;
        tx.update(userPlanRef, {'slots_used': next});
      }
    });
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse),
        ),
        backgroundColor: color ?? AppColors.onSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
        margin: const EdgeInsets.all(12),
      ),
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

  // Improved slot day parser: accepts Timestamp, DateTime, numeric epoch, and several string formats
  DateTime? _slotDayDate(dynamic v) {
    if (v == null) return null;

    // Firestore Timestamp -> DateTime
    if (v is Timestamp) return v.toDate();

    // Already a DateTime
    if (v is DateTime) return v;

    // If it's a numeric millisecondsSinceEpoch stored as num/string
    if (v is num) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v.toInt());
      } catch (_) {}
    }
    if (v is String) {
      final s = v.trim();
      // 1) Try ISO-like parse first (DateTime.parse accepts many formats)
      try {
        final dt = DateTime.parse(s);
        return dt;
      } catch (_) {}

      // 2) Common Firestore toString() format: "September 17, 2025 at 12:00:00 AM UTC+5:30"
      //    -> strip the " at ..." suffix and parse "September 17, 2025"
      try {
        // use case-insensitive split for " at "
        final parts = s.split(RegExp(r'\s+at\s+', caseSensitive: false));
        final dateOnly = parts.isNotEmpty ? parts[0].trim() : s;
        final parsed = DateFormat('MMMM d, yyyy').parseStrict(dateOnly);
        return parsed;
      } catch (_) {}

      // 3) Try a forgiving parse by removing timezone suffix after last space
      try {
        final withoutZone = s.replaceAll(RegExp(r'UTC[^\s]*'), '').trim();
        final parts2 = withoutZone.split(RegExp(r'\s+at\s+', caseSensitive: false));
        final dateOnly2 = parts2.isNotEmpty ? parts2[0].trim() : withoutZone;
        final parsed2 = DateFormat('MMMM d, yyyy').parse(dateOnly2);
        return parsed2;
      } catch (_) {}
    }

    return null;
  }

  // Robust time-range parser that normalizes dashes and AM/PM spacing
  (DateTime, DateTime)? _parseTimeRange(dynamic slotTime, {DateTime? day}) {
    if (slotTime == null) return null;

    String raw = slotTime.toString().trim();

    // Normalize different dash-like characters to a single hyphen
    raw = raw.replaceAll(RegExp(r'[–—−]'), '-');

    // Normalize various AM/PM spellings and ensure a space before AM/PM
    // Handles "10:00am", "10am", "10 AM", etc.
    raw = raw.replaceAllMapped(
      RegExp(r'(\d{1,2}(?::\d{1,2})?)(\s?)(am|pm)\b', caseSensitive: false),
      (m) {
        final timePart = m[1]!.trim();
        final ampm = (m[3] ?? '').toUpperCase();
        if (!timePart.contains(':')) {
          return '$timePart:00 $ampm';
        }
        return '$timePart $ampm';
      },
    );

    // Split on the normalized hyphen, allowing spaces around it
    final parts = raw.split(RegExp(r'\s*-\s*'));
    if (parts.length != 2) return null;

    final formats = [
      DateFormat('h:mm a'),
      DateFormat('hh:mm a'),
      // fallback formats
      DateFormat('h:m a'),
      DateFormat('h a'),
    ];

    DateTime? parseOne(String t) {
      final s = t.trim();
      for (final f in formats) {
        try {
          return f.parseStrict(s);
        } catch (_) {}
      }
      // last-resort try DateTime.parse (accepts ISO and some other formats)
      try {
        return DateTime.parse(s);
      } catch (_) {}
      return null;
    }

    final sParsed = parseOne(parts[0]);
    final eParsed = parseOne(parts[1]);
    if (sParsed == null || eParsed == null) return null;

    if (day != null) {
      final start = DateTime(day.year, day.month, day.day, sParsed.hour, sParsed.minute);
      final end = DateTime(day.year, day.month, day.day, eParsed.hour, eParsed.minute);
      return (start, end);
    } else {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, sParsed.hour, sParsed.minute);
      final end = DateTime(now.year, now.month, now.day, eParsed.hour, eParsed.minute);
      return (start, end);
    }
  }

  DateTime? _bookingDateTime(Map<String, dynamic>? bookingData) {
    if (bookingData == null) return null;
    final day = _slotDayDate(bookingData['slot_day']);
    final tr = _parseTimeRange(bookingData['slot_time'], day: day);
    if (day != null && tr != null) return tr.$2;
    return day;
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
