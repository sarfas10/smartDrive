// lib/instructor_slots_block.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InstructorSlotsBlock extends StatefulWidget {
  const InstructorSlotsBlock({super.key});

  @override
  State<InstructorSlotsBlock> createState() => _InstructorSlotsBlockState();
}

class _InstructorSlotsBlockState extends State<InstructorSlotsBlock> {
  DateTime selectedDate = _atMidnight(DateTime.now());
  String? selectedSlotId;

  String? _uid;
  bool _identityLoaded = false;

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
    } catch (_) {
      setState(() {
        _uid = null;
        _identityLoaded = true;
      });
    }
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
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                boxShadow: [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
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
              '👨‍🏫 My Scheduled Slots',
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
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Date selector (same look as SlotsBlock) ─────────────────────────
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
                  selectedSlotId = null;
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

  // ───────────────────────── Stream + UI (ONLY current instructor’s slots) ─────────────────────────
  Widget _buildSlotsContent(BuildContext context) {
    if (!_identityLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_uid == null) {
      return _buildEmptyState(context, 'Please sign in to view your scheduled slots.');
    }

    final ts = Timestamp.fromDate(selectedDate);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('slots')
          .where('slot_day', isEqualTo: ts)
          .where('instructor_user_id', isEqualTo: _uid) // ← key filter
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildEmptyState(context, 'Error: ${snapshot.error}');
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = List<QueryDocumentSnapshot>.from(snapshot.data?.docs ?? const []);
        if (docs.isEmpty) {
          return _buildEmptyState(
            context,
            'No slots scheduled for you on ${DateFormat('EEEE, MMM d').format(selectedDate)}',
          );
        }

        // Sort by parsed start time
        docs.sort((a, b) {
          final sa = _parseStartTime((a.data() as Map<String, dynamic>)['slot_time']?.toString() ?? '');
          final sb = _parseStartTime((b.data() as Map<String, dynamic>)['slot_time']?.toString() ?? '');
          return sa.compareTo(sb);
        });

        // Group by period
        final grouped = _groupSlotsByTimePeriod(docs);

        final sw = MediaQuery.of(context).size.width;
        final outerMargin = _scale(sw, 12, 20, 28);
        final headerPad = _scale(sw, 10, 12, 14);

        return Container(
          margin: EdgeInsets.all(outerMargin),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(headerPad),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    Text('🎯', style: TextStyle(fontSize: _scale(sw, 14, 16, 18))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Your slots for ${DateFormat('EEEE, d MMM').format(selectedDate)}',
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

  Widget _buildEmptyState(BuildContext context, String msg) {
    final sw = MediaQuery.of(context).size.width;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _scale(sw, 16, 20, 28)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('📅', style: TextStyle(fontSize: _scale(sw, 56, 64, 72), color: Colors.grey)),
            const SizedBox(height: 16),
            Text(msg, style: TextStyle(fontSize: _scale(sw, 16, 18, 20), color: Colors.grey), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── Grouping ─────────────────────────
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

  // ───────────────────────── Period section ─────────────────────────
  Widget _buildTimeSlotGroup(
    BuildContext context,
    String period,
    List<QueryDocumentSnapshot> slots,
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
      default:
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

  // ───────────────────────── Slot card (Edit + Delete like SlotsBlock) ─────────────────────────
  Widget _buildSlotCard(BuildContext context, QueryDocumentSnapshot slot, double cardWidth) {
    final sw = MediaQuery.of(context).size.width;
    final ts = MediaQuery.of(context).textScaleFactor.clamp(0.9, 1.2);
    final data = slot.data() as Map<String, dynamic>;

    final slotId = data['slot_id']?.toString() ?? slot.id;
    final vehicleType = data['vehicle_type']?.toString() ?? 'Unknown';
    final instructorName = data['instructor_name']?.toString() ??
        (data['instructor_user_id']?.toString() ?? 'Unknown');
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
    final instSize = _scale(sw, 9, 10, 11) * ts;
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
                  instructorName.length > 22 ? '${instructorName.substring(0, 22)}…' : instructorName,
                  style: TextStyle(
                    fontSize: instSize,
                    color: isSelected ? Colors.white.withOpacity(0.9) : const Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),

                // Costs display with EDIT like SlotsBlock
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
                      // Vehicle Cost
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
                      // Additional Cost + EDIT
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
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Delete button (same as SlotsBlock)
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

  // ───────────────────────── Edit Additional Cost (same flow as SlotsBlock) ─────────────────────────
  Future<void> _editAdditionalCost(String docId, num? current) async {
    final ctrl = TextEditingController(text: current?.toString() ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Edit Additional Cost'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Align(alignment: Alignment.centerLeft, child: Text('Enter amount (INR):')),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final newVal = num.tryParse(ctrl.text.trim());
    if (newVal == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid amount')));
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('slots').doc(docId).update({
        'additional_cost': newVal,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Additional cost updated')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ───────────────────────── Delete (same confirmation as SlotsBlock) ─────────────────────────
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
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

  // ───────────────────────── Helpers ─────────────────────────
  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  int _columnsForWidth(double width) {
    if (width < 360) return 1;
    if (width >= 1200) return 5;
    if (width >= 900) return 4;
    if (width >= 600) return 3;
    return 2;
  }

  double _cardWidth(double maxWidth, int columns, double gap) {
    final totalGaps = gap * (columns - 1);
    final usable = (maxWidth - totalGaps).clamp(200.0, maxWidth);
    final base = usable / columns;
    return base.clamp(160.0, 320.0);
  }

  static double _scale(double width, double small, double medium, double large) {
    if (width >= 1200) return large;
    if (width >= 800) return medium;
    return small;
  }

  /// Parse start time from "09:00 AM - 10:00 AM".
  DateTime _parseStartTime(String slotTime) {
    try {
      final start = slotTime.split(' - ').first.trim();
      final t = DateFormat('hh:mm a').parseStrict(start);
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

  String _formatCurrency(num? v) {
    final f = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    if (v == null) return '—';
    return f.format(v);
  }
}
