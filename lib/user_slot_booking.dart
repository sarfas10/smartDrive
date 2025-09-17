// lib/user_slot_booking.dart
// View available slots for a selected date and allow user to book a slot.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_drive/booking.dart';
import 'package:smart_drive/my_bookings.dart'; // ← NEW: navigate target

class UserSlotBooking extends StatefulWidget {
  const UserSlotBooking({super.key});

  @override
  State<UserSlotBooking> createState() => _UserSlotBookingState();
}

class _UserSlotBookingState extends State<UserSlotBooking> {
  DateTime selectedDate = _atMidnight(DateTime.now());
  String? selectedSlotId;
  bool _isBooking = false;

  // Horizontal date scroller (infinite-forward feel)
  final ScrollController _dateScroll = ScrollController();

  // Debounce timer for taps on date pills
  Timer? _dateDebounce;

  // ── NEW: bookings batching + cache ─────────────────────────────────────────
  // Cache booked maps per selected date key (yyyy-mm-dd)
  final Map<String, Map<String, bool>> _bookedCacheByDay = {};
  bool _bookedLoading = false;
  String get _dayKey => DateFormat('yyyy-MM-dd').format(selectedDate);

  @override
  void dispose() {
    _dateScroll.dispose();
    _dateDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sw = media.size.width;
    final ts = media.textScaleFactor.clamp(0.9, 1.2);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          SliverAppBar(
            floating: true,
            snap: true,
            pinned: false,
            elevation: 0,
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
              icon: Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: _scale(sw, 18, 22, 26)),
              tooltip: 'Back',
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
            title: Text(
              '📅 Book Driving Slot',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: _scale(sw, 16, 18, 20) * ts,
              ),
            ),

            // ── NEW: "My Bookings" action button ─────────────────────────────
            actions: [
              Padding(
                padding: EdgeInsets.only(right: _scale(sw, 8, 12, 16)),
                child: _MyBookingsActionButton(sw: sw, ts: ts),
              ),
            ],
          ),
        ],
        body: Column(
          children: [
            _buildDateSelector(context),
            Expanded(
              child: Container(
                color: const Color(0xFFFAFBFC),
                child: _buildSlotsContent(context),
              ),
            ),
            if (selectedSlotId != null) _buildBookingBar(context),
          ],
        ),
      ),
    );
  }

  // ————————————————— UI: Date selector —————————————————
  Widget _buildDateSelector(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final media = MediaQuery.of(context);
      final sw = media.size.width;
      final ts = media.textScaleFactor.clamp(0.9, 1.2);

      // Container paddings/heights
      final barPaddingH = _scale(sw, 16, 20, 28);
      final barPaddingV = _scale(sw, 10, 12, 14);
      final barHeight = _scale(sw, 64, 70, 82);

      // Visual sizing for cards
      final gap = _scale(sw, 6, 8, 10);
      final minCard = _scale(sw, 60, 68, 76);
      final desired = _scale(sw, 72, 80, 92);

      final contentWidth = constraints.maxWidth - barPaddingH * 2;
      final rawCount =
          ((contentWidth + gap) / (desired + gap)).floor().clamp(5, 14);
      final totalGaps = gap * (rawCount - 1);
      final cardWidth =
          ((contentWidth - totalGaps) / rawCount).clamp(minCard, 160.0);

      // Typography
      final pillPadH = _scale(sw, 8, 10, 12);
      final pillPadV = _scale(sw, 4, 6, 8);
      final dowSize = _scale(sw, 9, 10, 11) * ts;
      final daySize = _scale(sw, 14, 16, 18) * ts;
      final monSize = _scale(sw, 9, 10, 11) * ts;

      DateTime dateForIndex(int index) {
        // First = today (midnight), then +index days
        final todayMid = _atMidnight(DateTime.now());
        return _atMidnight(todayMid.add(Duration(days: index)));
      }

      void scrollToIndex(int index) {
        final itemExtent = cardWidth + gap;
        final target = index * itemExtent;
        _dateScroll.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }

      Widget buildCard(int index) {
        final date = dateForIndex(index);
        final isSelected = DateUtils.isSameDay(date, selectedDate);

        return SizedBox(
          width: cardWidth,
          child: GestureDetector(
            onTap: () {
              // Use a short debounce so quick taps don't thrash fetching,
              // but keep it short for snappy UI.
              _dateDebounce?.cancel();
              _dateDebounce = Timer(const Duration(milliseconds: 80), () {
                if (!mounted) return;

                setState(() {
                  selectedDate = date;
                  selectedSlotId = null;
                });

                // Non-blocking prefetch for adjacent days to improve perceived responsiveness
                _prefetchAdjacentDays(date);
              });

              // Snap scroll to center the tapped pill
              scrollToIndex(index);
            },
            child: Container(
              margin: EdgeInsets.only(right: gap),
              padding:
                  EdgeInsets.symmetric(horizontal: pillPadH, vertical: pillPadV),
              decoration: BoxDecoration(
                color:
                    isSelected ? const Color(0xFF10B981) : const Color(0xFFF8F9FA),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF10B981)
                      : const Color(0xFFE5E7EB),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('EEE').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: dowSize,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : Colors.black.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('d').format(date),
                    style: TextStyle(
                      fontSize: daySize,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('MMM').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: monSize,
                      color: isSelected
                          ? Colors.white
                          : Colors.black.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return Container(
        padding:
            EdgeInsets.symmetric(horizontal: barPaddingH, vertical: barPaddingV),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: SizedBox(
          height: barHeight,
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (_) {
              // Snap to nearest item so pills don’t stop half-visible.
              final itemExtent = cardWidth + gap;
              if (itemExtent <= 0) return false;
              final targetIndex = (_dateScroll.offset / itemExtent).round();
              final targetOffset = targetIndex * itemExtent;
              _dateScroll.animateTo(
                targetOffset,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
              return true;
            },
            child: ListView.builder(
              controller: _dateScroll,
              scrollDirection: Axis.horizontal,
              itemBuilder: (_, index) => buildCard(index),
              // Very large upper bound → effectively infinite forward scroll
              itemCount: 1000000,
            ),
          ),
        ),
      );
    });
  }

  // ————————————————— Firestore stream + list —————————————————
  Widget _buildSlotsContent(BuildContext context) {
    final ts = Timestamp.fromDate(selectedDate);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('slots')
          .where('slot_day', isEqualTo: ts)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs =
            List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? const []);

        if (docs.isEmpty) {
          return _buildEmptyState(context);
        }

        // Sort by parsed start time
        docs.sort((a, b) {
          final sa = _parseStartTime(
              (a.data() as Map)['slot_time']?.toString() ?? '');
          final sb = _parseStartTime(
              (b.data() as Map)['slot_time']?.toString() ?? '');
          return sa.compareTo(sb);
        });

        // Group by period
        final grouped = _groupSlotsByTimePeriod(docs);

        final media = MediaQuery.of(context);
        final sw = media.size.width;
        final outerMargin = _scale(sw, 12, 20, 28);
        final headerPad = _scale(sw, 10, 12, 14);

        // ── NEW: stream bookings for selectedDate so UI updates live ─────────
        final bookingsStream = FirebaseFirestore.instance
            .collection('bookings')
            .where('slot_day', isEqualTo: ts)
            .where('status', whereIn: ['booked', 'confirmed'])
            .snapshots();

        return StreamBuilder<QuerySnapshot>(
          stream: bookingsStream,
          builder: (context, bSnap) {
            // Build bookedMap from bookings snapshot; slot_id -> true
            final Map<String, bool> bookedMap = {};

            if (bSnap.hasData) {
              for (final doc in bSnap.data!.docs) {
                final bd = doc.data() as Map<String, dynamic>;
                final sid = (bd['slot_id'] ?? '').toString();
                if (sid.isNotEmpty) bookedMap[sid] = true;
              }
            }

            // If we didn't get data yet and have a cache, use cached map for snappy UI:
            final cacheKey = DateFormat('yyyy-MM-dd').format(selectedDate);
            if ((bSnap.connectionState == ConnectionState.waiting || !bSnap.hasData) &&
                _bookedCacheByDay.containsKey(cacheKey)) {
              final cached = _bookedCacheByDay[cacheKey]!;
              // overlay cached known trues onto bookedMap (so later stream results can override)
              for (final e in cached.entries) {
                if (e.value) bookedMap[e.key] = true;
              }
            }

            // Also mark any slot IDs present as false if absent (for deterministic lookups)
            for (final sdoc in docs) {
              final sdata = sdoc.data() as Map<String, dynamic>;
              final sid = (sdata['slot_id'] ?? sdoc.id).toString();
              bookedMap.putIfAbsent(sid, () => false);
            }

            // Cache fresh result (optional)
            if (bSnap.hasData) {
              final Map<String, bool> fresh = {};
              for (final e in bookedMap.entries) {
                if (e.value) fresh[e.key] = true;
              }
              _bookedCacheByDay[cacheKey] = fresh;
            }

            return Stack(
              children: [
                Container(
                  margin: EdgeInsets.all(outerMargin),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: EdgeInsets.all(headerPad),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text('🎯',
                                style: TextStyle(
                                    fontSize: _scale(sw, 14, 16, 18))),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Available slots for ${DateFormat('EEEE, d MMM').format(selectedDate)} - Select your preferred time',
                                style: TextStyle(
                                  fontSize: _scale(sw, 12, 13, 14),
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Slots
                      Expanded(
                        child: ListView(
                          children: grouped.entries
                              .map((e) => _buildTimeSlotGroup(
                                    context,
                                    e.key,
                                    e.value,
                                    bookedMap,
                                  ))
                              .toList(),
                        ),
                      ),
                    ],
                  ),
                ),

                // Subtle top-right progress while booked map resolves (first time)
                if ((bSnap.connectionState == ConnectionState.waiting) &&
                    _bookedLoading)
                  Positioned(
                    right: 16,
                    top: 16,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 6)
                        ],
                        border: Border.all(color: Color(0xFFE5E7EB)),
                      ),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
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

  /// Prefetch bookings maps for adjacent dates to reduce perceived latency when user navigates.
  /// This is non-blocking and will not override an existing cache for a day.
  void _prefetchAdjacentDays(DateTime centerDay) {
    final candidates = [
      centerDay.add(const Duration(days: 1)),
      centerDay.add(const Duration(days: 2)),
      // If you want previous day too, include centerDay.subtract(const Duration(days: 1))
    ];

    for (final d in candidates) {
      final key = DateFormat('yyyy-MM-dd').format(d);
      if (_bookedCacheByDay.containsKey(key)) continue; // already cached
      // fire and forget
      _fetchBookingsForDay(d).catchError((e) {
        debugPrint('prefetch bookings failed for $d: $e');
      });
    }
  }

  /// Query bookings for a specific slot_day (Firestore Timestamp) and store slot_id -> true
  /// in the per-day cache. This doesn't require slot docs; the UI will fill absent keys to false.
  Future<void> _fetchBookingsForDay(DateTime day) async {
    final key = DateFormat('yyyy-MM-dd').format(day);
    // If already cached by another inflight call, return early
    if (_bookedCacheByDay.containsKey(key)) return;

    final ts = Timestamp.fromDate(_atMidnight(day));
    if (mounted) setState(() => _bookedLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('bookings')
          .where('slot_day', isEqualTo: ts)
          .where('status', whereIn: ['booked', 'confirmed'])
          .get();

      final Map<String, bool> map = {};
      for (final doc in snap.docs) {
        final bd = doc.data() as Map<String, dynamic>;
        final sid = (bd['slot_id'] ?? '').toString();
        if (sid.isNotEmpty) map[sid] = true;
      }

      // Store map (UI will put false defaults for missing slots)
      _bookedCacheByDay[key] = map;
    } catch (e) {
      debugPrint('Error fetching bookings for $key: $e');
      // don't set cache on error so we can retry later
    } finally {
      if (mounted) setState(() => _bookedLoading = false);
    }
  }

  /// NEW: Batched fetch of bookings for the given slots using whereIn (<=30 per chunk).
  /// Returns map<slot_id, isBooked> and caches per day.
  Future<Map<String, bool>> _fetchBookedMapBatched(
      List<QueryDocumentSnapshot> docs) async {
    // If cached for this day, return immediately.
    if (_bookedCacheByDay.containsKey(_dayKey)) {
      return _bookedCacheByDay[_dayKey]!;
    }

    // Build list of slotIds present in the UI for the selected day.
    final List<String> slotIds = [];
    for (final d in docs) {
      final data = d.data() as Map<String, dynamic>;
      final sid = (data['slot_id'] ?? d.id).toString();
      slotIds.add(sid);
    }
    if (slotIds.isEmpty) {
      _bookedCacheByDay[_dayKey] = const {};
      return const {};
    }

    if (mounted) setState(() => _bookedLoading = true);
    try {
      // Chunk into groups of up to 30 (Firestore whereIn limit).
      const int chunkSize = 30;
      final List<List<String>> chunks = [];
      for (var i = 0; i < slotIds.length; i += chunkSize) {
        chunks.add(slotIds.sublist(
            i, i + chunkSize > slotIds.length ? slotIds.length : i + chunkSize));
      }

      final Map<String, bool> booked = {};
      for (final chunk in chunks) {
        final snap = await FirebaseFirestore.instance
            .collection('bookings')
            .where('slot_id', whereIn: chunk)
            .where('status', whereIn: ['booked', 'confirmed'])
            .get();

        for (final b in snap.docs) {
          final bd = b.data();
          final sid = (bd['slot_id'] ?? '').toString();
          if (sid.isNotEmpty) booked[sid] = true;
        }
      }

      // Mark all others as not booked.
      for (final sid in slotIds) {
        booked.putIfAbsent(sid, () => false);
      }

      // Cache result for this day key.
      _bookedCacheByDay[_dayKey] = booked;
      return booked;
    } finally {
      if (mounted) setState(() => _bookedLoading = false);
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _scale(sw, 16, 20, 28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📅',
                style: TextStyle(
                    fontSize: _scale(sw, 56, 64, 72), color: Colors.grey)),
            const SizedBox(height: 16),
            Text(
              'No slots available for ${DateFormat('EEEE, MMM d').format(selectedDate)}',
              style: TextStyle(
                  fontSize: _scale(sw, 16, 18, 20), color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text('Try selecting a different date',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ————————————————— Grouping —————————————————
  Map<String, List<QueryDocumentSnapshot>> _groupSlotsByTimePeriod(
      List<QueryDocumentSnapshot> slots) {
    final Map<String, List<QueryDocumentSnapshot>> grouped = {
      'Morning': [],
      'Afternoon': [],
      'Evening': [],
    };

    for (final slot in slots) {
      final data = slot.data() as Map<String, dynamic>;
      final start = _parseStartTime(data['slot_time']?.toString() ?? '');
      final h = start.hour;

      if (h >= 6 && h < 12) {
        grouped['Morning']!.add(slot);
      } else if (h >= 12 && h < 17) {
        grouped['Afternoon']!.add(slot);
      } else {
        grouped['Evening']!.add(slot);
      }
    }

    grouped.removeWhere((_, v) => v.isEmpty);
    return grouped;
  }

  // ————————————————— Group section —————————————————
  Widget _buildTimeSlotGroup(
    BuildContext context,
    String period,
    List<QueryDocumentSnapshot> slots,
    Map<String, bool> bookedMap,
  ) {
    final sw = MediaQuery.of(context).size.width;
    final titleSize = _scale(sw, 13, 14, 16);
    final groupPad = _scale(sw, 12, 16, 20);
    final chipGap = _scale(sw, 10, 12, 14);

    String emoji = '🌅';
    String timeRange = '';

    switch (period) {
      case 'Morning':
        emoji = '🌅';
        timeRange = '(6:00 AM - 12:00 PM)';
        break;
      case 'Afternoon':
        emoji = '☀️';
        timeRange = '(12:00 PM - 5:00 PM)';
        break;
      case 'Evening':
        emoji = '🌇';
        timeRange = '(5:00 PM - 10:00 PM)';
        break;
    }

    return Container(
      padding: EdgeInsets.all(groupPad),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji $period $timeRange',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsForWidth(constraints.maxWidth);
              final cardW = _cardWidth(constraints.maxWidth, columns, chipGap);
              return Wrap(
                spacing: chipGap,
                runSpacing: chipGap,
                alignment: (columns == 1)
                    ? WrapAlignment.center
                    : WrapAlignment.start, // center when single column
                children: slots.map((s) {
                  final data = s.data() as Map<String, dynamic>;
                  final slotId = (data['slot_id'] ?? s.id).toString();
                  final isBooked = bookedMap[slotId] ?? false;
                  return SizedBox(
                    width: cardW,
                    child: _buildSlotCard(context, s, cardW, isBooked),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ————————————————— Slot card (handles "Expired" + "Booked") —————————————————
  Widget _buildSlotCard(
    BuildContext context,
    QueryDocumentSnapshot slot,
    double cardWidth,
    bool isBooked,
  ) {
    final sw = MediaQuery.of(context).size.width;
    final ts = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.2);
    final data = slot.data() as Map<String, dynamic>;
    final slotId = data['slot_id']?.toString() ?? slot.id;
    final vehicleType = data['vehicle_type']?.toString() ?? 'Unknown';
    final instructorName =
        data['instructor_name']?.toString() ?? 'Unknown Instructor';

    final timeString = data['slot_time']?.toString() ?? '';

    // Get slot_cost from the database
    final slotCost = _asNum(data['slot_cost']);

    // Expiry logic relative to the selected date
    final isExpired = _isSlotExpiredForSelectedDate(timeString);

    // If booked or expired → disabled; else allow selection
    final disabled = isExpired || isBooked;
    final isSelected = !disabled && selectedSlotId == slotId;

    final padAll = _scale(sw, 10, 12, 14);
    final badgePadH = _scale(sw, 6, 8, 10);
    final badgePadV = _scale(sw, 2, 3, 4);

    final timeSize = _scale(sw, 12, 13, 14) * ts;
    final vehSize = _scale(sw, 9, 10, 11) * ts;

    final instSize = _scale(sw, 9, 10, 11) * ts;
    final availSize = _scale(sw, 9, 10, 11) * ts;
    final costSize = _scale(sw, 14, 16, 18) * ts;

    final borderColor = disabled
        ? const Color(0xFFD1D5DB)
        : (isSelected ? const Color(0xFF10B981) : const Color(0xFFE5E7EB));

    final bgColor =
        disabled ? const Color(0xFFF9FAFB) : (isSelected ? const Color(0xFF10B981) : Colors.white);

    final shadow = disabled
        ? null
        : (isSelected
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null);

    return AbsorbPointer(
      absorbing: disabled, // disables taps if expired/booked
      child: Opacity(
        opacity: disabled ? 0.55 : 1.0,
        child: GestureDetector(
          onTap: () {
            if (disabled) return;
            setState(() {
              selectedSlotId = isSelected ? null : slotId;
            });
          },
          child: Container(
            width: cardWidth,
            padding: EdgeInsets.all(padAll),
            decoration: BoxDecoration(
              color: bgColor,
              border: Border.all(color: borderColor, width: 2),
              borderRadius: BorderRadius.circular(8),
              boxShadow: shadow,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTimeRange(timeString),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: timeSize,
                    fontWeight: FontWeight.w600,
                    color: disabled
                        ? const Color(0xFF6B7280)
                        : (isSelected ? Colors.white : Colors.black),
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: badgePadH, vertical: badgePadV),
                  decoration: BoxDecoration(
                    color: disabled
                        ? const Color(0xFFF3F4F6)
                        : (isSelected
                            ? Colors.white.withOpacity(0.2)
                            : const Color(0xFFEFF6FF)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    vehicleType,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: vehSize,
                      fontWeight: FontWeight.w500,
                      color: disabled
                          ? const Color(0xFF6B7280)
                          : (isSelected
                              ? Colors.white
                              : const Color(0xFF1D4ED8)),
                    ),
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Text(
                  instructorName.length > 22
                      ? '${instructorName.substring(0, 22)}…'
                      : instructorName,
                  style: TextStyle(
                    fontSize: instSize,
                    color: disabled
                        ? const Color(0xFF9CA3AF)
                        : (isSelected
                            ? Colors.white.withOpacity(0.9)
                            : const Color(0xFF6B7280)),
                  ),
                  textAlign: TextAlign.center,
                ),

                // Cost display
                SizedBox(height: _scale(sw, 8, 10, 12)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: disabled
                        ? const Color(0xFFF3F4F6)
                        : (isSelected
                            ? Colors.white.withOpacity(0.15)
                            : const Color(0xFFF0FDF4)),
                    border: Border.all(
                      color: disabled
                          ? const Color(0xFFE5E7EB)
                          : (isSelected
                              ? Colors.white.withOpacity(0.3)
                              : const Color(0xFF10B981).withOpacity(0.2)),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.currency_rupee,
                        size: costSize - 2,
                        color: disabled
                            ? const Color(0xFF6B7280)
                            : (isSelected
                                ? Colors.white
                                : const Color(0xFF10B981)),
                      ),
                      Text(
                        _formatCostNumber(slotCost),
                        style: TextStyle(
                          fontSize: costSize,
                          fontWeight: FontWeight.w700,
                          color: disabled
                              ? const Color(0xFF6B7280)
                              : (isSelected
                                  ? Colors.white
                                  : const Color(0xFF10B981)),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: _scale(sw, 4, 6, 8)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: disabled
                            ? const Color(0xFF9CA3AF)
                            : (isSelected
                                ? Colors.white
                                : const Color(0xFF10B981)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isBooked ? 'Booked' : (isExpired ? 'Expired' : 'Available'),
                      style: TextStyle(
                        fontSize: availSize,
                        color: disabled
                            ? const Color(0xFF6B7280)
                            : (isSelected
                                ? Colors.white.withOpacity(0.95)
                                : const Color(0xFF10B981)),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ————————————————— Booking Bar —————————————————
  Widget _buildBookingBar(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final ts = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.2);

    return Container(
      padding: EdgeInsets.all(_scale(sw, 16, 20, 24)),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Selected Slot',
                    style: TextStyle(
                      fontSize: _scale(sw, 12, 13, 14) * ts,
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Slot #$selectedSlotId',
                    style: TextStyle(
                      fontSize: _scale(sw, 14, 16, 18) * ts,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: _isBooking ? null : _proceedToBooking,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: _scale(sw, 24, 28, 32),
                  vertical: _scale(sw, 12, 14, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isBooking) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    Icon(Icons.map_outlined, size: _scale(sw, 16, 18, 20)),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _isBooking ? 'Loading...' : 'Book Slot',
                    style: TextStyle(
                      fontSize: _scale(sw, 14, 16, 18) * ts,
                      fontWeight: FontWeight.w600,
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

  // ————————————————— Navigate to Booking Page —————————————————
  Future<void> _proceedToBooking() async {
    if (selectedSlotId == null || _isBooking) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to book a slot')),
        );
      }
      return;
    }

    setState(() {
      _isBooking = true;
    });

    try {
      // Check if slot is still available before proceeding
      final existingBooking = await FirebaseFirestore.instance
          .collection('bookings')
          .where('slot_id', isEqualTo: selectedSlotId)
          .where('status', whereIn: ['confirmed', 'booked'])
          .get();

      if (existingBooking.docs.isNotEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('This slot has already been booked by someone else'),
              backgroundColor: Color(0xFFDC2626),
            ),
          );
        }
        setState(() {
          selectedSlotId = null;
          _isBooking = false;
        });
        return;
      }

      // Navigate to BookingPage
      if (context.mounted) {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => BookingPage(
              userId: user.uid,
              slotId: selectedSlotId!,
            ),
          ),
        );

        // If booking was successful, clear the selection
        if (result == true) {
          setState(() {
            selectedSlotId = null;
          });
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBooking = false;
        });
      }
    }
  }

  // ————————————————— Helpers —————————————————
  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Breakpoints → columns (1–5). Single column centers via WrapAlignment.center
  int _columnsForWidth(double width) {
    if (width < 420) return 1;
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  /// Compute card width from available width, columns, and spacing
  double _cardWidth(double maxWidth, int columns, double gap) {
    final totalGaps = gap * (columns - 1);
    final usable = (maxWidth - totalGaps).clamp(200.0, maxWidth);
    final base = usable / columns;
    return base.clamp(200.0, 360.0);
  }

  /// Simple scaler that grows values with width
  static double _scale(double width, double small, double medium, double large) {
    if (width >= 1200) return large;
    if (width >= 800) return medium;
    return small;
  }

  /// Parse start time from "09:00 AM - 10:00 AM". Falls back to epoch if invalid.
  DateTime _parseStartTime(String slotTime) {
    try {
      final start = slotTime.split(' - ').first.trim();
      final t = DateFormat('hh:mm a').parseStrict(start);
      final d = selectedDate; // use selected date for grouping consistency
      return DateTime(d.year, d.month, d.day, t.hour, t.minute);
    } catch (_) {
      return DateTime(1970);
    }
  }

  /// Parse end time from "09:00 AM - 10:00 AM". Falls back to epoch if invalid.
  DateTime _parseEndTime(String slotTime) {
    try {
      final parts = slotTime.split(' - ');
      if (parts.length != 2) return DateTime(1970);
      final end = parts[1].trim();
      final t = DateFormat('hh:mm a').parseStrict(end);
      final d = selectedDate;
      return DateTime(d.year, d.month, d.day, t.hour, t.minute);
    } catch (_) {
      return DateTime(1970);
    }
  }

  String _formatTimeRange(String slotTime) {
    try {
      final parts = slotTime.split(' - ');
      if (parts.length != 2) return slotTime;
      final s = DateFormat('hh:mm a').parseStrict(parts[0].trim());
      final e = DateFormat('hh:mm a').parseStrict(parts[1].trim());
      return '${DateFormat('h:mm a').format(s)} - ${DateFormat('h:mm a').format(e)}';
    } catch (_) {
      return slotTime;
    }
  }

  num? _asNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    return num.tryParse(v.toString());
  }

  String _formatCostNumber(num? v) {
    if (v == null) return '0';
    return v.toInt().toString();
  }

  /// Determine if a slot is expired relative to the currently selectedDate.
  /// Rules:
  /// - selectedDate < today => expired
  /// - selectedDate > today => not expired
  /// - selectedDate == today => expired if endTime <= now
  bool _isSlotExpiredForSelectedDate(String slotTime) {
    final today = _atMidnight(DateTime.now());
    final sel = _atMidnight(selectedDate);

    if (sel.isBefore(today)) return true;
    if (sel.isAfter(today)) return false;

    // same day: compare end time to now
    final now = DateTime.now();
    final end = _parseEndTime(slotTime);
    if (end.year == 1970) return false; // on parse failure, do not mark expired
    return end.isBefore(now) || end.isAtSameMomentAs(now);
  }
}

/// Small, responsive action button component for app bar
class _MyBookingsActionButton extends StatelessWidget {
  final double sw;
  final double ts;
  const _MyBookingsActionButton({required this.sw, required this.ts});

  @override
  Widget build(BuildContext context) {
    final compact = sw < 380;
    final iconSize = _UserSlotBookingState._scale(sw, 16, 18, 20);
    final fontSize = _UserSlotBookingState._scale(sw, 12, 13, 14) * ts;

    return TextButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const MyBookingsPage(), // ← ensure this exists
          ),
        );
      },
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: _UserSlotBookingState._scale(sw, 8, 10, 12),
          vertical: _UserSlotBookingState._scale(sw, 6, 8, 10),
        ),
      ),
      icon: Icon(Icons.calendar_month, size: iconSize, color: Colors.white),
      label: compact
          ? const SizedBox.shrink()
          : Text('My Bookings', style: TextStyle(fontSize: fontSize, color: Colors.white)),
    );
  }
}
