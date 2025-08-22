// user_slot_booking.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserSlotBooking extends StatefulWidget {
  const UserSlotBooking({super.key});

  @override
  State<UserSlotBooking> createState() => _UserSlotBookingState();
}

class _UserSlotBookingState extends State<UserSlotBooking> {
  DateTime selectedDate = _atMidnight(DateTime.now());
  String? selectedSlotId;
  bool _isBooking = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final sw = media.size.width;
    final sh = media.size.height;
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
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
                  selectedSlotId = null; // reset selection
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
                  color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF8F9FA),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('EEE').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: dowSize,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.black.withOpacity(0.7),
                      ),
                    ),
                    SizedBox(height: _scale(sw, 1, 1, 2)),
                    Text(
                      DateFormat('d').format(date),
                      style: TextStyle(
                        fontSize: daySize,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(height: _scale(sw, 1, 1, 2)),
                    Text(
                      DateFormat('MMM').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: monSize,
                        color: isSelected ? Colors.white : Colors.black.withOpacity(0.7),
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

        final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? const []);
        
        return FutureBuilder<List<QueryDocumentSnapshot>>(
          future: _filterAvailableSlots(docs),
          builder: (context, availableSnapshot) {
            if (availableSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final availableDocs = availableSnapshot.data ?? [];
            if (availableDocs.isEmpty) {
              return _buildEmptyState(context);
            }

            // Sort by parsed start time
            availableDocs.sort((a, b) {
              final sa = _parseStartTime((a.data() as Map)['slot_time']?.toString() ?? '');
              final sb = _parseStartTime((b.data() as Map)['slot_time']?.toString() ?? '');
              return sa.compareTo(sb);
            });

            // Group by period
            final grouped = _groupSlotsByTimePeriod(availableDocs);

            final media = MediaQuery.of(context);
            final sw = media.size.width;
            final outerMargin = _scale(sw, 12, 20, 28);
            final headerPad = _scale(sw, 10, 12, 14);

            return Container(
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
                      border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                    ),
                    child: Row(
                      children: [
                        Text('🎯', style: TextStyle(fontSize: _scale(sw, 14, 16, 18))),
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
                          .map((e) => _buildTimeSlotGroup(context, e.key, e.value))
                          .toList(),
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

  // Helper function to filter available slots
  Future<List<QueryDocumentSnapshot>> _filterAvailableSlots(List<QueryDocumentSnapshot> docs) async {
    final availableDocs = <QueryDocumentSnapshot>[];
    
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final slotId = data['slot_id']?.toString() ?? doc.id;
      
      // Check if this slot is already booked
      final bookingQuery = await FirebaseFirestore.instance
          .collection('bookings')
          .where('slot_id', isEqualTo: slotId)
          .where('status', whereIn: ['confirmed', 'booked'])
          .limit(1)
          .get();
      
      if (bookingQuery.docs.isEmpty) {
        availableDocs.add(doc);
      }
    }
    
    return availableDocs;
  }

  Widget _buildEmptyState(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _scale(sw, 16, 20, 28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📅', style: TextStyle(fontSize: _scale(sw, 56, 64, 72), color: Colors.grey)),
            const SizedBox(height: 16),
            Text(
              'No slots available for ${DateFormat('EEEE, MMM d').format(selectedDate)}',
              style: TextStyle(fontSize: _scale(sw, 16, 18, 20), color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text('Try selecting a different date', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  // ————————————————— Grouping —————————————————
  Map<String, List<QueryDocumentSnapshot>> _groupSlotsByTimePeriod(List<QueryDocumentSnapshot> slots) {
    final Map<String, List<QueryDocumentSnapshot>> grouped = {
      'Morning': [],
      'Afternoon': [],
      'Evening': [],
    };

    for (final slot in slots) {
      final data = slot.data() as Map<String, dynamic>;
      final start = _parseStartTime(data['slot_time']?.toString() ?? '');
      final h = start.hour; // 0–23

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
  Widget _buildTimeSlotGroup(BuildContext context, String period, List<QueryDocumentSnapshot> slots) {
    final sw = MediaQuery.of(context).size.width;
    final emojiSize = _scale(sw, 14, 16, 18);
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
                children: slots.map((s) => _buildSlotCard(context, s, cardW)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  // ————————————————— Slot card —————————————————
  Widget _buildSlotCard(BuildContext context, QueryDocumentSnapshot slot, double cardWidth) {
    final sw = MediaQuery.of(context).size.width;
    final ts = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.2);
    final data = slot.data() as Map<String, dynamic>;
    final slotId = data['slot_id']?.toString() ?? slot.id;
    final vehicleType = data['vehicle_type']?.toString() ?? 'Unknown';
    final instructorName = data['instructor_name']?.toString() ?? 'Unknown Instructor';
    final seats = (data['seat'] is num)
        ? (data['seat'] as num).toInt()
        : int.tryParse('${data['seat']}') ?? 0;
    final timeString = data['slot_time']?.toString() ?? '';

    // Get slot_cost from the database
    final slotCost = _asNum(data['slot_cost']);

    final isSelected = selectedSlotId == slotId;

    final padAll = _scale(sw, 10, 12, 14);
    final badgePadH = _scale(sw, 6, 8, 10);
    final badgePadV = _scale(sw, 2, 3, 4);

    final timeSize = _scale(sw, 12, 13, 14) * ts;
    final vehSize = _scale(sw, 9, 10, 11) * ts;
    final seatsSize = _scale(sw, 10, 11, 12) * ts;
    final instSize = _scale(sw, 9, 10, 11) * ts;
    final availSize = _scale(sw, 9, 10, 11) * ts;
    final costSize = _scale(sw, 14, 16, 18) * ts;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedSlotId = isSelected ? null : slotId;
        });
      },
      child: Container(
        width: cardWidth,
        padding: EdgeInsets.all(padAll),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : Colors.white,
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : const Color(0xFFE5E7EB),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
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
                color: isSelected ? Colors.white : Colors.black,
              ),
            ),
            SizedBox(height: _scale(sw, 4, 6, 8)),
            Container(
              padding: EdgeInsets.symmetric(horizontal: badgePadH, vertical: badgePadV),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                vehicleType,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: vehSize,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? Colors.white : const Color(0xFF1D4ED8),
                ),
              ),
            ),
            SizedBox(height: _scale(sw, 4, 6, 8)),
            Text(
              '$seats seats',
              style: TextStyle(
                fontSize: seatsSize,
                color: isSelected ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.8),
              ),
            ),
            SizedBox(height: _scale(sw, 4, 6, 8)),
            Text(
              instructorName.length > 22 ? '${instructorName.substring(0, 22)}…' : instructorName,
              style: TextStyle(
                fontSize: instSize,
                color: isSelected ? Colors.white.withOpacity(0.9) : const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),

            // Cost display
            SizedBox(height: _scale(sw, 8, 10, 12)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.15) : const Color(0xFFF0FDF4),
                border: Border.all(
                  color: isSelected ? Colors.white.withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.2),
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.currency_rupee,
                    size: costSize - 2,
                    color: isSelected ? Colors.white : const Color(0xFF10B981),
                  ),
                  Text(
                    _formatCostNumber(slotCost),
                    style: TextStyle(
                      fontSize: costSize,
                      fontWeight: FontWeight.w700,
                      color: isSelected ? Colors.white : const Color(0xFF10B981),
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
                    color: isSelected ? Colors.white : const Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Available',
                  style: TextStyle(
                    fontSize: availSize,
                    color: isSelected ? Colors.white.withOpacity(0.95) : const Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
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
              onPressed: _isBooking ? null : _bookSlot,
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
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    Icon(Icons.check_circle, size: _scale(sw, 16, 18, 20)),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _isBooking ? 'Booking...' : 'Book Slot',
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

  // ————————————————— Book Slot Function —————————————————
  Future<void> _bookSlot() async {
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
      // Check if slot is still available before booking
      final existingBooking = await FirebaseFirestore.instance
          .collection('bookings')
          .where('slot_id', isEqualTo: selectedSlotId)
          .where('status', whereIn: ['confirmed', 'booked'])
          .get();

      if (existingBooking.docs.isNotEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This slot has already been booked by someone else'),
              backgroundColor: Color(0xFFDC2626),
            ),
          );
        }
        return;
      }

      // Create booking record
      final bookingRef = FirebaseFirestore.instance.collection('bookings').doc();
      await bookingRef.set({
        'booking_id': bookingRef.id,
        'slot_id': selectedSlotId,
        'user_id': user.uid,
        'booking_date': FieldValue.serverTimestamp(),
        'slot_date': Timestamp.fromDate(selectedDate),
        'status': 'confirmed',
        'created_at': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        setState(() {
          selectedSlotId = null;
          _isBooking = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Slot booked successfully!'),
            backgroundColor: const Color(0xFF10B981),
            action: SnackBarAction(
              label: 'View Bookings',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to bookings page
                // Navigator.pushNamed(context, '/my-bookings');
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        setState(() {
          _isBooking = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error booking slot: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  // ————————————————— Helpers —————————————————
  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Breakpoints → columns (2–5)
  int _columnsForWidth(double width) {
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  /// Compute card width from available width, columns, and spacing
  double _cardWidth(double maxWidth, int columns, double gap) {
    final totalGaps = gap * (columns - 1);
    final usable = (maxWidth - totalGaps).clamp(200.0, maxWidth);
    final base = usable / columns;
    return base.clamp(160.0, 320.0);
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
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, t.hour, t.minute);
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
}