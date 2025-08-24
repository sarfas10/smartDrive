// lib/plans_block.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:smart_drive/reusables/branding.dart';

class PlansBlock extends StatefulWidget {
  const PlansBlock({super.key});
  @override
  State<PlansBlock> createState() => _PlansBlockState();
}

/// Lightweight Plan model
class Plan {
  final String id; // we use name as id by default; can be a slug
  final String name;
  final int price; // monthly price OR per-lesson price for flexible plans
  final int slots;
  final int lessons;
  final bool extraKmSurcharge;
  final int surcharge;
  final bool freePickupRadius;
  final int freeRadius;
  final bool active;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  bool get isFlexible => slots == 0 && lessons == 0;
  String get priceSuffix => isFlexible ? ' per lesson' : ' per month';

  Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.slots,
    required this.lessons,
    required this.extraKmSurcharge,
    required this.surcharge,
    required this.freePickupRadius,
    required this.freeRadius,
    required this.active,
    this.createdAt,
    this.updatedAt,
  });

  factory Plan.fromDoc(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>? ?? {});
    return Plan(
      id: doc.id,
      name: (d['name'] ?? doc.id).toString(),
      price: (d['price'] ?? 0) as int,
      slots: (d['slots'] ?? 0) as int,
      lessons: (d['lessons'] ?? 0) as int,
      extraKmSurcharge: (d['extraKmSurcharge'] ?? false) as bool,
      surcharge: (d['surcharge'] ?? 0) as int,
      freePickupRadius: (d['freePickupRadius'] ?? false) as bool,
      freeRadius: (d['freeRadius'] ?? 0) as int,
      active: (d['active'] ?? true) as bool,
      createdAt: d['created_at'] as Timestamp?,
      updatedAt: d['updated_at'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap({bool forCreate = false}) {
    final now = FieldValue.serverTimestamp();
    return {
      'name': name,
      'price': price,
      'slots': slots,
      'lessons': lessons,
      'extraKmSurcharge': extraKmSurcharge,
      'surcharge': extraKmSurcharge ? surcharge : 0,
      'freePickupRadius': freePickupRadius,
      'freeRadius': freePickupRadius ? freeRadius : 0,
      'active': active,
      if (forCreate) 'created_at': now,
      'updated_at': now,
    };
  }
}

class _PlansBlockState extends State<PlansBlock> {
  final _currency = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

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
                            width: isTablet ? 360 : 380,
                            child: Column(
                              children: [
                                _QuickCard(child: _buildQuickActions()),
                                const SizedBox(height: 16),
                                _QuickCard(child: _buildCreateCustomPlan()),
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
            color: const Color(0xFF111827),
          ),
        ),
        const Spacer(),
        if (!isCompact)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x1A4C008A),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Create & Manage Subscription Plans',
              style: TextStyle(
                color: AppColors.primary,
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
        _QuickCard(child: _buildQuickActions()),
        const SizedBox(height: 12),
        _QuickCard(child: _buildCreateCustomPlan()),
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

  // ---------- Quick Actions ----------
  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.flash_on, title: 'Quick Actions'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _openPlanForm(
              context,
              initial: Plan(
                id: 'Pay-Per-Use',
                name: 'Pay-Per-Use',
                price: 500,
                slots: 0,
                lessons: 0,
                extraKmSurcharge: true,
                surcharge: 15,
                freePickupRadius: true,
                freeRadius: 5,
                active: true,
              ),
              isCreate: true,
              forceFlexible: true,
            ),
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Create Pay-Per-Use Plan'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _InfoTile(
          title: 'Pay-Per-Use Details',
          lines: const [
            'No monthly commitment',
            'Pay only for lessons taken',
            'Perfect for occasional learners',
          ],
        ),
      ],
    );
  }

  // ---------- Create Custom ----------
  Widget _buildCreateCustomPlan() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(icon: Icons.design_services, title: 'Create Custom Plan'),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openPlanForm(
              context,
              initial: Plan(
                id: '',
                name: '',
                price: 0,
                slots: 12,
                lessons: 12,
                extraKmSurcharge: false,
                surcharge: 0,
                freePickupRadius: false,
                freeRadius: 0,
                active: true,
              ),
              isCreate: true,
              forceFlexible: false,
            ),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Create Custom Plan'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.2),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
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
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error loading plans: ${snap.error}'));
        }

        final docs = snap.data?.docs ?? [];
        final plans = docs.map((d) => Plan.fromDoc(d)).toList();

        if (plans.isEmpty) {
          return _EmptyState(onPrimaryAction: () {
            _openPlanForm(
              context,
              initial: Plan(
                id: '',
                name: '',
                price: 0,
                slots: 12,
                lessons: 12,
                extraKmSurcharge: false,
                surcharge: 0,
                freePickupRadius: false,
                freeRadius: 0,
                active: true,
              ),
              isCreate: true,
              forceFlexible: false,
            );
          });
        }

        return LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            // Responsive columns: 1 (<=520), 2 (<=900), 3 (<=1280), 4 (>)
            int cols = 1;
            if (w > 520) cols = 2;
            if (w > 900) cols = 3;
            if (w > 1280) cols = 4;

            return GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                mainAxisExtent: 180,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: plans.length,
              itemBuilder: (_, i) => _PlanCard(
                plan: plans[i],
                currency: _currency,
                onEdit: (p) => _openPlanForm(context, initial: p, isCreate: false),
                onToggleActive: (p) => _toggleActive(p),
                onDuplicate: (p) => _duplicatePlan(p),
                onDelete: (p) => _deletePlan(p),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- CRUD helpers ----------
  Future<void> _toggleActive(Plan p) async {
    try {
      await FirebaseFirestore.instance.collection('plans').doc(p.id).update({
        'active': !p.active,
        'updated_at': FieldValue.serverTimestamp(),
      });
      _snack('Plan ${!p.active ? "activated" : "deactivated"}');
    } catch (e) {
      _snack('Failed to update status: $e');
    }
  }

  Future<void> _duplicatePlan(Plan p) async {
    try {
      final newId = _safeId('${p.name} Copy');
      final newPlan = Plan(
        id: newId,
        name: '${p.name} Copy',
        price: p.price,
        slots: p.slots,
        lessons: p.lessons,
        extraKmSurcharge: p.extraKmSurcharge,
        surcharge: p.surcharge,
        freePickupRadius: p.freePickupRadius,
        freeRadius: p.freeRadius,
        active: p.active,
      );
      await FirebaseFirestore.instance.collection('plans').doc(newId).set(newPlan.toMap(forCreate: true));
      _snack('Duplicated "${p.name}"');
    } catch (e) {
      _snack('Failed to duplicate: $e');
    }
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await FirebaseFirestore.instance.collection('plans').doc(p.id).delete();
      _snack('Deleted "${p.name}"');
    } catch (e) {
      _snack('Error deleting: $e');
    }
  }

  // ---------- Form (Create / Edit) ----------
  Future<void> _openPlanForm(
    BuildContext context, {
    required Plan initial,
    required bool isCreate,
    bool forceFlexible = false,
  }) async {
    final formKey = GlobalKey<FormState>();

    final nameCtrl = TextEditingController(text: initial.name);
    final priceCtrl = TextEditingController(text: initial.price == 0 ? '' : initial.price.toString());
    final slotsCtrl = TextEditingController(text: initial.slots.toString());
    final lessonsCtrl = TextEditingController(text: initial.lessons.toString());
    final surchargeCtrl = TextEditingController(text: initial.surcharge.toString());
    final radiusCtrl = TextEditingController(text: initial.freeRadius.toString());

    bool extraKm = initial.extraKmSurcharge;
    bool freePickup = initial.freePickupRadius;
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
                      Text(
                        isCreate
                            ? (forceFlexible ? 'Create Pay-Per-Use Plan' : 'Create Custom Plan')
                            : 'Edit Plan',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 16),

                      // Name
                      _LabeledField(
                        label: 'Plan Name',
                        child: TextFormField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(hintText: 'e.g., Starter, Pro, Pay-Per-Use'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a plan name' : null,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Price
                      _LabeledField(
                        label: forceFlexible ? 'Price per Lesson (₹)' : 'Monthly Price (₹)',
                        child: TextFormField(
                          controller: priceCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(hintText: 'e.g., 799'),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Enter a price';
                            final n = int.tryParse(v);
                            if (n == null || n < 0) return 'Enter a valid number';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Slots & Lessons (hidden for flexible if you want)
                      Opacity(
                        opacity: forceFlexible ? 0.6 : 1.0,
                        child: IgnorePointer(
                          ignoring: forceFlexible,
                          child: Row(
                            children: [
                              Expanded(
                                child: _LabeledField(
                                  label: 'Number of Slots',
                                  child: TextFormField(
                                    controller: slotsCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: const InputDecoration(hintText: 'e.g., 12'),
                                    validator: (v) {
                                      final n = int.tryParse(v ?? '');
                                      if (n == null || n < 0) return 'Enter a valid number';
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _LabeledField(
                                  label: 'Number of Lessons',
                                  child: TextFormField(
                                    controller: lessonsCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: const InputDecoration(hintText: 'e.g., 12'),
                                    validator: (v) {
                                      final n = int.tryParse(v ?? '');
                                      if (n == null || n < 0) return 'Enter a valid number';
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      const Divider(height: 24),
                      const Text('Additional Features', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),

                      CheckboxListTile(
                        value: extraKm,
                        onChanged: (v) => setState(() => extraKm = v ?? false),
                        title: const Text('Extra KM Surcharge'),
                        subtitle: const Text('Charge extra for kilometers beyond limit'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: extraKm
                            ? Padding(
                                key: const ValueKey('surcharge'),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LabeledField(
                                  label: 'Surcharge per KM (₹)',
                                  child: TextFormField(
                                    controller: surchargeCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: const InputDecoration(hintText: 'e.g., 15'),
                                    validator: (v) {
                                      final n = int.tryParse(v ?? '');
                                      if (!extraKm) return null;
                                      if (n == null || n < 0) return 'Enter a valid number';
                                      return null;
                                    },
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      CheckboxListTile(
                        value: freePickup,
                        onChanged: (v) => setState(() => freePickup = v ?? false),
                        title: const Text('Free Pickup Radius'),
                        subtitle: const Text('Offer free pickup within specified radius'),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: freePickup
                            ? Padding(
                                key: const ValueKey('radius'),
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _LabeledField(
                                  label: 'Free Radius (KM)',
                                  child: TextFormField(
                                    controller: radiusCtrl,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                    decoration: const InputDecoration(hintText: 'e.g., 5'),
                                    validator: (v) {
                                      final n = int.tryParse(v ?? '');
                                      if (!freePickup) return null;
                                      if (n == null || n < 0) return 'Enter a valid number';
                                      return null;
                                    },
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        value: active,
                        onChanged: (v) => setState(() => active = v),
                        title: const Text('Plan is Active'),
                        contentPadding: EdgeInsets.zero,
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          const Spacer(),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;

                              final name = nameCtrl.text.trim();
                              final id = _safeId(name);
                              final price = int.parse(priceCtrl.text.trim());
                              final slots = forceFlexible ? 0 : int.parse(slotsCtrl.text.trim());
                              final lessons = forceFlexible ? 0 : int.parse(lessonsCtrl.text.trim());
                              final surcharge = extraKm ? int.parse(surchargeCtrl.text.trim()) : 0;
                              final freeRadius = freePickup ? int.parse(radiusCtrl.text.trim()) : 0;

                              final data = Plan(
                                id: id,
                                name: name,
                                price: price,
                                slots: slots,
                                lessons: lessons,
                                extraKmSurcharge: extraKm,
                                surcharge: surcharge,
                                freePickupRadius: freePickup,
                                freeRadius: freeRadius,
                                active: active,
                              );

                              try {
                                if (isCreate) {
                                  await FirebaseFirestore.instance.collection('plans').doc(id).set(data.toMap(forCreate: true));
                                  _snack('Plan “$name” created');
                                } else {
                                  // Update & handle rename (id change)
                                  if (id != initial.id) {
                                    final batch = FirebaseFirestore.instance.batch();
                                    final newRef = FirebaseFirestore.instance.collection('plans').doc(id);
                                    final oldRef = FirebaseFirestore.instance.collection('plans').doc(initial.id);
                                    batch.set(newRef, data.toMap(forCreate: true));
                                    batch.delete(oldRef);
                                    await batch.commit();
                                  } else {
                                    await FirebaseFirestore.instance.collection('plans').doc(id).update(data.toMap());
                                  }
                                  _snack('Plan “$name” updated');
                                }
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                _snack('Error saving plan: $e');
                              }
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
    lessonsCtrl.dispose();
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4))],
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
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String title;
  final List<String> lines;
  const _InfoTile({required this.title, required this.lines});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0F2FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF0C4A6E))),
          const SizedBox(height: 6),
          ...lines.map(
            (t) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('• $t', style: const TextStyle(fontSize: 12, color: Color(0xFF0369A1))),
            ),
          ),
        ],
      ),
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
    final badge = plan.isFlexible
        ? const _Badge(text: 'FLEXIBLE')
        : (plan.active ? const _Badge(text: 'ACTIVE', color: Color(0xFF10B981)) : const _Badge(text: 'INACTIVE', color: Color(0xFFF59E0B)));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: plan.isFlexible ? AppColors.primary.withOpacity(0.25) : const Color(0x11000000),
          width: plan.isFlexible ? 2 : 1,
        ),
        boxShadow: const [BoxShadow(color: Color(0x07000000), blurRadius: 10, offset: Offset(0, 4))],
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
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                ),
              ),
              badge,
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'edit':
                      onEdit(plan);
                      break;
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
                  const PopupMenuItem(value: 'edit', child: _MenuRow(icon: Icons.edit, text: 'Edit')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: _MenuRow(
                      icon: plan.active ? Icons.pause_circle_filled : Icons.play_circle_fill,
                      text: plan.active ? 'Deactivate' : 'Activate',
                    ),
                  ),
                  const PopupMenuItem(value: 'dup', child: _MenuRow(icon: Icons.copy, text: 'Duplicate')),
                  const PopupMenuItem(
                    value: 'del',
                    child: _MenuRow(icon: Icons.delete, text: 'Delete', color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${currency.format(plan.price)}${plan.priceSuffix}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              if (!plan.isFlexible) ...[
                _Feature(icon: Icons.event_available, label: '${plan.slots} slots'),
                _Feature(icon: Icons.school, label: '${plan.lessons} lessons'),
              ] else
                const _Feature(icon: Icons.flash_on, label: 'Pay per lesson'),
              if (plan.extraKmSurcharge) _Feature(icon: Icons.local_gas_station, label: '₹${plan.surcharge}/km extra'),
              if (plan.freePickupRadius) _Feature(icon: Icons.location_on, label: '${plan.freeRadius} km pickup'),
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
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
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
    final c = color ?? const Color(0xFF111827);
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
        Icon(icon, size: 16, color: const Color(0xFF6B7280)),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
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
      Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            const Icon(Icons.inbox, size: 64, color: Color(0xFF9CA3AF)),
            const SizedBox(height: 12),
            const Text('No plans yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF374151))),
            const SizedBox(height: 4),
            const Text(
              'Create your first plan to get started. You can add a monthly plan or a pay-per-use plan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: onPrimaryAction,
              icon: const Icon(Icons.add),
              label: const Text('Create Plan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
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
