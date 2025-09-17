// lib/instructor_slots_block.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Import your design tokens & theme helpers — adjust path if needed
import 'theme/app_theme.dart';

class InstructorSlotsBlock extends StatefulWidget {
  const InstructorSlotsBlock({super.key});

  @override
  State<InstructorSlotsBlock> createState() => _InstructorSlotsBlockState();
}

class _InstructorSlotsBlockState extends State<InstructorSlotsBlock> {
  DateTime selectedDate = _atMidnight(DateTime.now());
  String? _uid;
  bool _identityLoaded = false;

  static const int serverLimit = 500;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
  }

  Future<void> _loadIdentity() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      setState(() {
        _uid = user?.uid;
        _identityLoaded = true;
      });
    } catch (e) {
      setState(() {
        _uid = null;
        _identityLoaded = true;
      });
      debugPrint('Failed to load identity: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sw = media.size.width;
    final ts = media.textScaleFactor.clamp(0.9, 1.2);

    return Scaffold(
      backgroundColor: context.c.background,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            elevation: 0,
            backgroundColor: Colors.transparent,
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: AppGradients.brandHero,
                boxShadow: AppShadows.card,
              ),
            ),
            leading: IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.onSurfaceInverse,
                size: _scale(sw, 18, 22, 26),
              ),
              tooltip: 'Back',
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
            title: Text(
              'My Booked Sessions',
              style: TextStyle(
                color: AppColors.onSurfaceInverse,
                fontWeight: FontWeight.w600,
                fontSize: _scale(sw, 16, 18, 20) * ts,
              ),
            ),
          ),
        ],
        body: Column(
          children: [
            _buildDateSelector(context),
            _buildAdminNoticeBanner(context),
            Expanded(
              child: Container(
                color: context.c.background,
                child: _buildBookingsContent(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Date selector ─────────────────────────
  Widget _buildDateSelector(BuildContext context) {
    final media = MediaQuery.of(context);
    final sw = media.size.width;
    final ts = media.textScaleFactor.clamp(0.9, 1.2);

    final barPaddingH = _scale(sw, 16, 20, 28);
    final barPaddingV = _scale(sw, 10, 12, 14);
    final barHeight = _scale(sw, 64, 70, 82);
    final pillPadH = _scale(sw, 8, 10, 12);
    final pillPadV = _scale(sw, 4, 6, 8);
    final pillGap = _scale(sw, 4, 6, 8);

    final dowSize = _scale(sw, 9, 10, 11) * ts;
    final daySize = _scale(sw, 14, 16, 18) * ts;
    final monSize = _scale(sw, 9, 10, 11) * ts;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: barPaddingH, vertical: barPaddingV),
      decoration: BoxDecoration(
        color: context.c.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SizedBox(
        height: barHeight,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: 7,
          itemBuilder: (context, index) {
            final date = _atMidnight(DateTime.now().add(Duration(days: index)));
            final isSelected = DateUtils.isSameDay(date, selectedDate);

            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedDate = date;
                });
              },
              child: Container(
                margin: EdgeInsets.only(right: index == 6 ? 0 : pillGap),
                padding: EdgeInsets.symmetric(horizontal: pillPadH, vertical: pillPadV),
                constraints: BoxConstraints(
                  minWidth: _scale(sw, 45, 50, 55),
                  maxWidth: _scale(sw, 65, 70, 75),
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.danger : context.c.surface,
                  border: Border.all(
                    color: isSelected ? AppColors.danger : AppColors.divider,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.m),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: dowSize,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface.withOpacity(0.7),
                      ),
                    ),
                    SizedBox(height: _scale(sw, 1, 1, 2)),
                    Text(
                      DateFormat('d').format(date),
                      style: TextStyle(
                        fontSize: daySize,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface,
                      ),
                    ),
                    SizedBox(height: _scale(sw, 1, 1, 2)),
                    Text(
                      DateFormat('MMM').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: monSize,
                        color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ───────────────────────── Admin notice banner ─────────────────────────
  Widget _buildAdminNoticeBanner(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: _scale(sw, 14, 16, 20), vertical: _scale(sw, 10, 12, 14)),
      decoration: BoxDecoration(
        color: context.c.surfaceVariant ?? context.c.surface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.onSurfaceMuted, size: _scale(sw, 18, 20, 22)),
          SizedBox(width: _scale(sw, 10, 12, 14)),
          Expanded(
            child: Text(
              'Important: When you cancel a booked slot, please inform the admin office.',
              style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted, fontSize: _scale(sw, 13, 14, 15)),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Stream + UI ─────────────────────────
  Widget _buildBookingsContent(BuildContext context) {
    if (!_identityLoaded) {
      return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)));
    }
    if (_uid == null) {
      return _buildEmptyState(context, 'Please sign in to view your booked sessions.');
    }

    final bookingsQuery = FirebaseFirestore.instance.collection('bookings').limit(serverLimit).snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: bookingsQuery,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyState(context, 'Error: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)));
        }

        final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? const []);

        return FutureBuilder<List<_InstructorBookingDoc>>(
          future: _enrichBookingDocs(docs),
          builder: (context, enrichedSnap) {
            if (enrichedSnap.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)));
            }
            if (enrichedSnap.hasError) {
              return _buildEmptyState(context, 'Error preparing bookings: ${enrichedSnap.error}');
            }

            final enriched = enrichedSnap.data ?? [];

            final sel = _atMidnight(selectedDate);
            final filtered = <_InstructorBookingDoc>[];

            for (final d in enriched) {
              final m = d.data;
              final status = (m['status'] ?? '').toString().toLowerCase();
              if (!(status == 'booked' || status == 'confirmed')) continue;

              final parsed = _toDate(m['slot_day']);
              if (parsed != null && DateUtils.isSameDay(parsed, sel)) {
                final bookingInstructor = (m['instructor_user_id'] ?? '').toString();
                if (bookingInstructor.isNotEmpty && bookingInstructor == _uid) {
                  filtered.add(d);
                }
              }
            }

            filtered.sort((a, b) {
              final sa = _parseStartTime((a.data['slot_time'] ?? '').toString(), useDate: selectedDate);
              final sb = _parseStartTime((b.data['slot_time'] ?? '').toString(), useDate: selectedDate);
              return sa.compareTo(sb);
            });

            if (filtered.isEmpty) {
              return _buildEmptyState(context, 'No bookings for ${DateFormat('EEEE, MMM d').format(selectedDate)}');
            }

            final grouped = <String, List<_InstructorBookingDoc>>{
              'Morning': [],
              'Afternoon': [],
              'Evening': [],
            };

            for (final b in filtered) {
              final start = _parseStartTime((b.data['slot_time'] ?? '').toString(), useDate: selectedDate);
              final h = start.hour;
              if (h >= 6 && h < 12) {
                grouped['Morning']!.add(b);
              } else if (h >= 12 && h < 17) {
                grouped['Afternoon']!.add(b);
              } else {
                grouped['Evening']!.add(b);
              }
            }
            grouped.removeWhere((k, v) => v.isEmpty);

            final sw = MediaQuery.of(context).size.width;
            final outerMargin = _scale(sw, 12, 20, 28);
            final headerPad = _scale(sw, 10, 12, 14);

            return Container(
              margin: EdgeInsets.all(outerMargin),
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
                      border: Border(bottom: BorderSide(color: AppColors.divider)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Booked sessions for ${DateFormat('EEEE, d MMM').format(selectedDate)}',
                            style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted, fontSize: _scale(sw, 12, 13, 14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: grouped.entries.map((e) => _buildBookingGroup(context, e.key, e.value)).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<List<_InstructorBookingDoc>> _enrichBookingDocs(List<QueryDocumentSnapshot> docs) async {
    final fs = FirebaseFirestore.instance;
    final futures = <Future<_InstructorBookingDoc>>[];

    for (final d in docs) {
      futures.add(Future(() async {
        final m = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
        final slotId = (m['slot_id'] ?? '').toString();
        final studentId = (m['student_id'] ?? m['user_id'] ?? '').toString();

        if (slotId.isNotEmpty) {
          try {
            final slotSnap = await fs.collection('slots').doc(slotId).get();
            if (slotSnap.exists) {
              final slotData = slotSnap.data() as Map<String, dynamic>? ?? {};
              if ((slotData['instructor_user_id'] ?? '').toString().isNotEmpty) {
                m['instructor_user_id'] = slotData['instructor_user_id'];
              }
              if ((slotData['slot_time'] ?? '').toString().isNotEmpty) {
                m.putIfAbsent('slot_time', () => slotData['slot_time']);
              }
              if ((slotData['vehicle_type'] ?? '').toString().isNotEmpty) {
                m.putIfAbsent('vehicle_type', () => slotData['vehicle_type']);
              }
              if (slotData['slot_cost'] != null) {
                m.putIfAbsent('slot_cost', () => slotData['slot_cost']);
              }
            }
          } catch (e) {
            debugPrint('Slot fetch failed for $slotId: $e');
          }
        }

        if (studentId.isNotEmpty) {
          try {
            final userSnap = await fs.collection('users').doc(studentId).get();
            if (userSnap.exists) {
              final userData = userSnap.data() as Map<String, dynamic>? ?? {};
              final displayName = (userData['name'] ??
                      userData['full_name'] ??
                      userData['display_name'] ??
                      userData['username'] ??
                      userData['user_name'] ??
                      'Student')
                  .toString();
              m['user_name'] = displayName;
            }
          } catch (e) {
            debugPrint('User fetch failed for $studentId: $e');
          }
        }

        return _InstructorBookingDoc(id: d.id, data: m, ref: d.reference);
      }));
    }

    return Future.wait(futures);
  }

  Widget _buildBookingGroup(BuildContext context, String period, List<_InstructorBookingDoc> items) {
    final sw = MediaQuery.of(context).size.width;
    final titleSize = _scale(sw, 13, 14, 16);
    final groupPad = _scale(sw, 12, 16, 20);

    String timeRange = '';
    switch (period) {
      case 'Morning':
        timeRange = '(6:00 AM - 12:00 PM)';
        break;
      case 'Afternoon':
        timeRange = '(12:00 PM - 5:00 PM)';
        break;
      case 'Evening':
        timeRange = '(5:00 PM - 10:00 PM)';
        break;
    }

    return Container(
      padding: EdgeInsets.all(groupPad),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.neuBg))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$period $timeRange',
            style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w600, color: context.c.onSurface),
          ),
          const SizedBox(height: 12),
          Column(
            children: items.map((b) => _buildBookingCard(context, b)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(BuildContext context, _InstructorBookingDoc bdoc) {
    // kept name _bookingCard originally; to avoid confusion rename internal call above
    return _bookingCard(context, bdoc);
  }

  Widget _bookingCard(BuildContext context, _InstructorBookingDoc bdoc) {
    final sw = MediaQuery.of(context).size.width;
    final data = bdoc.data;

    final slotTime = (data['slot_time'] ?? '').toString();
    final slotDay = _toDate(data['slot_day']) ?? _atMidnight(DateTime.now());
    final userName = (data['user_name'] ?? data['user_display_name'] ?? data['student_name'] ?? 'Student').toString();
    final vehicle = (data['vehicle_type'] ?? 'Vehicle').toString();
    final instructor = (data['instructor_name'] ?? 'Instructor').toString();
    final total = (data['total_cost'] is num) ? (data['total_cost'] as num).toDouble() : 0.0;

    final dateLine = DateFormat('EEE, d MMM yyyy').format(slotDay);
    final timeLine = slotTime.isNotEmpty ? slotTime : '--';

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_scale(sw, 12, 14, 16)),
      decoration: BoxDecoration(
        color: context.c.surface,
        borderRadius: BorderRadius.circular(AppRadii.s),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // top row: student + amount
          Row(
            children: [
              Expanded(
                child: Text(
                  userName,
                  style: context.t.titleSmall?.copyWith(
                    fontSize: _scale(sw, 14, 15, 16),
                    fontWeight: FontWeight.w700,
                    color: context.c.onSurface,
                  ),
                ),
              ),
              Text(
                freeOrAmount(data) ? 'FREE' : '₹${total.toStringAsFixed(2)}',
                style: context.t.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: freeOrAmount(data) ? AppColors.success : context.c.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 8),
              Text(dateLine, style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted)),
              const SizedBox(width: 16),
              Icon(Icons.schedule, size: 14, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 8),
              Text(timeLine, style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.directions_car, size: 14, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 8),
              Text(vehicle, style: context.t.bodySmall?.copyWith(color: context.c.onSurface)),
              const SizedBox(width: 16),
              Icon(Icons.person, size: 14, color: AppColors.onSurfaceMuted),
              const SizedBox(width: 8),
              Text(instructor, style: context.t.bodySmall?.copyWith(color: context.c.onSurface)),
            ],
          ),
          const SizedBox(height: 8),
          // cancel button bottom-right
          Row(
            children: [
              Expanded(child: Container()),
              ElevatedButton(
                onPressed: () => _onCancelBookingPressed(context, bdoc),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Text('Cancel', style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceInverse)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool freeOrAmount(Map<String, dynamic> data) {
    return (data['free_by_plan'] == true);
  }

  Future<void> _onCancelBookingPressed(BuildContext context, _InstructorBookingDoc bdoc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Confirm cancellation', style: context.t.titleMedium),
        content: Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('No')),
          TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (ok != true) return;

    // Show progress
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _cancelBookingInstructorFlow(bdoc);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(); // remove progress
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking cancelled, slot deleted, student benefit granted'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancellation failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // Fixed transaction: read all docs first, then perform writes (Firestore requires reads before writes)
  Future<void> _cancelBookingInstructorFlow(_InstructorBookingDoc bdoc) async {
    final fs = FirebaseFirestore.instance;
    final bookingRef = bdoc.ref;
    final bookingData = bdoc.data;
    final slotId = (bookingData['slot_id'] ?? '').toString();
    final slotRef = slotId.isNotEmpty ? fs.collection('slots').doc(slotId) : null;
    final userId = (bookingData['student_id'] ?? bookingData['user_id'] ?? '').toString();
    final userRef = userId.isNotEmpty ? fs.collection('users').doc(userId) : null;

    await fs.runTransaction((tx) async {
      // READS first
      final bSnap = await tx.get(bookingRef);
      DocumentSnapshot<Map<String, dynamic>>? sSnap;
      DocumentSnapshot<Map<String, dynamic>>? uSnap;

      if (slotRef != null) {
        sSnap = await tx.get(slotRef);
      }
      if (userRef != null) {
        uSnap = await tx.get(userRef);
      }

      if (!bSnap.exists) return;

      // WRITES after all reads
      tx.delete(bookingRef);

      if (sSnap != null && sSnap.exists) {
        tx.delete(slotRef!);
      }

      if (uSnap != null && uSnap.exists) {
        tx.update(userRef!, {'free_benefit': FieldValue.increment(1)});
      }
    });
  }

  Widget _buildEmptyState(BuildContext context, String msg) {
    final sw = MediaQuery.of(context).size.width;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _scale(sw, 16, 20, 28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📅', style: TextStyle(fontSize: _scale(sw, 56, 64, 72), color: AppColors.onSurfaceFaint)),
            const SizedBox(height: 16),
            Text(msg, style: context.t.bodyMedium?.copyWith(fontSize: _scale(sw, 16, 18, 20), color: AppColors.onSurfaceMuted), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  static double _scale(double width, double small, double medium, double large) {
    if (width >= 1200) return large;
    if (width >= 800) return medium;
    return small;
  }

  DateTime _parseStartTime(String slotTime, {DateTime? useDate}) {
    try {
      final start = slotTime.split(' - ').first.trim();
      final t = DateFormat('hh:mm a').parseStrict(start);
      final d = useDate ?? selectedDate;
      return DateTime(d.year, d.month, d.day, t.hour, t.minute);
    } catch (_) {
      return DateTime(1970);
    }
  }

  DateTime? _toDate(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is num) {
      final n = v.toInt();
      if (n <= 10000000000) {
        return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      } else {
        return DateTime.fromMillisecondsSinceEpoch(n);
      }
    }
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {
        try {
          return DateFormat('MMMM d, yyyy').parseLoose(v);
        } catch (_) {}
      }
    }
    return null;
  }
}

class _InstructorBookingDoc {
  final String id;
  final Map<String, dynamic> data;
  final DocumentReference ref;

  _InstructorBookingDoc({required this.id, required this.data, required this.ref});
}
