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
              '👨‍🏫 My Scheduled Slots',
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
            Expanded(
              child: Container(
                color: context.c.background,
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
                  color: isSelected ? AppColors.danger : context.c.surface,
                  border: Border.all(
                    color: isSelected ? AppColors.danger : AppColors.divider,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.m),
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

  // ───────────────────────── Stream + UI (ONLY current instructor’s slots) ─────────────────────────
  Widget _buildSlotsContent(BuildContext context) {
    if (!_identityLoaded) {
      return Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)),
      );
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
          return Center(
            child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(context.c.primary)),
          );
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
            color: context.c.surface,
            borderRadius: BorderRadius.circular(AppRadii.m),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(headerPad),
                decoration: BoxDecoration(
                  color: context.c.background,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    Text('🎯', style: TextStyle(fontSize: _scale(sw, 14, 16, 18))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Your slots for ${DateFormat('EEEE, d MMM').format(selectedDate)}',
                        style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceMuted, fontSize: _scale(sw, 12, 13, 14)),
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
            Text('📅', style: TextStyle(fontSize: _scale(sw, 56, 64, 72), color: AppColors.onSurfaceFaint)),
            const SizedBox(height: 16),
            Text(msg, style: context.t.bodyMedium?.copyWith(fontSize: _scale(sw, 16, 18, 20), color: AppColors.onSurfaceMuted), textAlign: TextAlign.center),
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
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.neuBg)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji $period $timeRange',
            style: TextStyle(
              fontSize: titleSize,
              fontWeight: FontWeight.w600,
              color: context.c.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsForWidth(constraints.maxWidth);
              final cardW = _cardWidth(constraints.maxWidth, columns, chipGap);

              final slotCards = slots.map((s) => _buildSlotCard(context, s, cardW)).toList();

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
          color: isSelected ? AppColors.success : context.c.surface,
          border: Border.all(
            color: isSelected ? AppColors.success : AppColors.divider,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppRadii.m),
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
                    color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface,
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: badgePadH, vertical: badgePadV),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.12) : AppColors.neuBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    vehicleType,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: vehSize,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? AppColors.onSurfaceInverse : context.c.primary,
                    ),
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Text(
                  instructorName.length > 22 ? '${instructorName.substring(0, 22)}…' : instructorName,
                  style: TextStyle(
                    fontSize: instSize,
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.9) : AppColors.onSurfaceMuted,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Costs display with EDIT like SlotsBlock
                SizedBox(height: _scale(sw, 8, 10, 12)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.12) : context.c.background,
                    border: Border.all(
                      color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.25) : AppColors.divider,
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
                              color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.95) : context.c.onSurface,
                            ),
                          ),
                          Text(
                            _formatCurrency(vehicleCost),
                            style: TextStyle(
                              fontSize: moneySize,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface,
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
                              color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.95) : context.c.onSurface,
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
                                  color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface,
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _editAdditionalCost(slot.id, additionalCost),
                                child: Icon(
                                  Icons.edit,
                                  size: 16,
                                  color: isSelected ? AppColors.onSurfaceInverse : AppColors.slate,
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
                    color: AppColors.errBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete, size: deleteIcon, color: AppColors.danger),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
        title: Text('Edit Additional Cost', style: context.t.titleMedium?.copyWith(color: context.c.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text('Enter amount (INR):', style: context.t.bodyMedium?.copyWith(color: context.c.onSurface))),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
                hintText: 'e.g. 250',
                filled: true,
                fillColor: context.c.surface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: context.c.primary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: context.c.primary, foregroundColor: context.c.onPrimary),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final newVal = num.tryParse(ctrl.text.trim());
    if (newVal == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invalid amount', style: context.t.bodyMedium?.copyWith(color: AppColors.danger))));
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('slots').doc(docId).update({
        'additional_cost': newVal,
        'updated_at': FieldValue.serverTimestamp(),
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Additional cost updated', style: context.t.bodyMedium?.copyWith(color: context.c.onSurface))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: context.t.bodyMedium?.copyWith(color: AppColors.danger))));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
        title: Text('Delete Slot', style: context.t.titleMedium?.copyWith(color: context.c.onSurface)),
        content: Text('Are you sure you want to delete slot $slotId?', style: context.t.bodyMedium?.copyWith(color: context.c.onSurface)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: context.c.primary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: context.c.onPrimary),
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
            SnackBar(content: Text('Slot $slotId deleted successfully', style: context.t.bodyMedium?.copyWith(color: context.c.onSurface))),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting slot: $e', style: context.t.bodyMedium?.copyWith(color: AppColors.danger))),
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
