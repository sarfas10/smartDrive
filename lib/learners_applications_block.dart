// lib/admin/learners_applications_block.dart
// Responsive / improved layout for all screens
// Status & action moved below email on small screens and aligned horizontally (side-by-side) on larger screens.
import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smart_drive/theme/app_theme.dart';

// External student details page (navigated to when tapping a card)
import 'student_details.dart' as details;

const _kMinMobile = 600.0; // below this → mobile list

/// Admin panel for learner applications.
/// Collection: `learner_applications`.
class LearnersApplicationsAdminBlock extends StatefulWidget {
  const LearnersApplicationsAdminBlock({super.key});

  @override
  State<LearnersApplicationsAdminBlock> createState() =>
      _LearnersApplicationsAdminBlockState();
}

class _LearnersApplicationsAdminBlockState
    extends State<LearnersApplicationsAdminBlock> {
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChangedImmediate);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.removeListener(_onSearchChangedImmediate);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChangedImmediate() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _search = _searchCtrl.text.trim().toLowerCase());
    });
  }

  Query<Map<String, dynamic>> _baseQuery() {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('learner_applications')
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snapshot, _) => snapshot.data() ?? {},
          toFirestore: (data, _) => data,
        );
    q = q.orderBy('created_at', descending: true);
    return q;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _HeaderBar(controller: _searchCtrl),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _baseQuery().snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: _InfoCard(
                        icon: Icons.error_outline,
                        iconColor: AppColors.danger,
                        title: 'Failed to load applications',
                        subtitle: snap.error.toString(),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = snap.data!.docs;
                  final filtered = docs.where((d) {
                    if (_search.isEmpty) return true;
                    final m = d.data();
                    final hay = [
                      m['name'],
                      m['email'],
                      m['phone'],
                      m['status'],
                      m['userId'],
                      m['type'], // include type in search
                    ].where((x) => x != null).join(' ').toLowerCase();
                    return hay.contains(_search);
                  }).toList();

                  if (filtered.isEmpty) {
                    return _EmptyState(
                      title: 'No applications found',
                      subtitle: 'Try a different search term.',
                      onClear: () {
                        _searchCtrl.clear();
                        setState(() {
                          _search = '';
                        });
                      },
                    );
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${filtered.length} of ${docs.length} applications',
                            style: const TextStyle(
                                color: AppColors.onSurfaceMuted, fontSize: 13),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ApplicationsListLarge(docs: filtered),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ---------------- Vertical list (row-by-row) used for all widths ----------------

class _ApplicationsListLarge extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  const _ApplicationsListLarge({required this.docs});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: docs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, i) {
        final doc = docs[i];
        final m = doc.data();
        final name = (m['name'] ?? '-').toString();
        final email = (m['email'] ?? '-').toString();
        final status = (m['status'] ?? 'pending').toString();
        final type = (m['type'] ?? 'application').toString(); // NEW: read type
        final docId = doc.id;
        final userId = (m['userId'] ?? m['user_id'] ?? '-').toString();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          color: AppColors.surface,
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const details.StudentDetailsPage(),
                  settings: RouteSettings(arguments: {'uid': userId}),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: LayoutBuilder(builder: (context, constraints) {
                // Adapt layout based on available width.
                final available = constraints.maxWidth;
                final isMobile = available < _kMinMobile;
                final isNarrow = available < 820;
                // For very small widths, slightly reduce badge paddings via passing a compact flag.

                // Left area: Name + Email
                final leftCol = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Primary: name (full width)
                    Text(name,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    // Secondary: email (full width)
                    Text(email,
                        style: const TextStyle(
                            color: AppColors.onSurfaceMuted, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                );

                // Right area: type, status and action aligned horizontally (or wrapped on mobile)
                final rightWidgets = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // type badge (leftmost within the right box)
                    _TypeChip(type: type),
                    const SizedBox(width: 8),
                    // status badge (left within the right box)
                    _StatusChip(status: status),
                    const SizedBox(width: 10),
                    // action icon (rightmost)
                    _ActionIconCompact(docId: docId),
                  ],
                );

                if (isMobile) {
                  // Mobile: stack name/email, then row with badges + action that can overflow to next line.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leftCol,
                      const SizedBox(height: 10),
                      // allow wrapping: use Wrap so badges will break to next line if needed
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _TypeChip(type: type),
                                  _StatusChip(status: status),
                                ],
                              ),
                            ),
                          ),
                          // action on the far right
                          _ActionIconCompact(docId: docId),
                        ],
                      ),
                    ],
                  );
                } else {
                  // Tablet / Desktop: keep single-line with left auto and right hugging
                  return Row(
                    children: [
                      // Left: name+email
                      Expanded(child: leftCol),
                      // Right: badges + action; allow this box to take only the space it needs but constrain
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          // dynamic width to avoid overflow but allow badges to show
                          maxWidth: math.max(180, available * 0.4),
                        ),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: rightWidgets,
                        ),
                      ),
                    ],
                  );
                }
              }),
            ),
          ),
        );
      },
    );
  }
}

// Compact action UI (icon) used in fixed-right column
class _ActionIconCompact extends StatelessWidget {
  final String docId;
  const _ActionIconCompact({required this.docId});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (val) {
        if (val == 'confirm') {
          _showChangeDialog(context, docId, 'confirmed');
        } else if (val == 'reject') {
          _showChangeDialog(context, docId, 'rejected');
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
            value: 'confirm',
            child: Row(children: [
              Icon(Icons.check_circle, color: AppColors.success),
              const SizedBox(width: 8),
              const Text('Confirm')
            ])),
        PopupMenuItem(
            value: 'reject',
            child: Row(children: [
              Icon(Icons.cancel, color: AppColors.danger),
              const SizedBox(width: 8),
              const Text('Reject')
            ])),
      ],
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.divider)),
        child: const Icon(Icons.more_vert, size: 18, color: AppColors.onSurfaceMuted),
      ),
    );
  }

  // shared dialog used by the menu to gather an optional note and apply status change
  void _showChangeDialog(BuildContext context, String docId, String toStatus) {
    final noteCtrl = TextEditingController();
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title:
                Text('${toStatus[0].toUpperCase()}${toStatus.substring(1)} Application'),
            content: TextField(
              controller: noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            actions: [
              TextButton(
                  onPressed: loading ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        setState(() => loading = true);
                        try {
                          final adminId =
                              FirebaseAuth.instance.currentUser?.uid ?? 'admin';
                          final docSnap = await FirebaseFirestore.instance
                              .collection('learner_applications')
                              .doc(docId)
                              .get();
                          final current = docSnap.data() ?? {};
                          final prevStatus =
                              (current['status'] ?? 'pending').toString();

                          await FirebaseFirestore.instance
                              .collection('learner_applications')
                              .doc(docId)
                              .update({
                            'status': toStatus,
                            'status_updated_at': FieldValue.serverTimestamp(),
                            'status_by': adminId,
                          });

                          await FirebaseFirestore.instance
                              .collection('learner_applications')
                              .doc(docId)
                              .collection('status_history')
                              .add({
                            'from': prevStatus,
                            'to': toStatus,
                            'note': noteCtrl.text.trim(),
                            'adminId': adminId,
                            'timestamp': FieldValue.serverTimestamp(),
                          });

                          if (Navigator.canPop(context)) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Status updated')));
                        } catch (e) {
                          setState(() => loading = false);
                          ScaffoldMessenger.of(context)
                              .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
                        }
                      },
                child: loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Update'),
              ),
            ],
          );
        });
      },
    );
  }
}

// ---------------- Details page (kept for admin access if needed) ----------------

class ApplicationDetailsPage extends StatefulWidget {
  final String docId;
  const ApplicationDetailsPage({required this.docId, super.key});

  @override
  State<ApplicationDetailsPage> createState() => _ApplicationDetailsPageState();
}

class _ApplicationDetailsPageState extends State<ApplicationDetailsPage> {
  @override
  Widget build(BuildContext context) {
    final ref =
        FirebaseFirestore.instance.collection('learner_applications').doc(widget.docId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Details'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final m = snap.data!.data() ?? {};
          final name = (m['name'] ?? '-').toString();
          final email = (m['email'] ?? '-').toString();
          final phone = (m['phone'] ?? '-').toString();
          final status = (m['status'] ?? 'pending').toString();
          final type = (m['type'] ?? 'application').toString(); // NEW: read type

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: AppText.sectionTitle), const SizedBox(height: 6), Text(email, style: AppText.tileSubtitle)])),
                _StatusChip(status: status),
              ]),
              const SizedBox(height: 18),
              Card(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _kv('User ID', (m['userId'] ?? '-').toString()),
                    _kv('Phone', phone),
                    _kv('Status', status),
                    _kv('Type', type), // NEW: show type
                    const SizedBox(height: 12),
                    Text('Notes / Admin History', style: AppText.tileTitle),
                    const SizedBox(height: 8),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: ref.collection('status_history').orderBy('timestamp', descending: true).limit(50).snapshots(),
                      builder: (context, histSnap) {
                        if (!histSnap.hasData) return const SizedBox.shrink();
                        final items = histSnap.data!.docs;
                        if (items.isEmpty) return Text('No status history', style: AppText.tileSubtitle);
                        return Column(
                          children: items.map((h) {
                            final data = h.data();
                            final from = (data['from'] ?? '-').toString();
                            final to = (data['to'] ?? '-').toString();
                            final note = (data['note'] ?? '').toString();
                            final admin = (data['adminId'] ?? '-').toString();
                            final ts = (data['timestamp'] is Timestamp) ? (data['timestamp'] as Timestamp).toDate().toLocal() : null;
                            final histDate = ts != null ? '${ts.year.toString().padLeft(4,'0')}-${ts.month.toString().padLeft(2,'0')}-${ts.day.toString().padLeft(2,'0')}' : '';
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: _StatusChip(status: to),
                              title: Text('$from → $to', style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (note.isNotEmpty) Text(note),
                                Text('By: $admin  ${histDate.isNotEmpty ? histDate : ''}', style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted))
                              ]),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}

// ---------------- Filters / Header Bar ----------------

class _HeaderBar extends StatefulWidget {
  final TextEditingController controller;

  const _HeaderBar({
    required this.controller,
  });

  @override
  State<_HeaderBar> createState() => _HeaderBarState();
}

class _HeaderBarState extends State<_HeaderBar> {
  late TextEditingController ctrl;
  @override
  void initState() {
    super.initState();
    ctrl = widget.controller;
    ctrl.addListener(_onCtrlChanged);
  }

  @override
  void dispose() {
    ctrl.removeListener(_onCtrlChanged);
    super.dispose();
  }

  void _onCtrlChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isVeryNarrow = width < 420;
    final isNarrow = width < 560;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              onChanged: (_) => {},
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.onSurfaceFaint),
                hintText: 'Search by name, email, userId…',
                hintStyle: const TextStyle(color: AppColors.onSurfaceFaint),
                suffixIcon: ctrl.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close, color: AppColors.onSurfaceFaint),
                        onPressed: () {
                          ctrl.clear();
                        },
                      ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          // optional space for future filters on wider screens
          if (!isVeryNarrow) ...[
            const SizedBox(width: 12),
            if (!isNarrow)
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.filter_list, size: 18),
                label: const Text('Filters'),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.divider),
                  foregroundColor: AppColors.onSurface,
                ),
              ),
          ]
        ]),
        const SizedBox(height: 6),
      ]),
    );
  }
}

// ---------------- Shared small helpers ----------------

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color c;
    IconData icon;
    switch (s) {
      case 'confirmed':
        c = AppColors.success;
        icon = Icons.check_circle;
        break;
      case 'paid':
        c = AppColors.info;
        icon = Icons.payment;
        break;
      case 'rejected':
        c = AppColors.danger;
        icon = Icons.cancel;
        break;
      case 'pending':
      default:
        c = AppColors.warning;
        icon = Icons.hourglass_bottom;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.withOpacity(0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: c, size: 14), const SizedBox(width: 8), Text(s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1), style: TextStyle(color: c, fontWeight: FontWeight.w700))]),
    );
  }
}

/// NEW: Compact type chip (application | retest | other)
class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final t = type.toLowerCase();
    Color bg;
    Color fg;
    IconData icon;
    String label;

    switch (t) {
      case 'retest':
      case 'learner_retest':
        bg = AppColors.info.withOpacity(0.10);
        fg = AppColors.info;
        icon = Icons.refresh;
        label = 'Retest';
        break;
      case 'application':
      case 'learner_application':
      default:
        bg = AppColors.brand.withOpacity(0.10);
        fg = AppColors.brand;
        icon = Icons.edit;
        label = 'Application';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: fg.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 12),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final String? ctaText;
  final VoidCallback? onTap;

  const _InfoCard({required this.icon, required this.iconColor, required this.title, this.subtitle, this.ctaText, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(18),
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: iconColor),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.onSurfaceMuted)),
          ],
          if (ctaText != null && onTap != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onTap, child: Text(ctaText!, style: const TextStyle(color: AppColors.onSurface))),
          ],
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClear;

  const _EmptyState({required this.title, required this.subtitle, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Center(child: _InfoCard(icon: Icons.inbox_outlined, iconColor: AppColors.onSurfaceFaint, title: title, subtitle: subtitle, ctaText: 'Clear search', onTap: onClear));
  }
}

Widget _kv(String k, String v) {
  return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(children: [SizedBox(width: 120, child: Text(k, style: const TextStyle(color: AppColors.onSurfaceMuted))), const SizedBox(width: 8), Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.onSurface)))]));
}

class _HeaderLabel extends StatelessWidget {
  final String text;
  const _HeaderLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Row(children: [Text(text, style: const TextStyle(color: AppColors.onSurface, fontWeight: FontWeight.w700)), const SizedBox(width: 6), const Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.onSurfaceFaint)]);
  }
}
