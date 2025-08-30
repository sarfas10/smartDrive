// lib/add_slots.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart'; // for context.wp(), context.hp(), context.sp()

class AddSlotsPage extends StatefulWidget {
  const AddSlotsPage({super.key});

  @override
  State<AddSlotsPage> createState() => _AddSlotsPageState();
}

class _AddSlotsPageState extends State<AddSlotsPage> {
  // ====== Theme / Colors ======
  static const Color kBgStart = Color(0xFF667EEA);
  static const Color kBgEnd = Color(0xFF764BA2);
  static const Color kPrimary = Color(0xFF1976D2);
  static const Color kPrimaryDark = Color(0xFF1565C0);
  static const Color kTodayBorder = Color(0xFF1976D2);
  static const Color kChipGreen = Color(0xFFA5D6A7);
  static const Color kChipGreenBg = Color(0xFFC8E6C9);
  static const Color kSummaryBgStart = Color(0xFFE8F5E8);
  static const Color kSummaryBgEnd = Color(0xFFF1F8E9);
  static const Color kOrange = Color(0xFFFF9800);

  // ====== State ======
  DateTime currentMonth = _todayMidnight();

  final Set<DateTime> selectedDates = {};
  final Set<String> selectedTimeSlots = {};     // keys like "09:00 AM-10:00 AM"
  final Set<String> selectedInstructorIds = {}; // instructor userIds
  final Set<String> selectedVehicleIds = {};    // vehicle_ids

  // Additional charges (added to vehicle charge to get final slot_cost)
  double _additionalCharges = 0.0;
  final TextEditingController _additionalChargesController = TextEditingController();

  // Instructors (from Firestore)
  bool _loadingInstructors = true;
  List<_Instructor> instructors = [];
  final Map<String, String> _instructorNamesById = {}; // userId -> display name

  // Vehicles (from Firestore)
  bool _loadingVehicles = true;
  List<_Vehicle> vehicles = [];
  final Map<String, _Vehicle> _vehicleById = {};       // vehicle_id -> model

  // --- Live booked-state (from Firestore) ---
  bool _loadingBooked = false;

  // dayKey -> set of time keys (no spaces) that are fully booked that day
  Map<String, Set<String>> _fullyBookedByDay = {};

  // union of fully-booked times across currently selected days (keys without spaces)
  Set<String> _disabledTimeSlots = {};

  // ====== UI Lock to prevent concurrent selections ======
  bool _uiLock = false;
  bool get _isBusy => _loadingBooked || _uiLock;

  Future<void> _runLocked(Future<void> Function() task) async {
    if (_isBusy) return; // ignore re-entrant taps
    setState(() => _uiLock = true);
    try {
      await task();
    } finally {
      if (mounted) setState(() => _uiLock = false);
    }
  }

  // ====== Static Time Slots ======
  final List<_TimeSlot> timeSlots = const [
    _TimeSlot('09:00 AM', '10:00 AM', false),
    _TimeSlot('10:00 AM', '11:00 AM', false),
    _TimeSlot('11:00 AM', '12:00 PM', false),
    _TimeSlot('12:00 PM', '01:00 PM', false),
    _TimeSlot('02:00 PM', '03:00 PM', false),
    _TimeSlot('03:00 PM', '04:00 PM', false),
    _TimeSlot('04:00 PM', '05:00 PM', false),
    _TimeSlot('05:00 PM', '06:00 PM', false),
  ];

  // ====== Lifecycle ======
  @override
  void initState() {
    super.initState();
    _fetchVehicles();
    _fetchInstructors();
    _additionalChargesController.addListener(_updateAdditionalCharges);
  }

  @override
  void dispose() {
    _additionalChargesController.removeListener(_updateAdditionalCharges);
    _additionalChargesController.dispose();
    super.dispose();
  }

  void _updateAdditionalCharges() {
    setState(() {
      _additionalCharges = double.tryParse(_additionalChargesController.text.trim()) ?? 0.0;
    });
  }

  Future<void> _fetchVehicles() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('vehicles')
          .orderBy('created_at', descending: false)
          .get();

      final list = <_Vehicle>[];
      for (final d in q.docs) {
        final m = d.data();
        final id = d.id;
        final type = (m['car_type'] ?? '').toString().trim();
        final charge = (m['vehicle_charge'] is num)
            ? (m['vehicle_charge'] as num).toDouble()
            : 0.0;
        if (type.isEmpty) continue;

        final v = _Vehicle(id: id, carType: type, charge: charge);
        list.add(v);
        _vehicleById[id] = v;
      }

      setState(() {
        vehicles = list;
        _loadingVehicles = false;
      });

      if (selectedDates.isNotEmpty) _refreshBookedTimes();
    } catch (e) {
      setState(() => _loadingVehicles = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load vehicles: $e')),
      );
    }
  }

  Future<void> _fetchInstructors() async {
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'instructor')
          .get();
      final list = <_Instructor>[];
      for (final d in q.docs) {
        final m = d.data();
        final name = (m['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;
        final available = (m['available'] == true) ? true : true; // default true
        final rating = (m['rating'] is num) ? (m['rating'] as num).toDouble() : null;

        list.add(_Instructor(
          id: d.id,
          name: name,
          subtitle: (m['subtitle'] ?? 'Instructor').toString(),
          rating: rating,
          available: available,
        ));
        _instructorNamesById[d.id] = name;
      }

      setState(() {
        instructors = list;
        _loadingInstructors = false;
      });

      if (selectedDates.isNotEmpty) _refreshBookedTimes();
    } catch (e) {
      setState(() => _loadingInstructors = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load instructors: $e')),
      );
    }
  }

  // ====== Helpers ======
  static DateTime _todayMidnight() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _atMidnight(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool get hasAllSelections =>
      selectedDates.isNotEmpty &&
      selectedTimeSlots.isNotEmpty &&
      selectedVehicleIds.isNotEmpty &&
      selectedInstructorIds.isNotEmpty;

  int get totalCombinations =>
      selectedDates.length *
      selectedTimeSlots.length *
      selectedVehicleIds.length *
      selectedInstructorIds.length;

  Set<String> get _allVehicleIds => vehicles.map((v) => v.id).toSet();

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}' ;

  String _timeKeyNoSpace(String slotTimeWithSpaces) =>
      slotTimeWithSpaces.replaceAll(' - ', '-');

  double _clampd(double v, double min, double max) => v < min ? min : (v > max ? max : v);

  // ====== Firestore "fully booked" check ======
  Future<void> _refreshBookedTimes() async {
    if (selectedDates.isEmpty) {
      setState(() {
        _fullyBookedByDay.clear();
        _disabledTimeSlots.clear();
        _loadingBooked = false;
      });
      return;
    }

    setState(() => _loadingBooked = true);

    try {
      final Map<String, Set<String>> bookedByDay = {};
      final allVehicleIds = _allVehicleIds;

      for (final day in selectedDates) {
        final ts = Timestamp.fromDate(_atMidnight(day));
        final dk = _dayKey(day);

        if (allVehicleIds.isEmpty) {
          bookedByDay[dk] = <String>{};
          continue;
        }

        final snap = await FirebaseFirestore.instance
            .collection('slots')
            .where('slot_day', isEqualTo: ts)
            .get();

        // time -> vehicle_ids present
        final Map<String, Set<String>> vehiclesByTime = {};
        for (final doc in snap.docs) {
          final m = doc.data();
          final t = (m['slot_time'] ?? '').toString(); // "09:00 AM - 10:00 AM"
          final vid = (m['vehicle_id'] ?? '').toString();
          if (t.isEmpty || vid.isEmpty) continue;
          vehiclesByTime.putIfAbsent(t, () => <String>{}).add(vid);
        }

        final fully = <String>{};
        for (final s in timeSlots) {
          final label = '${s.start} - ${s.end}';
          final present = vehiclesByTime[label];
          if (present != null && allVehicleIds.difference(present).isEmpty) {
            fully.add(_timeKeyNoSpace(label)); // e.g. "09:00 AM-10:00 AM"
          }
        }
        bookedByDay[dk] = fully;
      }

      final union = <String>{};
      for (final set in bookedByDay.values) {
        union.addAll(set);
      }

      setState(() {
        _fullyBookedByDay = bookedByDay;
        _disabledTimeSlots = union;
        _loadingBooked = false;
        selectedTimeSlots.removeWhere((k) => _disabledTimeSlots.contains(k));
      });
    } catch (e) {
      setState(() => _loadingBooked = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to check booked times: $e')),
      );
    }
  }

  // ====== Actions ======
  void _prevMonth() {
    if (_isBusy) return;
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    if (_isBusy) return;
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1, 1);
    });
  }

  // Renamed: pure state change (no refresh, locked handled outside)
  void _toggleDateInternal(DateTime date) {
    final d = _atMidnight(date);
    setState(() {
      final contains = selectedDates.any((x) => _isSameDate(x, d));
      if (contains) {
        selectedDates.removeWhere((x) => _isSameDate(x, d));
      } else {
        selectedDates.add(d);
      }
    });
  }

  // Uses UI lock to avoid concurrent taps and runs refresh
  void _onTapCalendarDate(DateTime date) {
    final today = _todayMidnight();
    if (date.isBefore(today)) return;

    _runLocked(() async {
      _toggleDateInternal(date);
      await _refreshBookedTimes();
    });
  }

  Future<void> _addSlots() async {
    if (!hasAllSelections || _isBusy) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: Text('Create $totalCombinations slot document(s) in Firestore?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes, Create')),
        ],
      ),
    );
    if (confirm != true) return;

    await _runLocked(() async {
      try {
        final batch = FirebaseFirestore.instance.batch();
        int toWrite = 0;
        int skipped = 0;

        final sortedDates = selectedDates.toList()..sort((a, b) => a.compareTo(b));

        for (final day in sortedDates) {
          final dayAtMidnight = Timestamp.fromDate(_atMidnight(day));
          final dk = _dayKey(day);

          for (final timeKey in selectedTimeSlots) {
            final fully = _fullyBookedByDay[dk] ?? const <String>{};
            if (fully.contains(timeKey)) {
              skipped++;
              continue;
            }

            final slotTime = timeKey.replaceAll('-', ' - '); // "09:00 AM - 10:00 AM"

            for (final vehicleId in selectedVehicleIds) {
              final v = _vehicleById[vehicleId];
              final vehicleCost = v?.charge ?? 0.0; // separate vehicle cost
              final additionalCost = _additionalCharges; // separate additional cost

              for (final instructorId in selectedInstructorIds) {
                final docRef = FirebaseFirestore.instance.collection('slots').doc();
                final data = {
                  'slot_id'           : docRef.id,
                  'slot_day'          : dayAtMidnight,
                  'slot_time'         : slotTime,
                  'vehicle_id'        : vehicleId,
                  'vehicle_type'      : v?.carType ?? '',
                  'instructor_user_id': instructorId,
                  'instructor_name'   : _instructorNamesById[instructorId] ?? '',
                  // no 'seat'
                  'vehicle_cost'      : vehicleCost,
                  'additional_cost'   : additionalCost,
                  'slot_cost'         : vehicleCost + additionalCost, // backward compatibility
                  'created_at'        : FieldValue.serverTimestamp(),
                };
                batch.set(docRef, data);
                toWrite++;
              }
            }
          }
        }

        if (toWrite == 0) {
          final txt = (vehicles.isEmpty)
              ? 'No vehicle available.'
              : (instructors.isEmpty)
                  ? 'No instructor available.'
                  : (skipped > 0
                      ? 'All selected (day × time) were already fully booked.'
                      : 'Nothing to create.');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt)));
          return;
        }

        await batch.commit();

        if (!mounted) return;
        final msg = skipped > 0
            ? 'Created $toWrite document(s). Skipped $skipped fully-booked (day × time) combo(s).'
            : 'Created $toWrite slot document(s).';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

        // Force clear even though we're still inside _runLocked (busy state)
        _clearAll(force: true);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create slots: $e')),
        );
      }
    });
  }

  void _toggleTimeSlot(_TimeSlot slot) async {
    if (_isBusy) return; // ignore while loading/locked

    final key = '${slot.start}-${slot.end}';
    if (_disabledTimeSlots.contains(key)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This time is fully booked on a selected day.')),
      );
      return;
    }

    setState(() {
      if (selectedTimeSlots.contains(key)) {
        selectedTimeSlots.remove(key);
      } else {
        selectedTimeSlots.add(key);
      }
    });

    // brief UI lock to avoid fast double taps on multiple tiles
    setState(() => _uiLock = true);
    await Future.delayed(const Duration(milliseconds: 250));
    if (mounted) setState(() => _uiLock = false);
  }

  void _toggleInstructor(_Instructor ins) {
    if (!ins.available || _isBusy) return;
    setState(() {
      if (selectedInstructorIds.contains(ins.id)) {
        selectedInstructorIds.remove(ins.id);
      } else {
        selectedInstructorIds.add(ins.id);
      }
    });
  }

  void _toggleVehicle(_Vehicle v) {
    if (_isBusy) return;
    setState(() {
      if (selectedVehicleIds.contains(v.id)) {
        selectedVehicleIds.remove(v.id);
      } else {
        selectedVehicleIds.add(v.id);
      }
    });
  }

  // NOTE: added {bool force = false} and busy check respects force
  void _clearAll({bool force = false}) {
    if (_isBusy && !force) return;
    setState(() {
      selectedDates.clear();
      selectedTimeSlots.clear();
      selectedInstructorIds.clear();
      selectedVehicleIds.clear();
      _additionalCharges = 0.0;
      _additionalChargesController.clear();

      _fullyBookedByDay.clear();
      _disabledTimeSlots.clear();
      _loadingBooked = false;
    });
  }

  // ====== Build ======
  @override
  Widget build(BuildContext context) {
    final noVehicles = !_loadingVehicles && vehicles.isEmpty;
    final noInstructors = !_loadingInstructors && instructors.isEmpty;

    final pagePad = EdgeInsets.all(_clampd(context.wp(4), 12, 28));
    final boxRadius = _clampd(context.sp(1.4), 10, 16);
    final boxPad = EdgeInsets.all(_clampd(context.wp(3), 16, 28));
    final boxShadowBlur = _clampd(context.sp(2.2), 10, 24);
    final btnVPad = _clampd(context.hp(1.8), 12, 20);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main content; taps blocked while busy
          AbsorbPointer(
            absorbing: _isBusy,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverAppBar(
                  floating: true,
                  snap: true,
                  pinned: false,
                  backgroundColor: Colors.white,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new, color: const Color(0xFF333333), size: _clampd(context.sp(2.2), 18, 22)),
                    tooltip: 'Back',
                    onPressed: () {
                      if (Navigator.canPop(context)) Navigator.pop(context);
                    },
                  ),
                ),
              ],
              body: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: pagePad,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(boxRadius),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(color: Colors.black26, blurRadius: boxShadowBlur, offset: const Offset(0, 12))
                            ],
                            border: Border.all(color: const Color(0xFFE3F2FD)),
                          ),
                          child: Padding(
                            padding: boxPad,
                            child: Column(
                              children: [
                                // Calendar
                                _Section(
                                  icon: Icons.calendar_month_outlined,
                                  title: 'Select Dates',
                                  titleSize: _clampd(context.sp(2.4), 16, 22),
                                  iconSize: _clampd(context.sp(2.2), 18, 22),
                                  child: _CalendarCard(
                                    currentMonth: currentMonth,
                                    onPrev: _prevMonth,
                                    onNext: _nextMonth,
                                    selectedDates: selectedDates,
                                    onTapDate: _onTapCalendarDate,
                                    locked: _isBusy, // NEW
                                  ),
                                ),
                                SizedBox(height: _clampd(context.hp(2), 12, 22)),

                                // Time Slots
                                _Section(
                                  icon: Icons.access_time,
                                  title: 'Select Time Slots',
                                  titleSize: _clampd(context.sp(2.4), 16, 22),
                                  iconSize: _clampd(context.sp(2.2), 18, 22),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _CardBox(
                                        child: _TimeSlotGrid(
                                          slots: timeSlots,
                                          selected: selectedTimeSlots,
                                          disabled: _disabledTimeSlots,
                                          onTap: _toggleTimeSlot,
                                          locked: _isBusy, // NEW
                                        ),
                                      ),
                                      if (_loadingBooked) SizedBox(height: _clampd(context.hp(1), 6, 12)),
                                      if (_loadingBooked) const LinearProgressIndicator(minHeight: 2),
                                      SizedBox(height: _clampd(context.hp(1.5), 10, 16)),
                                      if (selectedTimeSlots.isNotEmpty)
                                        _InfoBar(
                                          color: const Color(0xFFE3F2FD),
                                          icon: Icons.info_outline,
                                          text: '${selectedTimeSlots.length} time slot${selectedTimeSlots.length > 1 ? 's' : ''} selected',
                                          textColor: kPrimary,
                                          padH: _clampd(context.wp(3), 12, 20),
                                          padV: _clampd(context.hp(1), 8, 14),
                                          iconSize: _clampd(context.sp(2), 16, 20),
                                          fontSize: _clampd(context.sp(1.8), 12, 15),
                                        ),
                                      SizedBox(height: _clampd(context.hp(1), 8, 12)),
                                      if (_disabledTimeSlots.isNotEmpty)
                                        _InfoBar(
                                          color: const Color(0xFFFFF3E0),
                                          icon: Icons.block,
                                          text: 'Some times are BOOKED on selected day(s) because all vehicles already exist.',
                                          textColor: kOrange,
                                          padH: _clampd(context.wp(3), 12, 20),
                                          padV: _clampd(context.hp(1), 8, 14),
                                          iconSize: _clampd(context.sp(2), 16, 20),
                                          fontSize: _clampd(context.sp(1.8), 12, 15),
                                        ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: _clampd(context.hp(2), 12, 22)),

                                // Booking Summary
                                if (hasAllSelections)
                                  _BookingSummary(
                                    selectedDates: selectedDates,
                                    selectedTimeSlots: selectedTimeSlots,
                                    selectedCarTypes:
                                        selectedVehicleIds.map((id) => _vehicleById[id]?.carType ?? id).toSet(),
                                    selectedInstructors:
                                        selectedInstructorIds.map((id) => _instructorNamesById[id] ?? id).toSet(),
                                    totalCombinations: totalCombinations,
                                    pad: EdgeInsets.all(_clampd(context.wp(3), 12, 20)),
                                    radius: _clampd(context.sp(1.2), 10, 14),
                                    titleFs: _clampd(context.sp(2.2), 16, 20),
                                    labelFs: _clampd(context.sp(1.8), 12, 15),
                                    chipFs: _clampd(context.sp(1.6), 11, 13),
                                  ),

                                SizedBox(height: _clampd(context.hp(2), 12, 22)),

                                // Vehicles
                                _Section(
                                  icon: Icons.directions_car_filled,
                                  title: 'Select Vehicles',
                                  titleSize: _clampd(context.sp(2.4), 16, 22),
                                  iconSize: _clampd(context.sp(2.2), 18, 22),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _CardBox(
                                        child: _loadingVehicles
                                            ? Padding(
                                                padding: EdgeInsets.all(_clampd(context.wp(3), 12, 20)),
                                                child: const Center(child: CircularProgressIndicator()),
                                              )
                                            : (vehicles.isEmpty
                                                ? const _EmptyBanner(text: 'No vehicle available')
                                                : _VehicleGrid(
                                                    vehicles: vehicles,
                                                    selected: selectedVehicleIds,
                                                    onTap: _toggleVehicle,
                                                  )),
                                      ),
                                      SizedBox(height: _clampd(context.hp(1.5), 10, 16)),
                                      if (selectedVehicleIds.isNotEmpty)
                                        _InfoBar(
                                          color: const Color(0xFFE3F2FD),
                                          icon: Icons.info_outline,
                                          text: '${selectedVehicleIds.length} vehicle${selectedVehicleIds.length > 1 ? 's' : ''} selected',
                                          textColor: kPrimary,
                                          padH: _clampd(context.wp(3), 12, 20),
                                          padV: _clampd(context.hp(1), 8, 14),
                                          iconSize: _clampd(context.sp(2), 16, 20),
                                          fontSize: _clampd(context.sp(1.8), 12, 15),
                                        ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: _clampd(context.hp(2), 12, 22)),

                                // Additional Charges Section
                                _Section(
                                  icon: Icons.add_circle_outline,
                                  title: 'Additional Charges',
                                  titleSize: _clampd(context.sp(2.4), 16, 22),
                                  iconSize: _clampd(context.sp(2.2), 18, 22),
                                  child: _CardBox(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.monetization_on, color: kPrimary, size: _clampd(context.sp(2), 16, 20)),
                                            SizedBox(width: _clampd(context.wp(2), 8, 12)),
                                            Text('Additional Charges per Slot',
                                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: _clampd(context.sp(1.9), 13, 16))),
                                          ],
                                        ),
                                        SizedBox(height: _clampd(context.hp(1.2), 8, 14)),
                                        TextField(
                                          controller: _additionalChargesController,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(color: Colors.black),
                                          decoration: InputDecoration(
                                            hintText: 'Enter additional charges (₹)',
                                            prefixText: '₹ ',
                                            prefixStyle: const TextStyle(color: Colors.black),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(_clampd(context.sp(1.2), 8, 12)),
                                              borderSide: const BorderSide(color: Color(0xFFE3F2FD)),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(_clampd(context.sp(1.2), 8, 12)),
                                              borderSide: const BorderSide(color: kPrimary, width: 2),
                                            ),
                                            contentPadding: EdgeInsets.symmetric(
                                              horizontal: _clampd(context.wp(3), 12, 18),
                                              vertical: _clampd(context.hp(1.2), 10, 14),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: _clampd(context.hp(1), 8, 12)),
                                        Text(
                                          'This amount will be added to the base vehicle cost for each created slot.',
                                          style: TextStyle(fontSize: _clampd(context.sp(1.6), 11, 13), color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                SizedBox(height: _clampd(context.hp(2), 12, 22)),

                                // Instructors
                                _Section(
                                  icon: Icons.person_pin_circle_outlined,
                                  title: 'Select Instructors',
                                  titleSize: _clampd(context.sp(2.4), 16, 22),
                                  iconSize: _clampd(context.sp(2.2), 18, 22),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      _CardBox(
                                        child: _loadingInstructors
                                            ? Padding(
                                                padding: EdgeInsets.all(_clampd(context.wp(3), 12, 20)),
                                                child: const Center(child: CircularProgressIndicator()),
                                              )
                                            : (instructors.isEmpty
                                                ? const _EmptyBanner(text: 'No instructor available')
                                                : _InstructorGrid(
                                                    instructors: instructors,
                                                    selected: selectedInstructorIds,
                                                    onTap: _toggleInstructor,
                                                  )),
                                      ),
                                      SizedBox(height: _clampd(context.hp(1.5), 10, 16)),
                                      if (selectedInstructorIds.isNotEmpty)
                                        _InfoBar(
                                          color: const Color(0xFFE3F2FD),
                                          icon: Icons.info_outline,
                                          text: '${selectedInstructorIds.length} instructor${selectedInstructorIds.length > 1 ? 's' : ''} selected',
                                          textColor: kPrimary,
                                          padH: _clampd(context.wp(3), 12, 20),
                                          padV: _clampd(context.hp(1), 8, 14),
                                          iconSize: _clampd(context.sp(2), 16, 20),
                                          fontSize: _clampd(context.sp(1.8), 12, 15),
                                        ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: _clampd(context.hp(2), 12, 22)),

                                // Actions
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: _clearAll,
                                        style: OutlinedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(vertical: btnVPad),
                                        ),
                                        child: const Text('Clear All'),
                                      ),
                                    ),
                                    SizedBox(width: _clampd(context.wp(3), 12, 16)),
                                    Expanded(
                                      flex: 2,
                                      child: ElevatedButton(
                                        onPressed: hasAllSelections && !_isBusy ? _addSlots : null,
                                        style: ElevatedButton.styleFrom(
                                          padding: EdgeInsets.symmetric(vertical: btnVPad),
                                          backgroundColor: hasAllSelections && !_isBusy ? kPrimary : Colors.grey.shade300,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Add Slots'),
                                      ),
                                    ),
                                  ],
                                ),

                                SizedBox(height: _clampd(context.hp(1), 8, 12)),
                                if (noVehicles)
                                  _InfoBar(
                                    color: const Color(0xFFFFF3E0),
                                    icon: Icons.info_outline,
                                    text: 'No vehicle available',
                                    textColor: kOrange,
                                    padH: _clampd(context.wp(3), 12, 20),
                                    padV: _clampd(context.hp(1), 8, 14),
                                    iconSize: _clampd(context.sp(2), 16, 20),
                                    fontSize: _clampd(context.sp(1.8), 12, 15),
                                  ),
                                if (noInstructors) SizedBox(height: _clampd(context.hp(1), 8, 12)),
                                if (noInstructors)
                                  _InfoBar(
                                    color: const Color(0xFFFFF3E0),
                                    icon: Icons.info_outline,
                                    text: 'No instructor available',
                                    textColor: kOrange,
                                    padH: _clampd(context.wp(3), 12, 20),
                                    padV: _clampd(context.hp(1), 8, 14),
                                    iconSize: _clampd(context.sp(2), 16, 20),
                                    fontSize: _clampd(context.sp(1.8), 12, 15),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Busy overlay with circular loader
          if (_isBusy)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.35),
                child: const Center(
                  child: SizedBox(width: 44, height: 44, child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ====== Widgets ======

class _Section extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final double? titleSize;
  final double? iconSize;

  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.titleSize,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final hGap = _AddSlotsPageState()._clampd(context.wp(2), 8, 12);
    final vGap = _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14);
    final fs = titleSize ?? _AddSlotsPageState()._clampd(context.sp(2.4), 16, 22);
    final iSize = iconSize ?? _AddSlotsPageState()._clampd(context.sp(2.2), 18, 22);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, color: _AddSlotsPageState.kPrimary, size: iSize),
          SizedBox(width: hGap),
          Text(title,
              style: TextStyle(
                  fontSize: fs, fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
        ]),
        SizedBox(height: vGap),
        child,
      ],
    );
  }
}

class _CardBox extends StatelessWidget {
  final Widget child;
  const _CardBox({required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = _AddSlotsPageState()._clampd(context.sp(1.2), 8, 12);
    final pad = EdgeInsets.all(_AddSlotsPageState()._clampd(context.wp(3), 12, 20));
    final blur = _AddSlotsPageState()._clampd(context.sp(2), 8, 16);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE3F2FD)),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: blur, offset: const Offset(0, 4))],
      ),
      child: Padding(padding: pad, child: child),
    );
  }
}

class _CalendarCard extends StatelessWidget {
  final DateTime currentMonth;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final Set<DateTime> selectedDates;
  final void Function(DateTime) onTapDate;
  final bool locked; // NEW

  const _CalendarCard({
    required this.currentMonth,
    required this.onPrev,
    required this.onNext,
    required this.selectedDates,
    required this.onTapDate,
    required this.locked, // NEW
  });

  @override
  Widget build(BuildContext context) {
    final monthYear = '${_monthNames[currentMonth.month - 1]} ${currentMonth.year}';
    final days = _buildCalendarDays(currentMonth);

    final labelFs = _AddSlotsPageState()._clampd(context.sp(2), 15, 18);
    final navIcon = _AddSlotsPageState()._clampd(context.sp(2.2), 18, 22);
    final weekFs = _AddSlotsPageState()._clampd(context.sp(1.8), 12, 14);
    final gap = _AddSlotsPageState()._clampd(context.wp(1), 4, 10);
    final cellRadius = _AddSlotsPageState()._clampd(context.sp(1), 6, 10);

    return _CardBox(
      child: Column(
        children: [
          Row(
            children: [
              _IconBtn(icon: Icons.chevron_left, onTap: locked ? (){} : onPrev, size: navIcon),
              Expanded(
                child: Center(
                  child: Text(
                    monthYear,
                    style: TextStyle(fontSize: labelFs, fontWeight: FontWeight.w600, color: const Color(0xFF333333)),
                  ),
                ),
              ),
              _IconBtn(icon: Icons.chevron_right, onTap: locked ? (){} : onNext, size: navIcon),
            ],
          ),
          SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              _WeekdayLabel('Sun', fs: 0), // fs overridden below via DefaultTextStyle
              _WeekdayLabel('Mon', fs: 0),
              _WeekdayLabel('Tue', fs: 0),
              _WeekdayLabel('Wed', fs: 0),
              _WeekdayLabel('Thu', fs: 0),
              _WeekdayLabel('Fri', fs: 0),
              _WeekdayLabel('Sat', fs: 0),
            ],
          ),
          SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1), 6, 12)),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: weekFs),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellSize = (constraints.maxWidth - 6 * gap) / 7;

                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: days.map((d) {
                    final isCurrentMonth = d.month == currentMonth.month;
                    final today = _AddSlotsPageState._todayMidnight();
                    final isPast = d.isBefore(today);
                    final isToday = _isSameDate(d, today);
                    final isSelected = selectedDates.any((x) => _isSameDate(x, d));

                    Color? bg;
                    Color fg = Colors.black87;
                    BoxBorder? border;
                    final opacity = isCurrentMonth ? 1.0 : 0.3;
                    MouseCursor cursor = SystemMouseCursors.click;

                    if (isPast && isCurrentMonth) {
                      fg = Colors.black38;
                      cursor = SystemMouseCursors.forbidden;
                    }
                    if (isToday) {
                      border = Border.all(color: _AddSlotsPageState.kTodayBorder, width: 2);
                      fg = Colors.black87;
                    }
                    if (isSelected) {
                      bg = _AddSlotsPageState.kPrimary;
                      fg = Colors.white;
                      border = Border.all(color: _AddSlotsPageState.kPrimary, width: 2);
                    }

                    return MouseRegion(
                      cursor: locked ? SystemMouseCursors.forbidden : cursor,
                      child: GestureDetector(
                        onTap: () {
                          if (locked) return;
                          if (!isCurrentMonth) return;
                          if (isPast) return;
                          onTapDate(d);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: cellSize,
                          height: cellSize,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(cellRadius),
                            border: border,
                          ),
                          alignment: Alignment.center,
                          child: Opacity(
                            opacity: opacity,
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(
                                    d.day.toString(),
                                    style: TextStyle(
                                      fontWeight: (isToday || isSelected) ? FontWeight.w600 : FontWeight.w400,
                                      color: fg,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Positioned(
                                    top: 2,
                                    right: 4,
                                    child: Icon(Icons.check, size: 14, color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static List<DateTime> _buildCalendarDays(DateTime monthAnchor) {
    final first = DateTime(monthAnchor.year, monthAnchor.month, 1);
    final weekdayIndex = first.weekday % 7; // Monday=1..Sunday=7 -> Sunday=0
    final start = first.subtract(Duration(days: weekdayIndex));
    return List<DateTime>.generate(42, (i) => DateTime(start.year, start.month, start.day + i));
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  const _IconBtn({required this.icon, required this.onTap, required this.size});

  @override
  Widget build(BuildContext context) {
    final pad = _AddSlotsPageState()._clampd(context.wp(1.8), 6, 10);
    return InkResponse(
      onTap: onTap,
      radius: size + 2,
      child: Container(
        padding: EdgeInsets.all(pad),
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: Icon(icon, color: _AddSlotsPageState.kPrimary, size: size),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String text;
  final double fs;
  const _WeekdayLabel(this.text, {required this.fs});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(text,
            style: TextStyle(fontSize: fs == 0 ? _AddSlotsPageState()._clampd(context.sp(1.8), 12, 14) : fs,
                fontWeight: FontWeight.w600, color: const Color(0xFF666666))),
      ),
    );
  }
}

class _TimeSlotGrid extends StatelessWidget {
  final List<_TimeSlot> slots;
  final Set<String> selected;
  final Set<String> disabled; // keys without spaces
  final void Function(_TimeSlot) onTap;
  final bool locked; // NEW

  const _TimeSlotGrid({
    required this.slots,
    required this.selected,
    required this.disabled,
    required this.onTap,
    required this.locked, // NEW
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final targetTileW = _AddSlotsPageState()._clampd(context.wp(28), 200, 320);
      int columns = (c.maxWidth / targetTileW).floor().clamp(1, 4);
      final gap = _AddSlotsPageState()._clampd(context.wp(1.5), 8, 14);
      final totalGap = gap * (columns - 1);
      final tileW = (c.maxWidth - totalGap) / columns;

      // Dynamic extra height to avoid tiny overflows with larger text scales
      final baseTileH = _AddSlotsPageState()._clampd(context.hp(9), 72, 110);
      final textScale = MediaQuery.of(context).textScaleFactor;
      final extraH = 4 + ((textScale - 1.0).clamp(0.0, 0.6) * 24);
      final aspect = tileW / (baseTileH + extraH);

      final startFs = _AddSlotsPageState()._clampd(context.sp(1.9), 13, 16);
      final endFs = _AddSlotsPageState()._clampd(context.sp(1.6), 11, 13);
      final radius = _AddSlotsPageState()._clampd(context.sp(1.1), 8, 10);
      final padH = _AddSlotsPageState()._clampd(context.wp(2.6), 12, 16);
      final padV = _AddSlotsPageState()._clampd(context.hp(1), 8, 12);

      return GridView.builder(
        itemCount: slots.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: aspect,
        ),
        itemBuilder: (context, i) {
          final s = slots[i];
          final key = '${s.start}-${s.end}';
          final isSelected = selected.contains(key);
          final isBooked = disabled.contains(key);

          Color bg;
          Color border;
          Color fg;

          if (isBooked) {
            bg = const Color(0xFFF5F5F5);
            border = const Color(0xFFCCCCCC);
            fg = const Color(0xFF999999);
          } else if (isSelected) {
            bg = _AddSlotsPageState.kPrimary;
            border = _AddSlotsPageState.kPrimary;
            fg = Colors.white;
          } else {
            bg = const Color(0xFFE3F2FD);
            border = const Color(0xFFBBDEFB);
            fg = _AddSlotsPageState.kPrimary;
          }

          return GestureDetector(
            onTap: (isBooked || locked) ? null : () => onTap(s),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: border, width: 1.5),
              ),
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(s.start, style: TextStyle(fontWeight: FontWeight.w600, color: fg, fontSize: startFs)),
                      SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.3), 2, 4)),
                      Opacity(opacity: 0.8, child: Text(s.end, style: TextStyle(color: fg, fontSize: endFs))),
                    ],
                  ),
                  if (isBooked)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'BOOKED',
                        style: TextStyle(color: fg, fontSize: _AddSlotsPageState()._clampd(context.sp(1.6), 11, 12), fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (isSelected && !isBooked)
                    Positioned(
                      right: _AddSlotsPageState()._clampd(context.wp(1.6), 8, 10),
                      top: _AddSlotsPageState()._clampd(context.hp(0.6), 4, 8),
                      child: const Icon(Icons.check, size: 16, color: Colors.white),
                    ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _VehicleGrid extends StatelessWidget {
  final List<_Vehicle> vehicles;
  final Set<String> selected; // vehicle_ids
  final void Function(_Vehicle) onTap;

  const _VehicleGrid({
    required this.vehicles,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final targetTileW = _AddSlotsPageState()._clampd(context.wp(38), 260, 360);
      int columns = (c.maxWidth / targetTileW).floor().clamp(1, 3);
      final gap = _AddSlotsPageState()._clampd(context.wp(1.5), 8, 14);
      final totalGap = gap * (columns - 1);
      final tileW = (c.maxWidth - totalGap) / columns;

      final baseTileH = _AddSlotsPageState()._clampd(context.hp(10), 88, 130);
      final textScale = MediaQuery.of(context).textScaleFactor;
      final extraH = 6 + ((textScale - 1.0).clamp(0.0, 0.6) * 40);
      final aspect = tileW / (baseTileH + extraH);

      final padAll = _AddSlotsPageState()._clampd(context.wp(3), 12, 20);
      final iconCircle = _AddSlotsPageState()._clampd(context.wp(7), 42, 56);
      final iconSize = _AddSlotsPageState()._clampd(context.sp(2.2), 18, 22);
      final nameFs = _AddSlotsPageState()._clampd(context.sp(2), 14, 18);
      final subFs  = _AddSlotsPageState()._clampd(context.sp(1.8), 12, 15);
      final idFs   = _AddSlotsPageState()._clampd(context.sp(1.6), 11, 13);

      return GridView.builder(
        itemCount: vehicles.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: aspect,
        ),
        itemBuilder: (context, i) {
          final v = vehicles[i];
          final isSelected = selected.contains(v.id);

          final bg = isSelected ? _AddSlotsPageState.kPrimary : const Color(0xFFF8F9FA);
          final border = isSelected ? _AddSlotsPageState.kPrimary : const Color(0xFFE9ECEF);
          final fg = isSelected ? Colors.white : const Color(0xFF333333);
          final iconBg = isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFE3F2FD);

          return GestureDetector(
            onTap: () => onTap(v),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.all(padAll),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(_AddSlotsPageState()._clampd(context.sp(1.1), 8, 12)),
                border: Border.all(color: border, width: 1.5),
              ),
              child: Stack(
                children: [
                  Row(
                    children: [
                      Container(
                        width: iconCircle,
                        height: iconCircle,
                        decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                        child: Icon(Icons.directions_car, size: iconSize, color: Colors.black54),
                      ),
                      SizedBox(width: _AddSlotsPageState()._clampd(context.wp(2.4), 10, 14)),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v.carType,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: nameFs, color: fg),
                            ),
                            SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.5), 4, 8)),
                            Opacity(
                              opacity: 0.85,
                              child: Text(
                                '₹${v.charge.toStringAsFixed(0)} per session',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: subFs, color: fg),
                              ),
                            ),
                            Opacity(
                              opacity: 0.6,
                              child: Text(
                                'ID: ${v.id}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: idFs, color: fg),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isSelected)
                    Positioned(
                      right: _AddSlotsPageState()._clampd(context.wp(3), 10, 14),
                      top: _AddSlotsPageState()._clampd(context.hp(0.8), 6, 10),
                      child: const Icon(Icons.check, size: 18, color: Colors.white),
                    ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _InstructorGrid extends StatelessWidget {
  final List<_Instructor> instructors;
  final Set<String> selected; // userIds
  final void Function(_Instructor) onTap;

  const _InstructorGrid({required this.instructors, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final targetTileW = _AddSlotsPageState()._clampd(context.wp(38), 260, 360);
      int columns = (c.maxWidth / targetTileW).floor().clamp(1, 3);
      final gap = _AddSlotsPageState()._clampd(context.wp(1.5), 8, 14);
      final totalGap = gap * (columns - 1);
      final tileW = (c.maxWidth - totalGap) / columns;

      final baseTileH = _AddSlotsPageState()._clampd(context.hp(10), 88, 130);
      final textScale = MediaQuery.of(context).textScaleFactor;
      final extraH = 6 + ((textScale - 1.0).clamp(0.0, 0.6) * 36);
      final aspect = tileW / (baseTileH + extraH);

      final padAll = _AddSlotsPageState()._clampd(context.wp(3), 12, 20);
      final iconCircle = _AddSlotsPageState()._clampd(context.wp(7), 42, 56);
      final iconSize = _AddSlotsPageState()._clampd(context.sp(2.2), 18, 22);
      final nameFs = _AddSlotsPageState()._clampd(context.sp(2), 14, 18);
      final subFs  = _AddSlotsPageState()._clampd(context.sp(1.8), 12, 15);
      final badgeFs= _AddSlotsPageState()._clampd(context.sp(1.4), 10, 11);

      return GridView.builder(
        itemCount: instructors.length,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: gap,
          mainAxisSpacing: gap,
          childAspectRatio: aspect,
        ),
        itemBuilder: (context, i) {
          final ins = instructors[i];
          final isSelected = selected.contains(ins.id);

          final bg = !ins.available
              ? const Color(0xFFF5F5F5)
              : (isSelected ? _AddSlotsPageState.kPrimary : const Color(0xFFF8F9FA));
          final border = !ins.available
              ? const Color(0xFFDDDDDD)
              : (isSelected ? _AddSlotsPageState.kPrimary : const Color(0xFFE9ECEF));
          final fg = !ins.available
              ? const Color(0xFF999999)
              : (isSelected ? Colors.white : const Color(0xFF333333));
          final badge = !ins.available;

          final avatarBg = !ins.available
              ? const Color(0xFFF0F0F0)
              : (isSelected ? Colors.white.withOpacity(0.2) : const Color(0xFFE8F5E8));
          final avatarIcon = !ins.available
              ? const Color(0xFF999999)
              : (isSelected ? Colors.white : const Color(0xFF4CAF50));

          return GestureDetector(
            onTap: () => onTap(ins),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.all(padAll),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(_AddSlotsPageState()._clampd(context.sp(1.1), 8, 12)),
                border: Border.all(color: border, width: 1.5),
              ),
              child: Stack(
                children: [
                  Row(
                    children: [
                      Container(
                        width: iconCircle,
                        height: iconCircle,
                        decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
                        child: Icon(Icons.person, color: avatarIcon, size: iconSize),
                      ),
                      SizedBox(width: _AddSlotsPageState()._clampd(context.wp(2.4), 10, 14)),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              ins.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: nameFs, color: fg),
                            ),
                            SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.5), 4, 8)),
                            Opacity(
                              opacity: 0.85,
                              child: Text(
                                ins.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: subFs, color: fg),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (ins.rating != null)
                        Row(
                          children: [
                            Icon(Icons.star, size: _AddSlotsPageState()._clampd(context.sp(1.7), 12, 16), color: isSelected ? Colors.white : const Color(0xFFFFC107)),
                            SizedBox(width: _AddSlotsPageState()._clampd(context.wp(1), 4, 8)),
                            Text(ins.rating!.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
                          ],
                        ),
                    ],
                  ),
                  if (isSelected)
                    Positioned(
                      right: _AddSlotsPageState()._clampd(context.wp(3), 10, 14),
                      top: _AddSlotsPageState()._clampd(context.hp(0.8), 6, 10),
                      child: const Icon(Icons.check, size: 18, color: Colors.white),
                    ),
                  if (badge)
                    Positioned(
                      right: _AddSlotsPageState()._clampd(context.wp(2), 8, 12),
                      top: _AddSlotsPageState()._clampd(context.hp(0.6), 4, 8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: _AddSlotsPageState()._clampd(context.wp(2), 8, 12),
                          vertical: _AddSlotsPageState()._clampd(context.hp(0.4), 2, 4),
                        ),
                        decoration: BoxDecoration(color: const Color(0xFFDC3545), borderRadius: BorderRadius.circular(4)),
                        child: Text('UNAVAILABLE', style: TextStyle(color: Colors.white, fontSize: badgeFs, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    });
  }
}

class _EmptyBanner extends StatelessWidget {
  final String text;
  const _EmptyBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final pad = _AddSlotsPageState()._clampd(context.wp(3), 12, 20);
    final radius = _AddSlotsPageState()._clampd(context.sp(1.1), 8, 12);
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[200]!),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: Colors.grey, fontSize: _AddSlotsPageState()._clampd(context.sp(1.8), 12, 15))),
      ),
    );
  }
}

class _InfoBar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  final Color textColor;

  final double? padH;
  final double? padV;
  final double? iconSize;
  final double? fontSize;

  const _InfoBar({
    required this.color,
    required this.icon,
    required this.text,
    required this.textColor,
    this.padH,
    this.padV,
    this.iconSize,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final ph = padH ?? _AddSlotsPageState()._clampd(context.wp(3), 12, 20);
    final pv = padV ?? _AddSlotsPageState()._clampd(context.hp(1), 8, 14);
    final iSz = iconSize ?? _AddSlotsPageState()._clampd(context.sp(2), 16, 20);
    final fs  = fontSize ?? _AddSlotsPageState()._clampd(context.sp(1.8), 12, 15);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: ph, vertical: pv),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_AddSlotsPageState()._clampd(context.sp(1.1), 8, 12))),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: iSz),
          SizedBox(width: _AddSlotsPageState()._clampd(context.wp(2), 8, 12)),
          Flexible(child: Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w500, fontSize: fs))),
        ],
      ),
    );
  }
}

class _BookingSummary extends StatelessWidget {
  final Set<DateTime> selectedDates;
  final Set<String> selectedTimeSlots;
  final Set<String> selectedCarTypes; // using vehicle display names here
  final Set<String> selectedInstructors; // names for display
  final int totalCombinations;

  // percentage-based tuneables
  final EdgeInsets? pad;
  final double? radius;
  final double? titleFs;
  final double? labelFs;
  final double? chipFs;

  const _BookingSummary({
    required this.selectedDates,
    required this.selectedTimeSlots,
    required this.selectedCarTypes,
    required this.selectedInstructors,
    required this.totalCombinations,
    this.pad,
    this.radius,
    this.titleFs,
    this.labelFs,
    this.chipFs,
  });

  @override
  Widget build(BuildContext context) {
    final padding = pad ?? EdgeInsets.all(_AddSlotsPageState()._clampd(context.wp(3), 12, 20));
    final rad = radius ?? _AddSlotsPageState()._clampd(context.sp(1.2), 10, 14);
    final tFs = titleFs ?? _AddSlotsPageState()._clampd(context.sp(2.2), 16, 20);
    final lFs = labelFs ?? _AddSlotsPageState()._clampd(context.sp(1.8), 12, 15);
    final cFs = chipFs ?? _AddSlotsPageState()._clampd(context.sp(1.6), 11, 13);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_AddSlotsPageState.kSummaryBgStart, _AddSlotsPageState.kSummaryBgEnd]),
        border: Border.all(color: _AddSlotsPageState.kChipGreen),
        borderRadius: BorderRadius.circular(rad),
      ),
      padding: padding,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontSize: lFs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.bookmark, color: const Color(0xFF4CAF50), size: _AddSlotsPageState()._clampd(context.sp(2.2), 18, 22)),
              SizedBox(width: _AddSlotsPageState()._clampd(context.wp(2), 8, 12)),
              Text('Booking Summary', style: TextStyle(fontSize: tFs, color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
            ]),
            SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14)),

            if (selectedCarTypes.isNotEmpty) ...[
              _SummaryLabel('Vehicles:', fs: lFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.6), 4, 8)),
              _ChipWrap(values: selectedCarTypes, fs: cFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14)),
            ],

            if (selectedInstructors.isNotEmpty) ...[
              _SummaryLabel('Instructors:', fs: lFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.6), 4, 8)),
              _ChipWrap(values: selectedInstructors, fs: cFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14)),
            ],

            if (selectedDates.isNotEmpty) ...[
              _SummaryLabel('Selected Dates:', fs: lFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.6), 4, 8)),
              _ChipWrap(values: (selectedDates.toList()..sort()).map(_fmtDate), fs: cFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14)),
            ],

            if (selectedTimeSlots.isNotEmpty) ...[
              _SummaryLabel('Selected Time Slots:', fs: lFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(0.6), 4, 8)),
              _ChipWrap(values: selectedTimeSlots.map((s) => s.replaceFirst('-', ' - ')), fs: cFs),
              SizedBox(height: _AddSlotsPageState()._clampd(context.hp(1.2), 8, 14)),
            ],

            Text(
              'Total Slot Combinations: $totalCombinations',
              style: TextStyle(fontSize: tFs, color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _SummaryLabel extends StatelessWidget {
  final String text;
  final double fs;
  const _SummaryLabel(this.text, {required this.fs});

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(fontSize: fs, color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600));
  }
}

class _ChipWrap extends StatelessWidget {
  final Iterable<String> values;
  final double fs;
  const _ChipWrap({required this.values, required this.fs});

  @override
  Widget build(BuildContext context) {
    final padH = _AddSlotsPageState()._clampd(context.wp(2.2), 10, 14);
    final padV = _AddSlotsPageState()._clampd(context.hp(0.5), 4, 6);
    final radius = _AddSlotsPageState()._clampd(context.sp(1.1), 10, 14);

    final chips = values.map((v) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        margin: EdgeInsets.only(
          right: _AddSlotsPageState()._clampd(context.wp(1.6), 8, 12),
          bottom: _AddSlotsPageState()._clampd(context.hp(0.7), 6, 10),
        ),
        decoration: BoxDecoration(
          color: _AddSlotsPageState.kChipGreenBg,
          border: Border.all(color: _AddSlotsPageState.kChipGreen),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Text(v, style: TextStyle(color: const Color(0xFF2E7D32), fontSize: fs, fontWeight: FontWeight.w600)),
      );
    }).toList();

    return Wrap(children: chips);
  }
}

// ====== Models ======
class _TimeSlot {
  final String start;
  final String end;
  final bool booked;
  const _TimeSlot(this.start, this.end, this.booked);
}

class _Vehicle {
  final String id;       // Firestore doc id (vehicle_id)
  final String carType;  // display type
  final double charge;   // per session
  const _Vehicle({required this.id, required this.carType, required this.charge});
}

class _Instructor {
  final String id;        // Firestore user doc id
  final String name;      // display name
  final String subtitle;  // optional
  final double? rating;   // optional
  final bool available;
  const _Instructor({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.rating,
    required this.available,
  });
}

class _NoScrollbarBehavior extends ScrollBehavior {
  const _NoScrollbarBehavior();
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    // Hide any platform scrollbar
    return child;
  }
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    // Remove glow/stretch effects
    return child;
  }
}

// ====== Constants ======
const List<String> _monthNames = [
  'January','February','March','April','May','June',
  'July','August','September','October','November','December'
];
