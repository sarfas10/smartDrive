// lib/admin/users_block.dart
import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Theme
import 'package:smart_drive/theme/app_theme.dart';

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

  // --- New: show dialog to add office staff ---
  Future<void> _showAddOfficeStaffDialog() async {
    final _nameController = TextEditingController();
    final _emailController = TextEditingController();
    final _passwordController = TextEditingController();
    final _formKey = GlobalKey<FormState>();
    var loading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Add Office Staff'),
            content: Form(
              key: _formKey,
              child: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        validator: (v) =>
                            (v == null || v.trim().length < 2) ? 'Enter a valid name' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Email required';
                          final re = RegExp(r"^[^@]+@[^@]+\.[^@]+");
                          if (!re.hasMatch(v.trim())) return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (v) {
                          if (v == null || v.length < 6) return 'Password must be at least 6 chars';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                      },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        if (!(_formKey.currentState?.validate() ?? false)) return;
                        final name = _nameController.text.trim();
                        final email = _emailController.text.trim();
                        final password = _passwordController.text;

                        setStateDialog(() => loading = true);

                        try {
                          // Create in Firebase Auth
                          final userCred = await FirebaseAuth.instance
                              .createUserWithEmailAndPassword(email: email, password: password);

                          final uid = userCred.user?.uid ?? '';

                          // Create document in users collection
                          await FirebaseFirestore.instance.collection('users').doc(uid).set({
                            'name': name,
                            'email': email,
                            'createdAt': FieldValue.serverTimestamp(),
                            'role': 'office_staff',
                            // optionally add status or other fields:
                            'status': 'active',
                            'uid': uid,
                          }, SetOptions(merge: true));

                          setStateDialog(() => loading = false);
                          Navigator.of(ctx).pop();

                          // success feedback
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Office staff added successfully')),
                            );
                          }
                        } on FirebaseAuthException catch (e) {
                          setStateDialog(() => loading = false);
                          String message = e.message ?? 'Authentication error';
                          // helpful common messages
                          if (e.code == 'email-already-in-use') {
                            message = 'This email is already in use.';
                          } else if (e.code == 'invalid-email') {
                            message = 'Invalid email.';
                          } else if (e.code == 'weak-password') {
                            message = 'Password is too weak.';
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
                          }
                        } catch (e) {
                          setStateDialog(() => loading = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error: ${e.toString()}')),
                            );
                          }
                        }
                      },
                child: loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create'),
              ),
            ],
          );
        });
      },
    );
  }
  // --- end new dialog ---

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
            // pass the new callback
            onAddOfficeStaff: _showAddOfficeStaffDialog,
          ),
          const Divider(height: 1, color: AppColors.divider),
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
              iconColor: AppColors.danger,
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
              style: const TextStyle(color: AppColors.onSurfaceMuted, fontSize: 12),
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
                color: AppColors.surface,
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
                          return AppColors.brand.withOpacity(0.08);
                        }
                        // subtle zebra stripe on odd rows
                        return i.isEven
                            ? Colors.transparent
                            : AppColors.onSurface.withOpacity(0.02);
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
                                  backgroundColor: AppColors.brand.withOpacity(0.12),
                                  child: Text(
                                    name.isNotEmpty
                                        ? name.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: AppColors.brand,
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
                                    style: const TextStyle(
                                      color: AppColors.onSurface,
                                    ),
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
                                color: AppColors.onSurfaceMuted,
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
          color: AppColors.surface,
          child: ListTile(
            onTap: () => _openDetails(context, role, uid),
            leading: CircleAvatar(
              backgroundColor: AppColors.brand.withOpacity(0.12),
              child: Text(
                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                style: const TextStyle(color: AppColors.brand),
              ),
            ),
            title: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.onSurface),
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
                      color: AppColors.onSurfaceMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: const [
                      // Proportional spacing handled by Row
                    ],
                  ),
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
            trailing: const Icon(Icons.chevron_right, color: AppColors.onSurfaceFaint),
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

  // New callback for Add Office Staff button
  final VoidCallback? onAddOfficeStaff;

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
    this.onAddOfficeStaff,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isUltraNarrow = width < 420;   // phones portrait
    final isNarrow = width < 560;        // small devices

    return Container(
      color: AppColors.surface,
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
                    prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.onSurfaceFaint),
                    hintText: 'Search by name, email, phone…',
                    hintStyle: const TextStyle(color: AppColors.onSurfaceFaint),
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close, color: AppColors.onSurfaceFaint),
                            onPressed: () {
                              controller.clear();
                              onSearchChanged();
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.l),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              

              // New: Add Office Staffs button (visible on all widths)
              const SizedBox(width: 8),
              Tooltip(
                message: 'Add Office Staffs',
                child: ElevatedButton.icon(
                  onPressed: onAddOfficeStaff,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Office Staffs'),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.m),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'student', child: Text('Students')),
                    DropdownMenuItem(value: 'instructor', child: Text('Instructors')),
                    DropdownMenuItem(value: 'office_staff', child: Text('Office Staffs')),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.m),
                    ),
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
                  icon: const Icon(Icons.refresh, color: AppColors.onSurface),
                  label: const Text('Reset', style: TextStyle(color: AppColors.onSurface)),
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
    return DataTableTheme(
      data: DataTableThemeData(
        headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
        ),
        headingRowColor: MaterialStatePropertyAll(
          AppColors.brand.withOpacity(0.08),
        ),
        dataTextStyle: const TextStyle(color: AppColors.onSurface),
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
        Text(text, style: const TextStyle(color: AppColors.onSurface)),
        const SizedBox(width: 6),
        const Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.onSurfaceFaint),
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
        _LegendDot(color: AppColors.success, label: 'Active'),
        _LegendDot(color: AppColors.warning, label: 'Pending'),
        _LegendDot(color: AppColors.danger,  label: 'Blocked'),
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
        Text(label, style: const TextStyle(color: AppColors.onSurfaceMuted)),
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
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 42, color: iconColor),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.onSurface)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
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
        iconColor: AppColors.onSurfaceFaint,
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
    final color = isStudent ? AppColors.info : AppColors.purple;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
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
        c = AppColors.success; icon = Icons.check_circle; break;
      case 'pending':
        c = AppColors.warning; icon = Icons.hourglass_bottom; break;
      case 'blocked':
        c = AppColors.danger; icon = Icons.block; break;
      default:
        c = AppColors.onSurfaceMuted; icon = Icons.help_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
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
