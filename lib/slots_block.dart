// lib/slots_block.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'add_slots.dart';

import 'ui_common.dart';
import 'package:smart_drive/theme/app_theme.dart';

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
      backgroundColor: AppColors.background,
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
                gradient: AppGradients.brandHero,
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
                  color: AppColors.onSurfaceInverse, size: _scale(sw, 18, 22, 26)),
              tooltip: 'Back',
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
            title: Text(
              '🚗 Driving School Slots',
              style: AppText.sectionTitle.copyWith(
                color: AppColors.onSurfaceInverse,
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
                  icon: Icon(Icons.add, size: _scale(sw, 14, 16, 18), color: AppColors.onSurfaceInverse),
                  label: Text(
                    'Create Slot',
                    style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse, fontSize: _scale(sw, 12, 13, 14) * ts),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.onSurfaceInverse.withOpacity(0.12),
                    foregroundColor: AppColors.onSurfaceInverse,
                    side: BorderSide(color: AppColors.onSurfaceInverse.withOpacity(0.18)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
                color: AppColors.surface,
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
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                  color: isSelected ? AppColors.danger : AppColors.background,
                  border: Border.all(
                    color: isSelected ? AppColors.danger : AppColors.divider,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('EEE').format(date).toUpperCase(),
                      style: AppText.hintSmall.copyWith(
                        fontSize: dowSize,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? AppColors.onSurfaceInverse : AppColors.onSurfaceMuted,
                      ),
                    ),
                    SizedBox(height: _scale(sw, 1, 1, 2)),
                    Text(
                      DateFormat('d').format(date),
                      style: AppText.tileTitle.copyWith(
                        fontSize: daySize,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface,
                      ),
                    ),
                    SizedBox(height: _scale(sw, 1, 1, 2)),
                    Text(
                      DateFormat('MMM').format(date).toUpperCase(),
                      style: AppText.hintSmall.copyWith(
                        fontSize: monSize,
                        color: isSelected ? AppColors.onSurfaceInverse : AppColors.onSurfaceFaint,
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
      return Center(child: CircularProgressIndicator(color: context.c.primary));
    }

    final ts = Timestamp.fromDate(selectedDate);

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('slots').where('slot_day', isEqualTo: ts).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: AppText.tileSubtitle.copyWith(color: AppColors.danger)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: context.c.primary));
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
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: AppShadows.card,
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: EdgeInsets.all(headerPad),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
                  border: Border(bottom: BorderSide(color: AppColors.divider)),
                ),
                child: Row(
                  children: [
                    Text('🎯', style: AppText.tileTitle.copyWith(fontSize: _scale(sw, 14, 16, 18))),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Available slots for ${DateFormat('EEEE, d MMM').format(selectedDate)} - Select your preferred time',
                        style: AppText.tileSubtitle.copyWith(fontSize: _scale(sw, 12, 13, 14), color: AppColors.onSurfaceMuted),
                      ),
                    ),
                  ],
                ),
              ),

              // Slots
              Expanded(
                child: ListView(
                  children: grouped.entries.map((e) => _buildTimeSlotGroup(context, e.key, e.value)).toList(),
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
            Text('📅', style: AppText.tileTitle.copyWith(fontSize: _scale(sw, 56, 64, 72), color: AppColors.onSurfaceFaint)),
            const SizedBox(height: 16),
            Text(
              'No slots available for ${DateFormat('EEEE, MMM d').format(selectedDate)}',
              style: AppText.tileTitle.copyWith(fontSize: _scale(sw, 16, 18, 20), color: AppColors.onSurfaceMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text('Try selecting a different date', style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted)),
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
        border: Border(bottom: BorderSide(color: AppColors.background)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji $period $timeRange',
            style: AppText.tileTitle.copyWith(fontSize: titleSize, fontWeight: FontWeight.w600, color: AppColors.slate),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsForWidth(constraints.maxWidth);
              final cardW = _cardWidth(constraints.maxWidth, columns, chipGap);

              final slotCards = slots.map((s) => _buildSlotCard(context, s, cardW)).toList();

              if (columns == 1) {
                return Wrap(spacing: 0, runSpacing: chipGap, alignment: WrapAlignment.center, children: slotCards);
              }

              return Wrap(spacing: chipGap, runSpacing: chipGap, alignment: WrapAlignment.start, children: slotCards);
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
    final instructorName = data['instructor_name']?.toString() ?? (data['instructor_user_id']?.toString() ?? 'Unknown');
    final seats = (data['seat'] is num) ? (data['seat'] as num).toInt() : int.tryParse('${data['seat']}') ?? 0;
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
          color: isSelected ? AppColors.success : AppColors.surface,
          border: Border.all(color: isSelected ? AppColors.success : AppColors.divider, width: 2),
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
                  style: AppText.tileTitle.copyWith(
                    fontSize: timeSize,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface,
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: badgePadH, vertical: badgePadV),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.12) : AppColors.brand.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    vehicleType,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.hintSmall.copyWith(
                      fontSize: vehSize,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? AppColors.onSurfaceInverse : AppColors.brand,
                    ),
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Text(
                  '$seats seats',
                  style: AppText.tileSubtitle.copyWith(
                    fontSize: seatsSize,
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.9) : AppColors.onSurface,
                  ),
                ),
                SizedBox(height: _scale(sw, 4, 6, 8)),
                Text(
                  instructorName.length > 22 ? '${instructorName.substring(0, 22)}…' : instructorName,
                  style: AppText.hintSmall.copyWith(
                    fontSize: instSize,
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.9) : AppColors.onSurfaceFaint,
                  ),
                  textAlign: TextAlign.center,
                ),

                // Costs display
                SizedBox(height: _scale(sw, 8, 10, 12)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.12) : AppColors.background,
                    border: Border.all(color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.25) : AppColors.divider),
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
                            style: AppText.tileSubtitle.copyWith(fontSize: moneySize, fontWeight: FontWeight.w500, color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.95) : AppColors.slate),
                          ),
                          Text(
                            _formatCurrency(vehicleCost),
                            style: AppText.tileTitle.copyWith(fontSize: moneySize, fontWeight: FontWeight.w600, color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface),
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
                            style: AppText.tileSubtitle.copyWith(fontSize: moneySize, fontWeight: FontWeight.w500, color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.95) : AppColors.slate),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatCurrency(additionalCost),
                                style: AppText.tileTitle.copyWith(fontSize: moneySize, fontWeight: FontWeight.w600, color: isSelected ? AppColors.onSurfaceInverse : context.c.onSurface),
                              ),
                              if (isAdmin) ...[
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => _editAdditionalCost(slot.id, additionalCost),
                                  child: Icon(Icons.edit, size: 16, color: isSelected ? AppColors.onSurfaceInverse : AppColors.slate),
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
                  style: AppText.tileSubtitle.copyWith(
                    fontSize: availSize,
                    color: isSelected ? AppColors.onSurfaceInverse.withOpacity(0.95) : AppColors.success,
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

  // ————————————————— Edit Additional Cost —————————————————
  Future<void> _editAdditionalCost(String docId, num? current) async {
    if (!isAdmin) return;
    final ctrl = TextEditingController(text: current?.toString() ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Edit Additional Cost', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: Text('Enter amount (INR):', style: AppText.tileSubtitle.copyWith(color: context.c.onSurface))),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.s)),
                hintText: 'e.g. 250',
                hintStyle: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint),
                filled: true,
                fillColor: AppColors.surface,
              ),
              style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: AppText.tileSubtitle.copyWith(color: context.c.primary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: context.c.primary,
              foregroundColor: context.c.onPrimary,
            ),
            child: Text('Save', style: AppText.tileTitle.copyWith(color: context.c.onPrimary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final newVal = num.tryParse(ctrl.text.trim());
    if (newVal == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invalid amount', style: AppText.tileSubtitle.copyWith(color: AppColors.danger))),
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
          SnackBar(content: Text('Additional cost updated', style: AppText.tileSubtitle.copyWith(color: context.c.onSurface))),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e', style: AppText.tileSubtitle.copyWith(color: AppColors.danger))));
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
        title: Text('Delete Slot', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
        content: Text('Are you sure you want to delete slot $slotId?', style: AppText.tileSubtitle.copyWith(color: context.c.onSurface)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: AppText.tileSubtitle.copyWith(color: context.c.primary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.onSurfaceInverse),
            child: Text('Delete', style: AppText.tileTitle.copyWith(color: AppColors.onSurfaceInverse)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await slot.reference.delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Slot $slotId deleted successfully', style: AppText.tileSubtitle.copyWith(color: context.c.onSurface))),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting slot: $e', style: AppText.tileSubtitle.copyWith(color: AppColors.danger))),
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

      Future<void> deleteInBatches(List<QueryDocumentSnapshot> docs) async {
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

      await deleteInBatches(pastSnap.docs);

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

      await deleteInBatches(toDeleteToday);

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
