// lib/students_list_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'student_progress.dart'; // <-- from previous message

class StudentsListPage extends StatefulWidget {
  const StudentsListPage({super.key });

  

  @override
  State<StudentsListPage> createState() => _StudentsListPageState();
}

class _StudentsListPageState extends State<StudentsListPage> {
  static const _kBrand = Color(0xFF4C63D2);

  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _status = 'all'; // all | active | pending | inactive | suspended
  String _sort = 'nameAsc'; // nameAsc | nameDesc | newest | oldest | status

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = FirebaseFirestore.instance.collection('users');

    // Prefer a Firestore-side filter to restrict to students; tolerate naming variants.
    final query = base.where('role', whereIn: ['student', 'Student']);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text('My Students'),
        
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _error('Failed to load students.\n${snap.error}');
          }
          final allDocs = snap.data?.docs ?? const [];

          // Convert to view models
          final allStudents = allDocs.map((d) => _Student.fromDoc(d)).toList();

          // Counters (Total / Active)
          final totalCount = allStudents.length;
          final activeCount =
              allStudents.where((s) => s.status == 'active').length;

          // Apply UI-side filters
          var filtered = List<_Student>.from(allStudents);

          // Status
          if (_status != 'all') {
            filtered = filtered.where((s) => s.status == _status).toList();
          }

          // Search (name or email contains, case-insensitive)
          final q = _searchCtrl.text.trim().toLowerCase();
          if (q.isNotEmpty) {
            filtered = filtered
                .where((s) =>
                    s.name.toLowerCase().contains(q) ||
                    s.email.toLowerCase().contains(q))
                .toList();
          }

          // Sort
          filtered.sort((a, b) {
            switch (_sort) {
              case 'nameDesc':
                return b.nameLower.compareTo(a.nameLower);
              case 'newest':
                return b.createdAt.compareTo(a.createdAt);
              case 'oldest':
                return a.createdAt.compareTo(b.createdAt);
              case 'status':
                return a.status.compareTo(b.status); // a..z (active first)
              case 'nameAsc':
              default:
                return a.nameLower.compareTo(b.nameLower);
            }
          });

          return Column(
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _kpiCard(
                        icon: Icons.group_outlined,
                        label: 'Total Students',
                        value: '$totalCount',
                        tint: const Color(0xFFE8EEFF),
                        iconColor: _kBrand,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _kpiCard(
                        icon: Icons.trending_up_rounded,
                        label: 'Active Students',
                        value: '$activeCount',
                        tint: const Color(0xFFEAF7EF),
                        iconColor: const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Search + filters
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: _searchBox(
                        controller: _searchCtrl,
                        hint: 'Search students...',
                        onChanged: (v) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 250),
                              () => setState(() {}));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(child: _statusDropdown(_status, (v) => setState(() => _status = v))),
                    const SizedBox(width: 12),
                    Expanded(child: _sortDropdown(_sort, (v) => setState(() => _sort = v))),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // List
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemBuilder: (_, i) {
                    final s = filtered[i];
                    return _studentTile(
                      student: s,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StudentProgressPage(studentId: s.id),
                          ),
                        );
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: filtered.length,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // UI helpers
  // ────────────────────────────────────────────────────────────────────────────

  Widget _kpiCard({
    required IconData icon,
    required String label,
    required String value,
    required Color tint,
    required Color iconColor,
  }) {
    return Container(
      height: 74,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _searchBox({
    required TextEditingController controller,
    required String hint,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC7CEF7)),
          ),
        ),
      ),
    );
  }

  Widget _statusDropdown(String value, ValueChanged<String> onChanged) {
    const opts = [
      ['all', 'All Status'],
      ['active', 'Active'],
      ['pending', 'Pending'],
      ['inactive', 'Inactive'],
      ['suspended', 'Suspended'],
    ];
    return _dropdown(
      value: value,
      items: opts,
      onChanged: onChanged,
    );
  }

  Widget _sortDropdown(String value, ValueChanged<String> onChanged) {
    const opts = [
      ['nameAsc', 'Sort by Name'],
      ['nameDesc', 'Name (Z–A)'],
      ['newest', 'Newest'],
      ['oldest', 'Oldest'],
      ['status', 'Status (A–Z)'],
    ];
    return _dropdown(
      value: value,
      items: opts,
      onChanged: onChanged,
    );
  }

  Widget _dropdown({
    required String value,
    required List<List<String>> items,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          items: items
              .map((it) => DropdownMenuItem(
                    value: it[0],
                    child: Text(it[1]),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _studentTile({required _Student student, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(color: Color(0x08000000), blurRadius: 6, offset: Offset(0, 2))
            ],
          ),
          child: Row(
            children: [
              _Avatar(initials: student.initials),
              const SizedBox(width: 10),
              Expanded(
                child: _TwoLine(
                  title: student.name,
                  subtitle: student.email,
                ),
              ),
              _StatusPill(status: student.status),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _error(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(msg, textAlign: TextAlign.center),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Models & Small widgets
// ──────────────────────────────────────────────────────────────────────────────

class _Student {
  final String id;
  final String name;
  final String email;
  final String status; // normalized lower-case
  final DateTime createdAt;

  _Student({
    required this.id,
    required this.name,
    required this.email,
    required this.status,
    required this.createdAt,
  });

  String get nameLower => name.toLowerCase();
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'S';
    final a = parts[0][0].toUpperCase();
    final b = parts.length > 1 ? parts[1][0].toUpperCase() : '';
    return '$a$b';
  }

  factory _Student.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final name = (m['displayName'] ?? m['name'] ?? 'Student').toString();
    final email = (m['email'] ?? '').toString();
    final statusRaw = (m['status'] ?? (m['isActive'] == true ? 'active' : 'inactive'))
        .toString()
        .toLowerCase();
    final created =
        (m['createdAt'] ?? m['enrolledAt'] ?? m['enrolled_at']);
    DateTime createdAt;
    if (created is Timestamp) {
      createdAt = created.toDate();
    } else if (created is DateTime) {
      createdAt = created;
    } else if (created is String) {
      createdAt = DateTime.tryParse(created) ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else {
      createdAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return _Student(
      id: d.id,
      name: name,
      email: email,
      status: _normalizeStatus(statusRaw),
      createdAt: createdAt,
    );
  }

  static String _normalizeStatus(String s) {
    if (s.startsWith('a')) return 'active';
    if (s.startsWith('p')) return 'pending';
    if (s.startsWith('s')) return 'suspended';
    return 'inactive';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFE9EDFF),
      child: Text(
        initials,
        style: const TextStyle(
          color: Color(0xFF4C63D2),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _TwoLine extends StatelessWidget {
  const _TwoLine({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    late String text;

    switch (status) {
      case 'active':
        bg = const Color(0xFFEAF7EF);
        fg = const Color(0xFF2E7D32);
        text = 'Active';
        break;
      case 'pending':
        bg = const Color(0xFFFFF5E5);
        fg = const Color(0xFF9C6F19);
        text = 'Pending';
        break;
      case 'suspended':
        bg = const Color(0xFFFFEBEE);
        fg = const Color(0xFFD32F2F);
        text = 'Suspended';
        break;
      case 'inactive':
      default:
        bg = const Color(0xFFF4F6F8);
        fg = const Color(0xFF6B7280);
        text = 'Inactive';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
