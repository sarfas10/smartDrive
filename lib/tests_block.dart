// tests_block.dart — Horizontally scrollable table (phones/tablets/desktop)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:cloud_firestore/cloud_firestore.dart';

import 'ui_common.dart';
import 'create_test_pool.dart';
import 'edit_test_pool.dart';

// Allow drag scrolling with mouse/trackpad/touch for the horizontal table
class _DragScrollBehavior extends MaterialScrollBehavior {
  const _DragScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      };
}

class TestsBlock extends StatefulWidget {
  final VoidCallback onCreatePool; // kept for API compatibility (unused)
  const TestsBlock({super.key, required this.onCreatePool});

  @override
  State<TestsBlock> createState() => _TestsBlockState();
}

class _TestsBlockState extends State<TestsBlock> {
  // ── Local UI state (search / filter / sort) ────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _statusFilter = 'all'; // all | active | inactive
  _SortBy _sortBy = _SortBy.createdDesc;

  // single horizontal controller so header + rows scroll together
  final ScrollController _hCtrl = ScrollController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _hCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('test_pool')
        .orderBy('created_at', descending: true)
        .snapshots();

    final pad = EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width < 520 ? 12 : 16,
      vertical: 10,
    );

    final screenW = MediaQuery.of(context).size.width;

    return ListView(
      primary: false, // avoid scroll conflicts on resize
      children: [
        // Title in BLACK (local Theme override)
        Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context)
                .textTheme
                .apply(bodyColor: Colors.black, displayColor: Colors.black),
          ),
          child: TableHeader(
            title: 'Test Pools',
            trailing: ElevatedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateTestPoolPage()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Create Pool'),
            ),
          ),
        ),
        const Divider(height: 1),

        // Toolbar: search + status filter + sort
        Padding(
          padding: pad.copyWith(bottom: 0, top: 12),
          child: _Toolbar(
            searchCtrl: _searchCtrl,
            statusFilter: _statusFilter,
            onStatusChanged: (v) => setState(() => _statusFilter = v),
            sortBy: _sortBy,
            onSortChanged: (v) => setState(() => _sortBy = v),
            onClearSearch: () => setState(() => _searchCtrl.clear()),
            onQueryChanged: (_) => setState(() {}), // live filtering
          ),
        ),

        Padding(
          padding: pad.copyWith(top: 10),
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _LoadingState();
              }
              if (snap.hasError) {
                return _ErrorState(error: snap.error.toString());
              }
              if (!snap.hasData) {
                return const _LoadingState();
              }

              var docs = (snap.data?.docs ?? []).toList();

              // Filter: search (title/description)
              final q = _searchCtrl.text.trim().toLowerCase();
              if (q.isNotEmpty) {
                docs = docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final t = (m['title'] ?? '').toString().toLowerCase();
                  final desc = (m['description'] ?? '').toString().toLowerCase();
                  return t.contains(q) || desc.contains(q);
                }).toList();
              }

              // Filter: status
              if (_statusFilter != 'all') {
                docs = docs.where((d) {
                  final m = d.data() as Map<String, dynamic>;
                  final s = (m['status'] ?? '').toString().toLowerCase();
                  return s == _statusFilter;
                }).toList();
              }

              // Sort (client-side)
              docs.sort((a, b) => _compareDocs(a, b, _sortBy));

              if (docs.isEmpty) {
                return const _EmptyState(message: 'No pools match your filters');
              }

              // Single H-scroll area containing header + all rows
              return ScrollConfiguration(
                behavior: const _DragScrollBehavior(),
                child: Scrollbar(
                  controller: _hCtrl,
                  thumbVisibility: true,
                  notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _hCtrl,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      // include card horizontal padding so rows never overflow
                      width: math.max(
                        _Cols.minTableWidth,
                        MediaQuery.of(context).size.width - pad.horizontal,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _PoolsHeaderRow(),
                          SizedBox(height: screenW < 520 ? 8 : 10),
                          Column(
                            children: [
                              for (int i = 0; i < docs.length; i++) ...[
                                Builder(
                                  builder: (_) {
                                    final d = docs[i];
                                    final m = d.data() as Map<String, dynamic>;
                                    return _PoolRow(
                                      docId: d.id,
                                      data: m,
                                      onToggleStatus: () => _toggleStatus(d.id, m),
                                      onEdit: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                EditTestPoolPage(poolId: d.id),
                                          ),
                                        );
                                      },
                                      onDelete: () => _deletePool(context, d.id),
                                      onQuestions: () => _openQuestions(
                                        context,
                                        d.id,
                                        (m['title'] ?? '').toString(),
                                      ),
                                      onAttempts: () =>
                                          _openAttempts(context, d.id),
                                    );
                                  },
                                ),
                                if (i != docs.length - 1)
                                  SizedBox(height: screenW < 520 ? 8 : 10),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _toggleStatus(String id, Map<String, dynamic> m) async {
    final curr = (m['status'] ?? 'active').toString();
    final next = curr == 'active' ? 'inactive' : 'active';
    await FirebaseFirestore.instance.collection('test_pool').doc(id).update({
      'status': next,
      'updated_at': FieldValue.serverTimestamp(),
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Status changed to $next')),
    );
  }

  // ── Modals ─────────────────────────────────────────────────────────────────
  Future<void> _openQuestions(
      BuildContext context, String poolId, String poolTitle) async {
    final q = FirebaseFirestore.instance
        .collection('test_pool')
        .doc(poolId)
        .collection('questions')
        .orderBy('created_at', descending: true);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Questions — $poolTitle'),
        content: SizedBox(
          width: 720,
          height: 460,
          child: StreamBuilder<QuerySnapshot>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final children = <Widget>[];
              for (final d in snap.data?.docs ?? []) {
                final m = d.data() as Map<String, dynamic>;
                final type = (m['type'] ?? 'mcq').toString();
                final opts = (m['options'] as List?) ?? const [];
                final imageUrl = (m['image_url'] ?? '').toString();

                children.add(
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F9FA),
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(left: BorderSide(color: kBrand, width: 4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                m['question']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.deepPurple.withOpacity(.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: Colors.deepPurple.withOpacity(.25)),
                              ),
                              child: Text(
                                type.toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.deepPurple,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (imageUrl.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: Image.network(imageUrl, fit: BoxFit.cover),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (type == 'mcq') ...[
                          for (int i = 0; i < opts.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '${String.fromCharCode(65 + i)}) ${opts[i].toString()}'
                                '${i == (m['answer_index'] ?? -1) ? '  ✓' : ''}',
                              ),
                            ),
                        ] else ...[
                          Text(
                            'Expected: ${m['expected_answer']?.toString() ?? '-'}',
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ],
                        if ((m['explanation']?.toString() ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Explanation: ${m['explanation']}',
                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () async => d.reference.delete(),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (children.isEmpty) {
                return const Center(child: Text('No questions added yet.'));
              }
              return ListView(children: children);
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _openAttempts(BuildContext context, String poolId) async {
    final q = FirebaseFirestore.instance
        .collection('test_attempts')
        .where('pool_id', isEqualTo: poolId)
        .orderBy('started_at', descending: true);

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Test Attempts'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: StreamBuilder<QuerySnapshot>(
            stream: q.snapshots(),
            builder: (context, snap) {
              final rows = <List<Widget>>[];
              for (final d in snap.data?.docs ?? []) {
                final m = d.data() as Map<String, dynamic>;
                rows.add([
                  Text(m['student_id']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                  Text('${m['score'] ?? 0}'),
                  Text(m['status']?.toString() ?? '-'),
                  Text(_fmtTs(m['started_at'] as Timestamp?)),
                  Text(_fmtTs(m['completed_at'] as Timestamp?)),
                ]);
              }
              if (rows.isEmpty) {
                return const Center(child: Text('No attempts found.'));
              }
              return DataTableWrap(
                columns: const ['Student', 'Score', 'Status', 'Started', 'Completed'],
                rows: rows,
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _deletePool(BuildContext context, String poolId) async {
    final ok = await confirmDialog(
      context: context,
      message: 'Delete this test pool?\nThis will also delete all its questions.',
    );
    if (!ok) return;

    final ref = FirebaseFirestore.instance.collection('test_pool').doc(poolId);

    Future<void> deleteQuestionsBatch() async {
      const batchSize = 60;
      while (true) {
        final snap = await ref.collection('questions').limit(batchSize).get();
        if (snap.docs.isEmpty) break;
        final wb = FirebaseFirestore.instance.batch();
        for (final dq in snap.docs) {
          wb.delete(dq.reference);
        }
        await wb.commit();
        if (snap.docs.length < batchSize) break;
      }
    }

    try {
      await deleteQuestionsBatch();
      await ref.delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Column widths and total width (for aligned, locked layout)
class _Cols {
  static const double gap = 12;

  static const double title = 220;
  static const double duration = 90;
  static const double passing = 90;
  static const double questions = 92;
  static const double status = 130; // a bit wider (badge + toggle)
  static const double created = 150;
  static const double actions = 72; // only the 3-dot menu

  // Estimated AppCard horizontal padding (left+right).
  static const double cardHPad = 24;

  /// Base width of columns + gaps (what the Row inside the card needs).
  static const double baseWidth =
      title + duration + passing + questions + status + created + actions + gap * 6;

  /// Minimum table width for the scroller (include the card’s padding).
  static const double minTableWidth = baseWidth + cardHPad;
}

// Header strip (uses fixed column widths; no internal scrolling)
class _PoolsHeaderRow extends StatelessWidget {
  const _PoolsHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1A4c63d2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: const [
          _HCell(head: 'Title', width: _Cols.title),
          _Spacer(width: _Cols.gap),
          _HCell(head: 'Duration', width: _Cols.duration),
          _Spacer(width: _Cols.gap),
          _HCell(head: 'Passing', width: _Cols.passing),
          _Spacer(width: _Cols.gap),
          _HCell(head: 'Questions', width: _Cols.questions),
          _Spacer(width: _Cols.gap),
          _HCell(head: 'Status', width: _Cols.status),
          _Spacer(width: _Cols.gap),
          _HCell(head: 'Created', width: _Cols.created),
          _Spacer(width: _Cols.gap),
          _HCell(head: 'Actions', width: _Cols.actions),
        ],
      ),
    );
  }
}

class _Spacer extends StatelessWidget {
  final double width;
  const _Spacer({required this.width});
  @override
  Widget build(BuildContext context) => SizedBox(width: width);
}

// Header cell (label-only) – fixed width for alignment
class _HCell extends StatelessWidget {
  final String head;
  final double width;
  const _HCell({required this.head, required this.width});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        head.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          color: Colors.grey.shade800,
          fontWeight: FontWeight.w800,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

// Row cell (value-only) – fixed width for alignment
class _Cell extends StatelessWidget {
  final Widget child;
  final double width;
  const _Cell({required this.child, this.width = 100});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.black87),
        child: child,
      ),
    );
  }
}

// Row-style pool presentation (header-aligned; horizontal scroll outside)
class _PoolRow extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onQuestions; // kept for compatibility
  final VoidCallback onAttempts;
  final VoidCallback onToggleStatus;

  const _PoolRow({
    required this.docId,
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onQuestions,
    required this.onAttempts,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '').toString();
    final desc = (data['description'] ?? '').toString();
    final dur = (data['duration_minutes'] ?? 0).toString();
    final pass = (data['passing_score_pct'] ?? 0).toString();
    final status = (data['status'] ?? 'active').toString();
    final createdAt = (data['created_at'] as Timestamp?)?.toDate();

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _Cell(
            width: _Cols.title,
            child: Tooltip(
              message: desc.isEmpty ? title : '$title\n\n$desc',
              child: Text(
                title.isEmpty ? '-' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const _Spacer(width: _Cols.gap),
          _Cell(
            width: _Cols.duration,
            child: Text('$dur min', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const _Spacer(width: _Cols.gap),
          _Cell(
            width: _Cols.passing,
            child: Text('Pass $pass%', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const _Spacer(width: _Cols.gap),
          _Cell(
            width: _Cols.questions,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _QuestionsCountText(poolId: docId),
            ),
          ),
          const _Spacer(width: _Cols.gap),
          _Cell(
            width: _Cols.status,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatusBadge(
                  text: status,
                  type: status == 'active' ? 'active' : 'rejected',
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: status == 'active' ? 'Deactivate' : 'Activate',
                  child: IconButton(
                    onPressed: onToggleStatus,
                    icon: Icon(
                      status == 'active' ? Icons.toggle_on : Icons.toggle_off,
                      color: status == 'active' ? Colors.green : Colors.grey,
                      size: 26,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          const _Spacer(width: _Cols.gap),
          _Cell(
            width: _Cols.created,
            child: Text(
              createdAt == null ? '-' : _fmtDate(createdAt),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const _Spacer(width: _Cols.gap),
          _Cell(
            width: _Cols.actions,
            child: _RowActions(
              onQuestions: onQuestions, // not shown, but kept
              onAttempts: onAttempts,
              onEdit: onEdit,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

// Always-3-dots menu (both wide & narrow) — white background
class _RowActions extends StatelessWidget {
  final VoidCallback onQuestions; // kept for compatibility (not shown)
  final VoidCallback onAttempts;  // kept for compatibility (unused)
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RowActions({
    required this.onQuestions,
    required this.onAttempts, // unused now
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final menuItems = <PopupMenuEntry<String>>[
      const PopupMenuItem(
        value: 'edit',
        child: _MenuRow('Edit', Icons.edit),
      ),
      const PopupMenuItem(
        value: 'delete',
        child: _MenuRow('Delete', Icons.delete_forever, danger: true),
      ),
    ];

    void handleSelect(String v) {
      switch (v) {
        case 'edit':
          onEdit();
          break;
        case 'delete':
          onDelete();
          break;
      }
    }

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
          textStyle: TextStyle(color: Colors.black87),
          elevation: 8,
        ),
      ),
      child: IconTheme.merge(
        data: const IconThemeData(color: Colors.black87),
        child: PopupMenuButton<String>(
          tooltip: 'Actions',
          onSelected: handleSelect,
          itemBuilder: (_) => menuItems,
          child: const Icon(Icons.more_vert, size: 22),
        ),
      ),
    );
  }
}


class _MenuRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool danger;
  const _MenuRow(this.label, this.icon, {this.danger = false});
  @override
  Widget build(BuildContext context) {
    final c = danger ? Colors.red : Colors.black87;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: c)),
      ],
    );
  }
}

// Live question count (realtime)
class _QuestionsCountText extends StatelessWidget {
  final String poolId;
  const _QuestionsCountText({required this.poolId});

  @override
  Widget build(BuildContext context) {
    final qs = FirebaseFirestore.instance
        .collection('test_pool')
        .doc(poolId)
        .collection('questions')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: qs,
      builder: (_, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Text('$count', style: const TextStyle(fontWeight: FontWeight.w700));
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Toolbar with search / status filter / sort
class _Toolbar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String statusFilter;
  final ValueChanged<String> onStatusChanged;
  final _SortBy sortBy;
  final ValueChanged<_SortBy> onSortChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<String> onQueryChanged;

  const _Toolbar({
    required this.searchCtrl,
    required this.statusFilter,
    required this.onStatusChanged,
    required this.sortBy,
    required this.onSortChanged,
    required this.onClearSearch,
    required this.onQueryChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 740;

    // Search
    final searchField = TextField(
      controller: searchCtrl,
      onChanged: onQueryChanged,
      decoration: InputDecoration(
        hintText: 'Search by title or description…',
        hintStyle: const TextStyle(color: Colors.black45),
        prefixIcon: const Icon(Icons.search, color: Colors.black54),
        suffixIcon: (searchCtrl.text.isEmpty)
            ? null
            : IconButton(
                onPressed: onClearSearch,
                icon: const Icon(Icons.close, color: Colors.black54),
                tooltip: 'Clear',
              ),
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      style: const TextStyle(color: Colors.black),
    );

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterPill(
          label: 'All',
          selected: statusFilter == 'all',
          onTap: () => onStatusChanged('all'),
        ),
        FilterPill(
          label: 'Active',
          selected: statusFilter == 'active',
          onTap: () => onStatusChanged('active'),
        ),
        FilterPill(
          label: 'Inactive',
          selected: statusFilter == 'inactive',
          onTap: () => onStatusChanged('inactive'),
        ),
      ],
    );

    // Sort menu with white popup background
    final sortButton = Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: const PopupMenuThemeData(
          color: Colors.white,
          textStyle: TextStyle(color: Colors.black87),
          elevation: 8,
        ),
      ),
      child: PopupMenuButton<_SortBy>(
        tooltip: 'Sort',
        initialValue: sortBy,
        onSelected: onSortChanged,
        itemBuilder: (_) => const [
          PopupMenuItem(value: _SortBy.createdDesc, child: _SortRow('Newest first', Icons.south)),
          PopupMenuItem(value: _SortBy.createdAsc, child: _SortRow('Oldest first', Icons.north)),
          PopupMenuItem(value: _SortBy.titleAsc, child: _SortRow('Title A–Z', Icons.sort_by_alpha)),
          PopupMenuItem(value: _SortBy.durationDesc, child: _SortRow('Duration (high→low)', Icons.timer)),
          PopupMenuItem(value: _SortBy.passingDesc, child: _SortRow('Passing % (high→low)', Icons.verified)),
        ],
        child: OutlinedButton.icon(
          onPressed: null, // acts only as an anchor; PopupMenu handles taps
          icon: const Icon(Icons.sort, color: Colors.black),
          label: Text(
            _sortLabel(sortBy),
            style: const TextStyle(color: Colors.black),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            disabledForegroundColor: Colors.black,
            side: const BorderSide(color: Colors.black12),
          ),
        ),
      ),
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: double.infinity, child: searchField),
          const SizedBox(height: 8),
          filters,
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: sortButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: searchField),
        const SizedBox(width: 12),
        filters,
        const Spacer(),
        sortButton,
      ],
    );
  }
}

class _SortRow extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SortRow(this.label, this.icon);

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: Colors.black87),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
}

enum _SortBy { createdDesc, createdAsc, titleAsc, durationDesc, passingDesc }

String _sortLabel(_SortBy s) {
  switch (s) {
    case _SortBy.createdDesc:
      return 'Newest first';
    case _SortBy.createdAsc:
      return 'Oldest first';
    case _SortBy.titleAsc:
      return 'Title A–Z';
    case _SortBy.durationDesc:
      return 'Duration (high→low)';
    case _SortBy.passingDesc:
      return 'Passing % (high→low)';
  }
}

int _compareDocs(QueryDocumentSnapshot a, QueryDocumentSnapshot b, _SortBy sort) {
  final ma = a.data() as Map<String, dynamic>;
  final mb = b.data() as Map<String, dynamic>;
  int cmpInt(num? x, num? y) => (x ?? 0).compareTo(y ?? 0);
  int cmpStr(String? x, String? y) => (x ?? '').toLowerCase().compareTo((y ?? '').toLowerCase());

  switch (sort) {
    case _SortBy.createdDesc:
      final tA = ma['created_at'] as Timestamp?;
      final tB = mb['created_at'] as Timestamp?;
      if (tA == null && tB == null) return 0;
      if (tA == null) return 1;
      if (tB == null) return -1;
      return tB.compareTo(tA);
    case _SortBy.createdAsc:
      final tA2 = ma['created_at'] as Timestamp?;
      final tB2 = mb['created_at'] as Timestamp?;
      if (tA2 == null && tB2 == null) return 0;
      if (tA2 == null) return 1;
      if (tB2 == null) return -1;
      return tA2.compareTo(tB2);
    case _SortBy.titleAsc:
      return cmpStr(ma['title']?.toString(), mb['title']?.toString());
    case _SortBy.durationDesc:
      return -cmpInt(ma['duration_minutes'] as num?, mb['duration_minutes'] as num?);
    case _SortBy.passingDesc:
      return -cmpInt(ma['passing_score_pct'] as num?, mb['passing_score_pct'] as num?);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// States
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('Loading test pools…', style: TextStyle(color: Colors.grey.shade700)),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? message;
  const _EmptyState({this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          children: [
            Icon(Icons.fact_check_outlined, size: 64, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            Text(message ?? 'No test pools yet',
                style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Create your first pool to get started',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Failed to load pools: $error', style: const TextStyle(color: Colors.red)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utils
String _fmtTs(Timestamp? ts) {
  if (ts == null) return '-';
  return _fmtDate(ts.toDate());
}

String _fmtDate(DateTime dt) {
  final d = dt.toLocal();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$y-$m-$day $hh:$mm';
}
