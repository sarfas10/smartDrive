// users_block.dart
import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 👉 Import your external details pages
import 'student_details.dart' as details;
import 'instructor_details.dart' as inst;

// Responsive breakpoint for switching List ↔ Table
const kTableBreakpoint = 720.0;

class UsersBlock extends StatefulWidget {
  const UsersBlock({super.key});

  @override
  State<UsersBlock> createState() => _UsersBlockState();
}

class _UsersBlockState extends State<UsersBlock> {
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _compact = false; // affects table row heights

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isTable = width >= kTableBreakpoint;

    return SafeArea(
      top: false,
      bottom: false,
      child: Column(
        children: [
          _FiltersBar(
            roleValue: _roleFilter,
            statusValue: _statusFilter,
            controller: _searchController,
            compact: _compact,
            onCompactToggle: () => setState(() => _compact = !_compact),
            onSearchChanged: () {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 250), () {
                if (mounted) setState(() {});
              });
            },
            onReset: () {
              _searchController.clear();
              setState(() {
                _roleFilter = 'all';
                _statusFilter = 'all';
              });
            },
            onRoleChanged: (v) => setState(() => _roleFilter = v ?? 'all'),
            onStatusChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
          ),
          const Divider(height: 1),
          Expanded(
            child: _TableTheme(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _UsersBody(
                  roleFilter: _roleFilter,
                  statusFilter: _statusFilter,
                  searchText: _searchController.text,
                  compact: _compact,
                  isTable: isTable,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// BODY: streams, filtering, and responsive rendering

class _UsersBody extends StatelessWidget {
  final String roleFilter;
  final String statusFilter;
  final String searchText;
  final bool compact;
  final bool isTable;

  const _UsersBody({
    required this.roleFilter,
    required this.statusFilter,
    required this.searchText,
    required this.compact,
    required this.isTable,
  });

  Query _buildQuery() {
    Query q = FirebaseFirestore.instance.collection('users');
    if (roleFilter != 'all') q = q.where('role', isEqualTo: roleFilter);
    if (statusFilter != 'all') q = q.where('status', isEqualTo: statusFilter);
    if (roleFilter == 'all' && statusFilter == 'all') q = q.orderBy('name');
    return q;
  }

  List<QueryDocumentSnapshot> _filterDocs(List<QueryDocumentSnapshot> docs) {
    final s = searchText.trim().toLowerCase();
    final filtered = docs.where((d) {
      if (s.isEmpty) return true;
      final m = d.data() as Map<String, dynamic>;
      final hay = [
        m['name'],
        m['email'],
        m['phone'],
        m['role'],
        m['status'],
      ].where((x) => x != null).join(' ').toLowerCase();
      return hay.contains(s);
    }).toList();

    if (roleFilter != 'all' || statusFilter != 'all') {
      filtered.sort((a, b) {
        final an = ((a.data() as Map<String, dynamic>)['name'] ?? '')
            .toString()
            .toLowerCase();
        final bn = ((b.data() as Map<String, dynamic>)['name'] ?? '')
            .toString()
            .toLowerCase();
        return an.compareTo(bn);
      });
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final query = _buildQuery();

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: _InfoCard(
              icon: Icons.error_outline,
              iconColor: Colors.red,
              title: 'Error loading users',
              subtitle: snapshot.error.toString(),
              ctaText: 'Retry',
              onTap: () {},
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data!.docs;
        final rowsDocs = _filterDocs(allDocs);
        final total = allDocs.length;
        final shown = rowsDocs.length;

        if (rowsDocs.isEmpty) {
          return _EmptyState(
            title: 'No users match your filters',
            subtitle: 'Try clearing the search or changing role/status.',
            onClear: () {},
          );
        }

        // Show count
        final header = Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              '$shown of $total users',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 4),
            Expanded(
              child: isTable
                  ? _UsersDataTable(docs: rowsDocs, compact: compact)
                  : _UsersListMobile(docs: rowsDocs),
            ),
          ],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
/* DESKTOP / TABLET: DataTable */

class _UsersDataTable extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final bool compact;
  const _UsersDataTable({required this.docs, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 760),
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                child: DataTable(
                  showCheckboxColumn: false,
                  dividerThickness: 0.6,
                  columnSpacing: 28,
                  headingRowHeight: 44,
                  dataRowMinHeight: compact ? 40 : 52,
                  dataRowMaxHeight: compact ? 52 : 68,
                  columns: const [
                    DataColumn(label: _HeaderLabel('Name')),
                    DataColumn(label: _HeaderLabel('Email')),
                    DataColumn(label: _HeaderLabel('Role')),
                    DataColumn(label: _HeaderLabel('Status')),
                  ],
                  rows: docs.asMap().entries.map((entry) {
                    final i = entry.key;
                    final doc = entry.value;
                    final m = doc.data() as Map<String, dynamic>;
                    final name = (m['name'] ?? 'Unknown').toString();
                    final email = (m['email'] ?? '-').toString();
                    final role = (m['role'] ?? '-').toString();
                    final status = (m['status'] ?? 'active').toString();
                    final uid = (m['uid']?.toString().isNotEmpty ?? false)
                        ? m['uid'].toString()
                        : doc.id;

                    return DataRow(
                      color: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.hovered)) {
                          return Theme.of(context).hoverColor.withOpacity(0.35);
                        }
                        return i.isEven
                            ? Theme.of(context)
                                .colorScheme
                                .surface
                                .withOpacity(0.0)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withOpacity(0.14);
                      }),
                      onSelectChanged: (_) => _openDetails(context, role, uid),
                      cells: [
                        DataCell(
                          MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 12,
                                  child: Text(
                                    name.isNotEmpty
                                        ? name.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    name,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Tooltip(
                            message: email,
                            child: Text(
                              email,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        DataCell(_RoleChip(role: role)),
                        DataCell(_StatusChip(status: status)),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
/* MOBILE: List view with tiles */

class _UsersListMobile extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  const _UsersListMobile({required this.docs});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final doc = docs[i];
        final m = doc.data() as Map<String, dynamic>;
        final name = (m['name'] ?? 'Unknown').toString();
        final email = (m['email'] ?? '-').toString();
        final role = (m['role'] ?? '-').toString();
        final status = (m['status'] ?? 'active').toString();
        final uid = (m['uid']?.toString().isNotEmpty ?? false)
            ? m['uid'].toString()
            : doc.id;

        return Card(
          elevation: 0,
          child: ListTile(
            onTap: () => _openDetails(context, role, uid),
            leading: CircleAvatar(
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
              ),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _RoleChip(role: role),
                      const SizedBox(width: 8),
                      _StatusChip(status: status),
                    ],
                  ),
                ],
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared navigation helper → pushes your EXTERNAL details pages

void _openDetails(BuildContext context, String role, String uid) {
  // Accept a few common aliases just in case.
  final r = (role).toLowerCase().trim();
  final isInstructor =
      r == 'instructor' || r == 'teacher' || r == 'tutor' || r == 'faculty';

  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => isInstructor
          ? const inst.InstructorDetailsPage()
          : const details.StudentDetailsPage(),
      // Both pages should read args via ModalRoute.of(context)!.settings.arguments
      settings: RouteSettings(arguments: {'uid': uid}),
      transitionsBuilder: (_, anim, __, child) {
        final slide =
            Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: slide, child: child),
        );
      },
    ),
  );
}

// ──────────────────────────────────────────────────────────────────────────────
// Filters bar (overflow-proof & mobile-optimized)

class _FiltersBar extends StatelessWidget {
  final String roleValue;
  final String statusValue;
  final TextEditingController controller;
  final bool compact;

  final VoidCallback onCompactToggle;
  final VoidCallback onSearchChanged;
  final VoidCallback onReset;
  final ValueChanged<String?> onRoleChanged;
  final ValueChanged<String?> onStatusChanged;

  const _FiltersBar({
    required this.roleValue,
    required this.statusValue,
    required this.controller,
    required this.compact,
    required this.onCompactToggle,
    required this.onSearchChanged,
    required this.onReset,
    required this.onRoleChanged,
    required this.onStatusChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final isUltraNarrow = width < 420;   // phones portrait
    final isNarrow = width < 560;        // small devices

    return Container(
      color: isDark
          ? theme.colorScheme.surface
          : theme.colorScheme.surfaceContainerHighest.withOpacity(0.25),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search + actions
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onChanged: (_) => onSearchChanged(),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    hintText: 'Search by name, email, phone…',
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              controller.clear();
                              onSearchChanged();
                            },
                          ),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: compact ? 'Comfortable rows' : 'Compact rows',
                child: IconButton(
                  onPressed: onCompactToggle,
                  icon: Icon(compact
                      ? Icons.format_line_spacing
                      : Icons.density_medium),
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: 'Reset filters',
                  child: TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset'),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),

          // Wrap lets items flow to next line on narrow screens
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: isUltraNarrow ? width - 32 : 220,
                  maxWidth: isNarrow ? width - 32 : 360,
                ),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: roleValue,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'student', child: Text('Students')),
                    DropdownMenuItem(value: 'instructor', child: Text('Instructors')),
                  ],
                  onChanged: onRoleChanged,
                ),
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: isUltraNarrow ? width - 32 : 220,
                  maxWidth: isNarrow ? width - 32 : 360,
                ),
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: statusValue,
                  decoration: InputDecoration(
                    labelText: 'Status',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              const _StatusLegend(),
              if (isNarrow)
                OutlinedButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reset'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Small UI helpers

class _TableTheme extends StatelessWidget {
  final Widget child;
  const _TableTheme({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DataTableTheme(
      data: DataTableThemeData(
        headingTextStyle: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
        headingRowColor:
            WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHighest.withOpacity(0.4)),
        dataTextStyle: theme.textTheme.bodyMedium,
        horizontalMargin: 16,
      ),
      child: child,
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String text;
  const _HeaderLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text),
        const SizedBox(width: 6),
        Icon(Icons.swap_vert_rounded, size: 16, color: Colors.grey.shade500),
      ],
    );
  }
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend();
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: const [
        _LegendDot(color: Colors.green, label: 'Active'),
        _LegendDot(color: Colors.orange, label: 'Pending'),
        _LegendDot(color: Colors.red, label: 'Blocked'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: Colors.grey.shade700)),
      ],
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

  const _InfoCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.ctaText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: iconColor),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          ],
          if (ctaText != null && onTap != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onTap, child: Text(ctaText!)),
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

  const _EmptyState({
    required this.title,
    required this.subtitle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: _InfoCard(
        icon: Icons.inbox_outlined,
        iconColor: Colors.grey.shade500,
        title: title,
        subtitle: subtitle,
        ctaText: 'Clear filters',
        onTap: onClear,
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});

  @override
  Widget build(BuildContext context) {
    final r = role.toLowerCase();
    final isStudent = r == 'student';
    final color = isStudent ? Colors.blue : Colors.deepPurple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isStudent ? Icons.school : Icons.workspace_premium, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            r.isEmpty ? '-' : r[0].toUpperCase() + r.substring(1),
            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    Color c;
    IconData icon;
    switch (s) {
      case 'active':
        c = Colors.green; icon = Icons.check_circle; break;
      case 'pending':
        c = Colors.orange; icon = Icons.hourglass_bottom; break;
      case 'blocked':
        c = Colors.red; icon = Icons.block; break;
      default:
        c = Colors.grey; icon = Icons.help_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Text(
            s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1),
            style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
