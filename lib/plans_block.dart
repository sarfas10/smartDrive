// lib/plans_block.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:smart_drive/reusables/branding.dart' hide AppColors, AppText;

import 'ui_common.dart';
import 'package:smart_drive/theme/app_theme.dart';

class PlansBlock extends StatefulWidget {
  const PlansBlock({super.key});
  @override
  State<PlansBlock> createState() => _PlansBlockState();
}

/// Plan model (Study Materials & Tests removed)
class Plan {
  final String id; // slug of name
  final String name;

  /// For slot-based plans: total plan price.
  /// For Pay-Per-Use: always 0; UI shows "Pay as you go".
  final int price;

  /// Slot-based charging
  final int slots;

  /// Alternate plan type
  final bool isPayPerUse;

  /// Optional transport
  final bool extraKmSurcharge;
  final int surcharge;
  final bool freePickupRadius;
  final int freeRadius;

  /// Driving test flags per class
  final bool drivingTest8; // 8-type
  final bool drivingTestH; // H-type

  final bool active;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.slots,
    required this.isPayPerUse,
    required this.extraKmSurcharge,
    required this.surcharge,
    required this.freePickupRadius,
    required this.freeRadius,
    required this.drivingTest8,
    required this.drivingTestH,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  factory Plan.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>? ?? {});

    // Back-compat: if slots == 0 and old 'lessons' existed, treat as PPU
    final legacyFlexible = ((d['slots'] ?? 0) == 0 && (d['lessons'] != null));
    final isPPU = (d['isPayPerUse'] ?? false) as bool || legacyFlexible;

    // Driving test flags: prefer explicit fields, fall back to old single flag if present
    bool drv8 = (d['driving_test_8'] ?? null) != null ? (d['driving_test_8'] as bool) : false;
    bool drvH = (d['driving_test_h'] ?? null) != null ? (d['driving_test_h'] as bool) : false;
    if (!(d.containsKey('driving_test_8') || d.containsKey('driving_test_h'))) {
      // older versions used driving_test_included (single flag). If present, apply to both.
      final legacy = (d['driving_test_included'] ?? true) as bool;
      drv8 = legacy;
      drvH = legacy;
    }

    return Plan(
      id: doc.id,
      name: (d['name'] ?? doc.id).toString(),
      price: isPPU ? 0 : (d['price'] ?? 0) as int, // PPU force 0
      slots: (d['slots'] ?? 0) as int,
      isPayPerUse: isPPU,
      extraKmSurcharge: (d['extraKmSurcharge'] ?? false) as bool,
      surcharge: (d['surcharge'] ?? 0) as int,
      freePickupRadius: (d['freePickupRadius'] ?? false) as bool,
      freeRadius: (d['freeRadius'] ?? 0) as int,
      drivingTest8: drv8,
      drivingTestH: drvH,
      active: (d['active'] ?? true) as bool,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap({bool forCreate = false}) {
    final now = FieldValue.serverTimestamp();
    return {
      'name': name,
      'price': isPayPerUse ? 0 : price, // persist 0 for PPU
      'slots': isPayPerUse ? 0 : slots,

      // transport
      'extraKmSurcharge': extraKmSurcharge,
      'surcharge': extraKmSurcharge ? surcharge : 0,
      'freePickupRadius': freePickupRadius,
      'freeRadius': freePickupRadius ? freeRadius : 0,

      'isPayPerUse': isPayPerUse,

      // driving test flags
      'driving_test_8': drivingTest8,
      'driving_test_h': drivingTestH,

      'active': active,
      if (forCreate) 'created_at': now,
      'updated_at': now,
    };
  }
}

class _PlansBlockState extends State<PlansBlock> {
  final _currency =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  void _snack(String msg) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _runWithSpinner(Future<void> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(color: context.c.primary),
        ),
      ),
    );
    try {
      await task();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close spinner
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final double w = c.maxWidth;
        final bool isPhone = w < 720;
        final bool isTablet = w >= 720 && w < 1100;
        final EdgeInsets pad = EdgeInsets.all(isPhone ? 12 : 20);

        return Padding(
          padding: pad,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(isPhone),
              SizedBox(height: isPhone ? 12 : 20),
              Expanded(
                child: isPhone
                    ? _buildPhoneLayout()
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: isTablet ? 360 : 420,
                            child: Column(
                              children: [
                                _QuickCard(child: _buildCreatePlanCard()),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(child: _buildExistingPlansGrid()),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------- Header ----------
  Widget _buildHeader(bool isCompact) {
    return Row(
      children: [
        const Icon(Icons.payment_rounded, color: AppColors.primary, size: 24),
        const SizedBox(width: 12),
        Text(
          'Plans Management',
          style: TextStyle(
            fontSize: isCompact ? 20 : 24,
            fontWeight: FontWeight.w700,
            color: context.c.onSurface,
          ),
        ),
        const Spacer(),
        if (!isCompact)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brand.withOpacity(0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Create & Manage Slot-Based / Pay-Per-Use',
              style: TextStyle(
                color: context.c.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  // ---------- Phone layout (stacked) ----------
  Widget _buildPhoneLayout() {
    return ListView(
      children: [
        _QuickCard(child: _buildCreatePlanCard()),
        const SizedBox(height: 12),
        _QuickCard(
          child: SizedBox(
            height: 520,
            child: _buildExistingPlansGrid(),
          ),
        ),
      ],
    );
  }

  // ---------- Create Plan / Pay-Per-Use ----------
  Widget _buildCreatePlanCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(icon: Icons.design_services, title: 'Create Plan'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openSlotsPlanForm(
                  context,
                  initial: const Plan(
                    id: '',
                    name: '',
                    price: 0,
                    slots: 12,
                    isPayPerUse: false,
                    // Required-at-creation transport toggles (locked ON in UI)
                    extraKmSurcharge: true,
                    surcharge: 15,
                    freePickupRadius: true,
                    freeRadius: 5,
                    drivingTest8: true,
                    drivingTestH: true,
                    active: true,
                  ),
                  isCreate: true,
                ),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Create Plan'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary, width: 1.2),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _openPayPerUseForm(
                  context,
                  initial: const Plan(
                    id: 'pay-per-use',
                    name: 'Pay-Per-Use',
                    price: 0, // forced 0; UI shows "Pay as you go"
                    slots: 0,
                    isPayPerUse: true,
                    // Required-at-creation transport toggles (locked ON in UI)
                    extraKmSurcharge: true,
                    surcharge: 15,
                    freePickupRadius: true,
                    freeRadius: 5,
                    drivingTest8: true,
                    drivingTestH: true,
                    active: true,
                  ),
                  isCreate: true,
                ),
                icon: const Icon(Icons.flash_on, size: 18),
                label: const Text('Pay-Per-Use'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onSurfaceInverse,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------- Existing Plans Grid ----------
  Widget _buildExistingPlansGrid() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('plans')
          .orderBy('created_at', descending: true)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: context.c.primary));
        }
        if (snap.hasError) {
          return Center(child: Text('Error loading plans: ${snap.error}', style: AppText.tileSubtitle.copyWith(color: AppColors.danger)));
        }

        final docs = snap.data?.docs ?? [];
        final plans = docs.map((d) => Plan.fromDoc(d)).toList();

        if (plans.isEmpty) {
          return _EmptyState(onPrimaryAction: () {
            _openSlotsPlanForm(
              context,
              initial: const Plan(
                id: '',
                name: '',
                price: 0,
                slots: 12,
                isPayPerUse: false,
                extraKmSurcharge: true, // required at creation
                surcharge: 15,
                freePickupRadius: true, // required at creation
                freeRadius: 5,
                drivingTest8: true,
                drivingTestH: true,
                active: true,
              ),
              isCreate: true,
            );
          });
        }

        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            int cols = 1;
            if (w > 520) cols = 2;
            if (w > 900) cols = 3;
            if (w > 1280) cols = 4;

            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: 220,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: plans.length,
              itemBuilder: (_, i) => _PlanCard(
                plan: plans[i],
                currency: _currency,
                onEdit: (p) => p.isPayPerUse
                    ? _openPayPerUseForm(context, initial: p, isCreate: false)
                    : _openSlotsPlanForm(context, initial: p, isCreate: false),
                onToggleActive: (p) => _runWithSpinner(() => _toggleActive(p)),
                onDuplicate: (p) => _runWithSpinner(() => _duplicatePlan(p)),
                onDelete: (p) => _runWithSpinner(() => _deletePlan(p)),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- CRUD helpers ----------
  Future<void> _toggleActive(Plan p) async {
    await FirebaseFirestore.instance.collection('plans').doc(p.id).update({
      'active': !p.active,
      'updated_at': FieldValue.serverTimestamp(),
    });
    _snack('Plan ${!p.active ? "activated" : "deactivated"}');
  }

  Future<void> _duplicatePlan(Plan p) async {
    final newId = _safeId('${p.name} Copy');
    final newPlan = Plan(
      id: newId,
      name: '${p.name} Copy',
      price: p.isPayPerUse ? 0 : p.price,
      slots: p.slots,
      isPayPerUse: p.isPayPerUse,
      extraKmSurcharge: p.extraKmSurcharge,
      surcharge: p.surcharge,
      freePickupRadius: p.freePickupRadius,
      freeRadius: p.freeRadius,
      drivingTest8: p.drivingTest8,
      drivingTestH: p.drivingTestH,
      active: p.active,
    );
    await FirebaseFirestore.instance
        .collection('plans')
        .doc(newId)
        .set(newPlan.toMap(forCreate: true));
    _snack('Duplicated "${p.name}"');
  }

  Future<void> _deletePlan(Plan p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Plan'),
        content: Text('Delete “${p.name}”? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.onSurfaceInverse),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await FirebaseFirestore.instance.collection('plans').doc(p.id).delete();
    _snack('Deleted "${p.name}"');
  }

  // ---------- Forms ----------
  Future<void> _openSlotsPlanForm(
    BuildContext context, {
    required Plan initial,
    required bool isCreate,
  }) async {
    final formKey = GlobalKey<FormState>();

    final nameCtrl = TextEditingController(text: initial.name);
    final priceCtrl = TextEditingController(text: initial.price == 0 ? '' : initial.price.toString());
    final slotsCtrl = TextEditingController(text: initial.slots.toString());
    final surchargeCtrl = TextEditingController(text: initial.surcharge.toString());
    final radiusCtrl = TextEditingController(text: initial.freeRadius.toString());

    // Transport rules (required at creation → locked ON)
    bool extraKm = isCreate ? true : initial.extraKmSurcharge;
    bool freePickup = isCreate ? true : initial.freePickupRadius;

    // NEW: driving test flags per class (default true for creation)
    bool drivingTest8 = isCreate ? true : initial.drivingTest8;
    bool drivingTestH = isCreate ? true : initial.drivingTestH;

    // Editable always
    bool active = initial.active;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isCreate ? 'Create Slot-Based Plan' : 'Edit Slot-Based Plan',
                          style: AppText.sectionTitle.copyWith(fontSize: 18)),
                      const SizedBox(height: 16),

                      _LabeledField(
                        label: 'Plan Name',
                        child: TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(hintText: 'e.g., Starter, Pro'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a plan name' : null,
                        ),
                      ),
                      const SizedBox(height: 12),

                      _LabeledField(
                        label: 'Plan Price (₹)',
                        child: TextFormField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(hintText: 'e.g., 1999'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter a price';
                            final n = int.tryParse(v);
                            if (n == null || n <= 0) return 'Enter a valid positive amount';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      _LabeledField(
                        label: 'Number of Slots',
                        child: TextFormField(
                          controller: slotsCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(hintText: 'e.g., 12'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            if (n == null || n <= 0) return 'Enter a valid positive number';
                            return null;
                          },
                        ),
                      ),

                      const Divider(height: 24),
                      Text('Optional Transport Rules', style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),

                      // Extra KM Surcharge — required at creation (locked ON)
                      CheckboxListTile(
                        value: extraKm,
                        onChanged: isCreate ? null : (vv) => setState(() => extraKm = vv ?? false),
                        title: const Text('Extra KM Surcharge'),
                        subtitle: const Text('Charge extra for kilometers beyond limit'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (extraKm)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LabeledField(
                            label: 'Surcharge per KM (₹)',
                            child: TextFormField(
                              controller: surchargeCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(hintText: 'e.g., 15'),
                              validator: (v) {
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n <= 0) {
                                  return 'Enter a positive surcharge';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),

                      // Free Pickup Radius — required at creation (locked ON)
                      CheckboxListTile(
                        value: freePickup,
                        onChanged: isCreate ? null : (vv) => setState(() => freePickup = vv ?? false),
                        title: const Text('Free Pickup Radius'),
                        subtitle: const Text('Offer free pickup within specified radius'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (freePickup)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LabeledField(
                            label: 'Free Radius (KM)',
                            child: TextFormField(
                              controller: radiusCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(hintText: 'e.g., 5'),
                              validator: (v) {
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n <= 0) {
                                  return 'Enter a positive radius';
                                }
                                return null;
                              },
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),

                      // NEW: Driving Test selection per class
                      Text('Driving Test included for classes', style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        value: drivingTest8,
                        onChanged: (vv) => setState(() => drivingTest8 = vv ?? false),
                        title: const Text('8 type'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: drivingTestH,
                        onChanged: (vv) => setState(() => drivingTestH = vv ?? false),
                        title: const Text('H type'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),

                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        value: active,
                        onChanged: (vv) => setState(() => active = vv),
                        title: const Text('Plan is Active'),
                        contentPadding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          const Spacer(),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onSurfaceInverse,
                            ),
                            onPressed: () async {
                              // Enforce required transport toggles at creation
                              if (isCreate && (!extraKm || !freePickup)) {
                                _snack('Extra KM Surcharge and Free Pickup Radius are required.');
                                return;
                              }
                              if (!formKey.currentState!.validate()) return;

                              final name = nameCtrl.text.trim();
                              final id = _safeId(name);
                              final price = int.parse(priceCtrl.text.trim());
                              final slots = int.parse(slotsCtrl.text.trim());
                              final surcharge = int.parse(surchargeCtrl.text.trim().isEmpty ? '0' : surchargeCtrl.text.trim());
                              final freeRadius = int.parse(radiusCtrl.text.trim().isEmpty ? '0' : radiusCtrl.text.trim());

                              final data = Plan(
                                id: id,
                                name: name,
                                price: price,
                                slots: slots,
                                isPayPerUse: false,
                                extraKmSurcharge: true, // enforced at creation
                                surcharge: surcharge,
                                freePickupRadius: true, // enforced at creation
                                freeRadius: freeRadius,
                                drivingTest8: drivingTest8,
                                drivingTestH: drivingTestH,
                                active: active,
                              );

                              await _runWithSpinner(() async {
                                if (isCreate) {
                                  await FirebaseFirestore.instance
                                      .collection('plans')
                                      .doc(id)
                                      .set(data.toMap(forCreate: true));
                                  _snack('Plan “$name” created');
                                } else {
                                  if (id != initial.id) {
                                    final batch = FirebaseFirestore.instance.batch();
                                    final newRef = FirebaseFirestore.instance.collection('plans').doc(id);
                                    final oldRef = FirebaseFirestore.instance.collection('plans').doc(initial.id);
                                    batch.set(newRef, data.toMap(forCreate: true));
                                    batch.delete(oldRef);
                                    await batch.commit();
                                  } else {
                                    await FirebaseFirestore.instance
                                        .collection('plans')
                                        .doc(id)
                                        .update(data.toMap());
                                  }
                                  _snack('Plan “$name” updated');
                                }
                              });

                              if (mounted) Navigator.pop(context);
                            },
                            child: Text(isCreate ? 'Create Plan' : 'Save Changes'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    priceCtrl.dispose();
    slotsCtrl.dispose();
    surchargeCtrl.dispose();
    radiusCtrl.dispose();
  }

  Future<void> _openPayPerUseForm(
    BuildContext context, {
    required Plan initial,
    required bool isCreate,
  }) async {
    final formKey = GlobalKey<FormState>();

    final nameCtrl = TextEditingController(text: initial.name);
    final surchargeCtrl = TextEditingController(text: initial.surcharge.toString());
    final radiusCtrl = TextEditingController(text: initial.freeRadius.toString());

    // Required-at-creation toggles
    bool extraKm = isCreate ? true : initial.extraKmSurcharge;
    bool freePickup = isCreate ? true : initial.freePickupRadius;
    bool active = initial.active;

    // NEW: driving test flags per class (default true for creation)
    bool drivingTest8 = isCreate ? true : initial.drivingTest8;
    bool drivingTestH = isCreate ? true : initial.drivingTestH;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isCreate ? 'Create Pay-Per-Use' : 'Edit Pay-Per-Use',
                          style: AppText.sectionTitle.copyWith(fontSize: 18)),
                      const SizedBox(height: 16),

                      _LabeledField(
                        label: 'Plan Name',
                        child: TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(hintText: 'e.g., Pay-Per-Use'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a plan name' : null,
                        ),
                      ),
                      const SizedBox(height: 12),

                      const Divider(height: 24),
                      Text('Transport Rules', style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),

                      // Extra KM Surcharge — required at creation (locked ON)
                      CheckboxListTile(
                        value: extraKm,
                        onChanged: isCreate ? null : (vv) => setState(() => extraKm = vv ?? false),
                        title: const Text('Extra KM Surcharge'),
                        subtitle: const Text('Charge extra for kilometers beyond limit'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (extraKm)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LabeledField(
                            label: 'Surcharge per KM (₹)',
                            child: TextFormField(
                              controller: surchargeCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(hintText: 'e.g., 15'),
                              validator: (v) {
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n <= 0) return 'Enter a positive surcharge';
                                return null;
                              },
                            ),
                          ),
                        ),

                      // Free Pickup Radius — required at creation (locked ON)
                      CheckboxListTile(
                        value: freePickup,
                        onChanged: isCreate ? null : (vv) => setState(() => freePickup = vv ?? false),
                        title: const Text('Free Pickup Radius'),
                        subtitle: const Text('Offer free pickup within specified radius'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      if (freePickup)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _LabeledField(
                            label: 'Free Radius (KM)',
                            child: TextFormField(
                              controller: radiusCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: const InputDecoration(hintText: 'e.g., 5'),
                              validator: (v) {
                                final n = int.tryParse((v ?? '').trim());
                                if (n == null || n <= 0) return 'Enter a positive radius';
                                return null;
                              },
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),

                      // NEW: Driving Test selection per class
                      Text('Driving Test included for classes', style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      CheckboxListTile(
                        value: drivingTest8,
                        onChanged: (vv) => setState(() => drivingTest8 = vv ?? false),
                        title: const Text('8 type'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        value: drivingTestH,
                        onChanged: (vv) => setState(() => drivingTestH = vv ?? false),
                        title: const Text('H type'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),

                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        value: active,
                        onChanged: (vv) => setState(() => active = vv),
                        title: const Text('Plan is Active'),
                        contentPadding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                          const Spacer(),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onSurfaceInverse,
                            ),
                            onPressed: () async {
                              // Enforce required transport toggles at creation
                              if (isCreate && (!extraKm || !freePickup)) {
                                _snack('Extra KM Surcharge and Free Pickup Radius are required.');
                                return;
                              }
                              if (!formKey.currentState!.validate()) return;

                              final name = nameCtrl.text.trim();
                              final id = _safeId(name);
                              final surcharge = int.parse(surchargeCtrl.text.trim());
                              final freeRadius = int.parse(radiusCtrl.text.trim());

                              final data = Plan(
                                id: id,
                                name: name,
                                price: 0, // Pay as you go
                                slots: 0,
                                isPayPerUse: true,
                                extraKmSurcharge: true, // enforced at creation
                                surcharge: surcharge,
                                freePickupRadius: true, // enforced at creation
                                freeRadius: freeRadius,
                                drivingTest8: drivingTest8,
                                drivingTestH: drivingTestH,
                                active: active,
                              );

                              await _runWithSpinner(() async {
                                if (isCreate) {
                                  await FirebaseFirestore.instance
                                      .collection('plans')
                                      .doc(id)
                                      .set(data.toMap(forCreate: true));
                                  _snack('Pay-Per-Use "$name" created');
                                } else {
                                  if (id != initial.id) {
                                    final batch = FirebaseFirestore.instance.batch();
                                    final newRef = FirebaseFirestore.instance.collection('plans').doc(id);
                                    final oldRef = FirebaseFirestore.instance.collection('plans').doc(initial.id);
                                    batch.set(newRef, data.toMap(forCreate: true));
                                    batch.delete(oldRef);
                                    await batch.commit();
                                  } else {
                                    await FirebaseFirestore.instance
                                        .collection('plans')
                                        .doc(id)
                                        .update(data.toMap());
                                  }
                                  _snack('Pay-Per-Use "$name" updated');
                                }
                              });

                              if (mounted) Navigator.pop(context);
                            },
                            child: Text(isCreate ? 'Create' : 'Save Changes'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    surchargeCtrl.dispose();
    radiusCtrl.dispose();
  }

  String _safeId(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}

// ---------- UI bits ----------

class _QuickCard extends StatelessWidget {
  final Widget child;
  const _QuickCard({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionTitle({required this.icon, required this.title});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppText.sectionTitle.copyWith(color: context.c.onSurface),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final NumberFormat currency;
  final void Function(Plan) onEdit;
  final void Function(Plan) onToggleActive;
  final void Function(Plan) onDuplicate;
  final void Function(Plan) onDelete;

  const _PlanCard({
    required this.plan,
    required this.currency,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final badge = plan.isPayPerUse
        ? _Badge(text: 'PAY-PER-USE', color: AppColors.brand)
        : (plan.active
            ? _Badge(text: 'ACTIVE', color: AppColors.success)
            : _Badge(text: 'INACTIVE', color: AppColors.warning));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.tileTitle.copyWith(color: context.c.onSurface),
                ),
              ),
              badge,
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'toggle':
                      onToggleActive(plan);
                      break;
                    case 'dup':
                      onDuplicate(plan);
                      break;
                    case 'del':
                      onDelete(plan);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: _MenuRow(
                      icon: plan.active ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      text: plan.active ? 'Deactivate' : 'Activate',
                    ),
                  ),
                  PopupMenuItem(value: 'dup', child: _MenuRow(icon: Icons.copy, text: 'Duplicate')),
                  PopupMenuItem(
                    value: 'del',
                    child: _MenuRow(icon: Icons.delete, text: 'Delete', color: AppColors.danger),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            plan.isPayPerUse ? 'Pay as you go' : currency.format(plan.price),
            style: AppText.tileTitle.copyWith(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              if (!plan.isPayPerUse) _Feature(icon: Icons.event_available, label: '${plan.slots} slots'),
              if (plan.isPayPerUse) const _Feature(icon: Icons.flash_on, label: 'Pay per session'),
              if (plan.extraKmSurcharge)
                _Feature(icon: Icons.local_gas_station, label: '₹${plan.surcharge}/km extra'),
              if (plan.freePickupRadius)
                _Feature(icon: Icons.location_on, label: '${plan.freeRadius} km pickup'),

              // NEW: driving test included features per class
              if (plan.drivingTest8) _Feature(icon: Icons.verified_user, label: '8-type test included'),
              if (plan.drivingTestH) _Feature(icon: Icons.verified_user, label: 'H-type test included'),
            ],
          ),
          const Spacer(),
          // Inline action icons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Edit',
                icon: const Icon(Icons.edit, color: AppColors.primary),
                onPressed: () => onEdit(plan),
              ),
              IconButton(
                tooltip: 'Delete',
                icon: Icon(Icons.delete, color: AppColors.danger),
                onPressed: () => onDelete(plan),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, this.color = AppColors.primary});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(text, style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceInverse, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _MenuRow({required this.icon, required this.text, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.c.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: c)),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Feature({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.onSurfaceFaint),
        const SizedBox(width: 4),
        Text(label, style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint)),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabeledField({required this.label, required this.child});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600, color: context.c.onSurface)),
      const SizedBox(height: 6),
      InputDecorator(
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          fillColor: AppColors.surface,
        ),
        child: child,
      ),
    ]);
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onPrimaryAction;
  const _EmptyState({required this.onPrimaryAction});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: AppColors.onSurfaceFaint),
            const SizedBox(height: 12),
            Text('No plans yet',
                style: AppText.tileTitle.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.slate)),
            const SizedBox(height: 4),
            Text(
              'Create your first plan: Slot-based (priced once) or Pay-Per-Use (Pay as you go).',
              textAlign: TextAlign.center,
              style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onPrimaryAction,
              icon: const Icon(Icons.add),
              label: const Text('Create Plan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onSurfaceInverse,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
