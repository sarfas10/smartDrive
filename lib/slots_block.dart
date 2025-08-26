// slots_block.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_slots.dart';

class SlotsBlock extends StatefulWidget {
  const SlotsBlock({super.key});

  @override
  State<SlotsBlock> createState() => _SlotsBlockState();
}

class _SlotsBlockState extends State<SlotsBlock> {
  DateTime selectedDate = _atMidnight(DateTime.now());
  String? selectedSlotId;

  bool isAdmin = false;
  bool _roleLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          isAdmin = false;
          _roleLoaded = true;
        });
        return;
      }

      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = snap.data();
      final role = (data?['role'] ?? '').toString().toLowerCase().trim();

      setState(() {
        isAdmin = (role == 'admin');
        _roleLoaded = true;
      });

      // Run purge once when an admin opens this screen
      if (isAdmin) {
        Future.microtask(_purgeExpiredSlots);
      }
    } catch (_) {
      setState(() {
        isAdmin = false;
        _roleLoaded = true;
      });
    }
  }

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
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
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
              '🚗 Driving School Slots',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: _scale(sw, 16, 18, 20) * ts,
              ),
            ),
            actions: [
              Padding(
                padding: EdgeInsets.only(right: _scale(sw, 8, 10, 12)),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddSlotsPage()),
                    );
                  },
                  icon: Icon(Icons.add, size: _scale(sw, 14, 16, 18)),
                  label: Text(
                    'Create Slot',
                    style: TextStyle(fontSize: _scale(sw, 12, 13, 14) * ts),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                    padding: EdgeInsets.symmetric(
                      horizontal: _scale(sw, 10, 12, 14),
                      vertical: _scale(sw, 6, 8, 10),
                    ),
                    elevation: 0,
                  ),
                ),
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
                  color: isSelected ? const Color(0xFFEF4444) : const Color(0xFFF8F9FA),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFEF4444) : const Color(0xFFE5E7EB),
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
    if (!_roleLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

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
        if (docs.isEmpty) {
          return _buildEmptyState(context);
        }

        // Sort by parsed start time
        docs.sort((a, b) {
          final sa = _parseStartTime((a.data() as Map<String, dynamic>)['slot_time']?.toString() ?? '');
          final sb = _parseStartTime((b.data() as Map<String, dynamic>)['slot_time']?.toString() ?? '');
          return sa.compareTo(sb);
        });

        // Group by period
        final grouped = _groupSlotsByTimePeriod(docs);

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
Widget _buildTimeSlotGroup(
  BuildContext context,
  String period,
  List<QueryDocumentSnapshot> slots,
) {
  final sw = MediaQuery.of(context).size.width;
  // final emojiSize = _scale(sw, 14, 16, 18); // (unused; remove if you don't need it)
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
    default:
      // optional: handle unexpected keys
      emoji = '🕒';
      timeRange = '';
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

            final slotCards = slots
                .map((s) => _buildSlotCard(context, s, cardW))
                .toList();

            if (columns == 1) {
              return Wrap(
                spacing: 0,
                runSpacing: chipGap,
                alignment: WrapAlignment.center,
                children: slotCards,
              );
            }

            return Wrap(
              spacing: chipGap,
              runSpacing: chipGap,
              alignment: WrapAlignment.start,
              children: slotCards,
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
    final instructorName = data['instructor_name']?.toString() ??
        (data['instructor_user_id']?.toString() ?? 'Unknown');
    final seats = (data['seat'] is num)
        ? (data['seat'] as num).toInt()
        : int.tryParse('${data['seat']}') ?? 0;
    final timeString = data['slot_time']?.toString() ?? '';

    // Costs
    final vehicleCost = _asNum(data['vehicle_cost']);
    final additionalCost = _asNum(data['additional_cost']);

    final isSelected = selectedSlotId == slotId;

    final padAll = _scale(sw, 10, 12, 14);
    final badgePadH = _scale(sw, 6, 8, 10);
    final badgePadV = _scale(sw, 2, 3, 4);
    final deleteBtn = _scale(sw, 18, 20, 22);
    final deleteIcon = _scale(sw, 10, 12, 14);

    final timeSize = _scale(sw, 12, 13, 14) * ts;
    final vehSize = _scale(sw, 9, 10, 11) * ts;
    final seatsSize = _scale(sw, 10, 11, 12) * ts;
    final instSize = _scale(sw, 9, 10, 11) * ts;
    final availSize = _scale(sw, 9, 10, 11) * ts;
    final moneySize = _scale(sw, 11, 12, 13) * ts;

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
        ),
        child: Stack(
          children: [
            Column(
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

                // Costs display
                SizedBox(height: _scale(sw, 8, 10, 12)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.12) : const Color(0xFFFAFAFA),
                    border: Border.all(
                      color: isSelected ? Colors.white.withOpacity(0.25) : const Color(0xFFE5E7EB),
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Vehicle Cost',
                            style: TextStyle(
                              fontSize: moneySize,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? Colors.white.withOpacity(0.95) : const Color(0xFF374151),
                            ),
                          ),
                          Text(
                            _formatCurrency(vehicleCost),
                            style: TextStyle(
                              fontSize: moneySize,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white : const Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Additional Cost',
                            style: TextStyle(
                              fontSize: moneySize,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? Colors.white.withOpacity(0.95) : const Color(0xFF374151),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatCurrency(additionalCost),
                                style: TextStyle(
                                  fontSize: moneySize,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : const Color(0xFF111827),
                                ),
                              ),
                              if (isAdmin) ...[
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _editAdditionalCost(slot.id, additionalCost),
                                  child: Icon(
                                    Icons.edit,
                                    size: 16,
                                    color: isSelected ? Colors.white : const Color(0xFF1F2937),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: _scale(sw, 2, 4, 6)),
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

            // Delete button
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () => _deleteSlot(slot),
                child: Container(
                  width: deleteBtn,
                  height: deleteBtn,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: deleteIcon, color: const Color(0xFFDC2626)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ————————————————— Edit Additional Cost —————————————————
  Future<void> _editAdditionalCost(String docId, num? current) async {
    if (!isAdmin) return;
    final ctrl = TextEditingController(text: current?.toString() ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Edit Additional Cost'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Enter amount (INR):'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'e.g. 250',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final newVal = num.tryParse(ctrl.text.trim());
    if (newVal == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid amount')),
        );
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('slots').doc(docId).update({
        'additional_cost': newVal,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Additional cost updated')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  // ————————————————— Delete —————————————————
  Future<void> _deleteSlot(QueryDocumentSnapshot slot) async {
    final data = slot.data() as Map<String, dynamic>;
    final slotId = data['slot_id']?.toString() ?? slot.id;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Slot'),
        content: Text('Are you sure you want to delete slot $slotId?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await slot.reference.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Slot $slotId deleted successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting slot: $e')),
          );
        }
      }
    }
  }

  // ————————————————— Purge expired slots (admin entry) —————————————————
  Future<void> _purgeExpiredSlots() async {
    try {
      final now = DateTime.now(); // local device time
      final todayLocalMidnight = DateTime(now.year, now.month, now.day);
      final todayTs = Timestamp.fromDate(todayLocalMidnight);

      final slotsCol = FirebaseFirestore.instance.collection('slots');

      // 1) Delete all past-day slots
      final pastSnap = await slotsCol.where('slot_day', isLessThan: todayTs).get();

      Future<void> _deleteInBatches(List<QueryDocumentSnapshot> docs) async {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        int op = 0;
        for (final d in docs) {
          batch.delete(d.reference);
          op++;
          if (op >= 400) {
            await batch.commit();
            batch = FirebaseFirestore.instance.batch();
            op = 0;
          }
        }
        if (op > 0) {
          await batch.commit();
        }
      }

      await _deleteInBatches(pastSnap.docs);

      // 2) For today, delete slots whose start time is within last 5 minutes (or earlier)
      final todaySnap = await slotsCol.where('slot_day', isEqualTo: todayTs).get();
      final List<QueryDocumentSnapshot> toDeleteToday = [];

      for (final doc in todaySnap.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;

        final slotTimeStr = data['slot_time']?.toString() ?? '';
        if (slotTimeStr.isEmpty) continue;

        final startLocal = _parseStartTimeForDay(slotTimeStr, todayLocalMidnight);

        // delete if now >= (start - 5 minutes)
        if (now.isAfter(startLocal.subtract(const Duration(minutes: 5))) ||
            now.isAtSameMomentAs(startLocal.subtract(const Duration(minutes: 5)))) {
          toDeleteToday.add(doc);
        }
      }

      await _deleteInBatches(toDeleteToday);

      if (context.mounted && isAdmin) {
       debugPrint('Expired slots purged');
      }
    } catch (e) {
      if (context.mounted && isAdmin) {
       debugPrint('Purge error: $e');
      }
    }
  }

  /// Parse start "hh:mm a" from "10:00 AM - 11:00 AM" and bind it to the given day (local).
  DateTime _parseStartTimeForDay(String slotTime, DateTime dayLocalMidnight) {
    try {
      final start = slotTime.split(' - ').first.trim(); // "10:00 AM"
      final t = DateFormat('hh:mm a').parseStrict(start); // time-only
      return DateTime(
        dayLocalMidnight.year,
        dayLocalMidnight.month,
        dayLocalMidnight.day,
        t.hour,
        t.minute,
      );
    } catch (_) {
      return DateTime(1970); // clearly expired
    }
  }

  // ————————————————— Helpers —————————————————
  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Breakpoints → columns (1–5)
  int _columnsForWidth(double width) {
    if (width < 360) return 1;
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

  String _formatCurrency(num? v) {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    if (v == null) return '—';
    return f.format(v);
  }
}
