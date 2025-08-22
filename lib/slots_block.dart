// slots_block.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'add_slots.dart';

class SlotsBlock extends StatefulWidget {
  const SlotsBlock({super.key});

  @override
  State<SlotsBlock> createState() => _SlotsBlockState();
}

class _SlotsBlockState extends State<SlotsBlock> {
  DateTime selectedDate = _atMidnight(DateTime.now());
  String? selectedSlotId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
          SliverAppBar(
            floating: true,
            snap: true,       // hide on scroll, reappear on slight up-scroll
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
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              tooltip: 'Back',
              onPressed: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
            title: const Text(
              '🚗 Driving School Slots',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AddSlotsPage()),
                    );
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Create Slot'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.2),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
        body: Column(
          children: [
            _buildDateSelector(),
            Expanded(
              child: Container(
                color: const Color(0xFFFAFBFC),
                child: _buildSlotsContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ————————————————— UI: Date selector —————————————————
  Widget _buildDateSelector() {
    return Container(
  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  decoration: const BoxDecoration(
    color: Colors.white, // ✅ put color here
    border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
  ),
  child: SizedBox(
    height: 70,
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
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFEF4444) : const Color(0xFFF8F9FA),
                  border: Border.all(
                    color: isSelected ? const Color(0xFFEF4444) : const Color(0xFFE5E7EB),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat('EEE').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.black.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('d').format(date),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMM').format(date).toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
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
  Widget _buildSlotsContent() {
    final ts = Timestamp.fromDate(selectedDate); // matches AddSlotsPage storage

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('slots')
          .where('slot_day', isEqualTo: ts)
          // No orderBy; we'll sort client-side by parsed start time
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
          return _buildEmptyState();
        }

        // Sort by parsed start time
        docs.sort((a, b) {
          final sa = _parseStartTime((a.data() as Map)['slot_time']?.toString() ?? '');
          final sb = _parseStartTime((b.data() as Map)['slot_time']?.toString() ?? '');
          return sa.compareTo(sb);
        });

        // Group by period
        final grouped = _groupSlotsByTimePeriod(docs);

        return Container(
          margin: const EdgeInsets.all(20),
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
                padding: const EdgeInsets.all(12),
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
                    const Text('🎯', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(
                      'Available slots for ${DateFormat('EEEE, d MMM').format(selectedDate)} - Select your preferred time',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),

              // Slots
              Expanded(
                child: ListView(
                  children: grouped.entries.map((e) => _buildTimeSlotGroup(e.key, e.value)).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('📅', style: TextStyle(fontSize: 64, color: Colors.grey)),
          const SizedBox(height: 16),
          Text(
            'No slots available for ${DateFormat('EEEE, MMM d').format(selectedDate)}',
            style: const TextStyle(fontSize: 18, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('Try selecting a different date', style: TextStyle(color: Colors.grey)),
        ],
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

    // Remove empty groups
    grouped.removeWhere((_, v) => v.isEmpty);
    return grouped;
  }

  // ————————————————— Group section —————————————————
  Widget _buildTimeSlotGroup(String period, List<QueryDocumentSnapshot> slots) {
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
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$emoji $period $timeRange',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: slots.map((s) => _buildSlotCard(s)).toList(),
          ),
        ],
      ),
    );
  }

  // ————————————————— Slot card —————————————————
  Widget _buildSlotCard(QueryDocumentSnapshot slot) {
    final data = slot.data() as Map<String, dynamic>;
    final slotId = data['slot_id']?.toString() ?? slot.id;
    final vehicleType = data['vehicle_type']?.toString() ?? 'Unknown';
    final instructorName = data['instructor_name']?.toString() ?? (data['instructor_user_id']?.toString() ?? 'Unknown');
    final seats = (data['seat'] is num) ? (data['seat'] as num).toInt() : int.tryParse('${data['seat']}') ?? 0;
    final timeString = data['slot_time']?.toString() ?? '';

    final isSelected = selectedSlotId == slotId;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedSlotId = isSelected ? null : slotId;
        });
      },
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(12),
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
              children: [
                Text(
                  _formatTimeRange(timeString),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    vehicleType,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF1D4ED8),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$seats seats',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  instructorName.length > 18 ? '${instructorName.substring(0, 18)}…' : instructorName,
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white.withOpacity(0.9) : const Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Available',
                  style: TextStyle(
                    fontSize: 10,
                    color: isSelected ? Colors.white.withOpacity(0.95) : const Color(0xFF10B981),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            // Edit / Delete
            Positioned(
              top: 0,
              right: 0,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _editSlot(slot.id, data),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.edit, size: 12, color: Color(0xFF1D4ED8)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _deleteSlot(slot),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(Icons.delete, size: 12, color: Color(0xFFDC2626)),
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

  // ————————————————— Edit / Delete —————————————————
  Future<void> _editSlot(String docId, Map<String, dynamic> data) async {
    final slotIdCtrl = TextEditingController(text: data['slot_id']?.toString() ?? '');
    final vehicleTypeCtrl = TextEditingController(text: data['vehicle_type']?.toString() ?? '');
    final instructorCtrl = TextEditingController(text: data['instructor_user_id']?.toString() ?? '');
    final seatsCtrl = TextEditingController(text: (data['seat']?.toString() ?? ''));
    final timeCtrl = TextEditingController(text: data['slot_time']?.toString() ?? '');
    DateTime dialogDate = (data['slot_day'] is Timestamp)
        ? (data['slot_day'] as Timestamp).toDate()
        : selectedDate;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Text('Edit Slot', style: TextStyle(fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFormField('Slot ID', slotIdCtrl),
                const SizedBox(height: 12),
                _buildFormField('Vehicle Type', vehicleTypeCtrl),
                const SizedBox(height: 12),
                _buildFormField('Instructor ID', instructorCtrl),
                const SizedBox(height: 12),
                _buildFormField('Seats', seatsCtrl, isNumber: true),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Day', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                      initialDate: dialogDate,
                    );
                    if (picked != null) {
                      setStateDialog(() => dialogDate = _atMidnight(picked));
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(DateFormat('yyyy-MM-dd').format(dialogDate)),
                  ),
                ),
                const SizedBox(height: 12),
                _buildFormField('Time (e.g. 09:00 AM - 10:00 AM)', timeCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await FirebaseFirestore.instance.collection('slots').doc(docId).update({
                    'slot_id': slotIdCtrl.text.trim(),
                    'vehicle_type': vehicleTypeCtrl.text.trim(),
                    'instructor_user_id': instructorCtrl.text.trim(),
                    'seat': int.tryParse(seatsCtrl.text.trim()) ?? data['seat'],
                    'slot_day': Timestamp.fromDate(_atMidnight(dialogDate)),
                    'slot_time': timeCtrl.text.trim(),
                    'updated_at': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Slot updated successfully')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error updating slot: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField(String label, TextEditingController controller, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF374151))),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF6366F1)),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

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

  // ————————————————— Helpers —————————————————
  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Parse start time from "09:00 AM - 10:00 AM". Falls back to 00:00 if invalid.
  DateTime _parseStartTime(String slotTime) {
    try {
      final start = slotTime.split(' - ').first.trim();
      final t = DateFormat('hh:mm a').parseStrict(start);
      // Return with today's date just for ordering/grouping
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day, t.hour, t.minute);
    } catch (_) {
      return DateTime(1970); // minimal
    }
  }

  String _formatTimeRange(String slotTime) {
    // Already stored as "hh:mm a - hh:mm a"; if malformed, just return it.
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
}
