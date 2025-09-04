// lib/admin_dashboard.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:smart_drive/reusables/branding.dart';

import 'users_block.dart';
import 'materials_block.dart';
import 'tests_block.dart';
import 'notifications_block.dart';

import 'settings_block.dart';
import 'slots_block.dart';
import 'plans_block.dart'; // New import for plans management

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String selected = 'dashboard';

  static const kBg = Color(0xFFF5F6F8);
  static const kSurface = Colors.white;

  void _pick(String s) => setState(() => selected = s);
  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final bool isMobile = width < 768;
        final bool isDesktop = width >= 1080;
        final double sidebarWidth = isDesktop ? 280 : 260;

        return Scaffold(
          backgroundColor: kBg,
          drawer: isDesktop ? null : _buildDrawer(),
          appBar: isDesktop ? null : _buildAppBar(),
          body: SafeArea(
            bottom: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isMobile) _buildSidebar(sidebarWidth),
                _buildMainContent(isDesktop),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: kSurface,
      elevation: 8,
      child: Sidebar(selected: selected, onPick: _pick, isInDrawer: true),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 2,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const AppBrandingRow(
        logoSize: 36,
        nameSize: 20,
        spacing: 8,
        textColor: Colors.white,
      ),
      centerTitle: false,
    );
  }

  Widget _buildSidebar(double width) {
    return SizedBox(
      width: width,
      child: Sidebar(selected: selected, onPick: _pick),
    );
  }

  Widget _buildMainContent(bool isDesktop) {
    return Expanded(
      child: Padding(
        padding: EdgeInsets.all(isDesktop ? 16.0 : 12.0),
        child: _CardSurface(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildSection(), // no header, just content
          ),
        ),
      ),
    );
  }

  Widget _buildSection() {
    switch (selected) {
      case 'dashboard':
        return const DashboardBlock();
      case 'users':
        return const UsersBlock();
      case 'slots':
        return const SlotsBlock();
      case 'materials':
        return const MaterialsBlock();
      case 'tests':
        return TestsBlock(onCreatePool: _openCreatePool);
      case 'plans':
        return const PlansBlock(); // New plans block
      case 'notifications':
        return const NotificationsBlock();
      
      case 'settings':
        return const SettingsBlock();
      default:
        return const Center(child: Text('Section not found'));
    }
  }

  Future<void> _openCreatePool() async {
    final controllers = {
      'title': TextEditingController(),
      'category': TextEditingController(),
      'duration': TextEditingController(text: '30'),
      'passing': TextEditingController(text: '80'),
    };

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create Test Pool'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTextField('Title', controllers['title']!),
              const SizedBox(height: 12),
              _buildTextField('Category', controllers['category']!),
              const SizedBox(height: 12),
              _buildTextField('Duration (minutes)', controllers['duration']!, isNumber: true),
              const SizedBox(height: 12),
              _buildTextField('Passing Score (%)', controllers['passing']!, isNumber: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _saveTestPool(controllers),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final c in controllers.values) {
      c.dispose();
    }
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: const InputDecoration(
        labelText: '',
        border: OutlineInputBorder(),
      ).copyWith(labelText: label),
    );
  }

  Future<void> _saveTestPool(Map<String, TextEditingController> controllers) async {
    try {
      final doc = {
        'title': controllers['title']!.text.trim(),
        'category': controllers['category']!.text.trim(),
        'duration_minutes': int.tryParse(controllers['duration']!.text.trim()) ?? 30,
        'passing_score_pct': int.tryParse(controllers['passing']!.text.trim()) ?? 80,
        'status': 'active',
        'created_at': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('tests_pools').add(doc);

      if (mounted) {
        Navigator.pop(context);
        _snack('Test pool created successfully');
      }
    } catch (e) {
      if (mounted) _snack('Error creating test pool: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sidebar
// ─────────────────────────────────────────────────────────────────────────────

class Sidebar extends StatelessWidget {
  final String selected;
  final void Function(String) onPick;
  final bool isInDrawer;
  const Sidebar({
    super.key,
    required this.selected,
    required this.onPick,
    this.isInDrawer = false,
  });

  static const _menuItems = [
    (Icons.dashboard_rounded, 'Dashboard', 'dashboard'),
    (Icons.group_rounded, 'Users', 'users'),
    (Icons.event_available_rounded, 'Slots', 'slots'),
    (Icons.menu_book_rounded, 'Materials', 'materials'),
    (Icons.quiz_rounded, 'Tests', 'tests'),
    (Icons.payment_rounded, 'Plans', 'plans'), // New plans menu item
    (Icons.notifications_rounded, 'Notifications', 'notifications'),
    
    (Icons.settings_rounded, 'Settings', 'settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111418),
        border: Border(
          right: BorderSide(color: Color(0x14000000), width: 0.6),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppBrandingRow(
                    logoSize: 40,
                    nameSize: 18,
                    spacing: 10,
                    textColor: Colors.white,
                  ),
                  SizedBox(height: 16),
                  Divider(color: Colors.white24, height: 1),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: List.generate(_menuItems.length, (index) {
                    final item = _menuItems[index];
                    final isActive = selected == item.$3;
                    return _MenuItem(
                      icon: item.$1,
                      title: item.$2,
                      isActive: isActive,
                      onTap: () {
                        Navigator.maybePop(context);
                        onPick(item.$3);
                      },
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = AppColors.primary;
    const inactiveColor = Colors.white;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? const Color(0x1A4C008A) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              width: 3,
              color: isActive ? activeColor : Colors.transparent,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isActive ? activeColor : inactiveColor, size: 20),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isActive ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard (3:1 stats : activities)
// ─────────────────────────────────────────────────────────────────────────────

class _DashData {
  final int slotsTotal;
  final int instructorsActive;
  final int studentsActive;
  final int revenue; // static for now
  const _DashData({
    required this.slotsTotal,
    required this.instructorsActive,
    required this.studentsActive,
    required this.revenue,
  });
}

class DashboardBlock extends StatelessWidget {
  const DashboardBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashData>(
      future: _fetchDashboardData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Error: ${snapshot.error}')),
          );
        }

        final d = snapshot.data!;
        final stats = {
          'slots': _formatNumber(d.slotsTotal),
          'instructors': _formatNumber(d.instructorsActive),
          'revenue': '₹${_formatNumber(d.revenue)}',
          'students': _formatNumber(d.studentsActive),
        };

        return LayoutBuilder(
          builder: (context, c) {
            final isCompact = c.maxWidth < 720;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _DashboardHeader(), // 👈 Title only for dashboard
                const SizedBox(height: 16),
                Expanded(
                  flex: 3,
                  child: _StatsViewport(stats: stats, maxWidth: c.maxWidth),
                ),
                const SizedBox(height: 12),
                Expanded(
                  flex: 1,
                  child: _RecentActivities(isCompact: isCompact),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<_DashData> _fetchDashboardData() async {
    final db = FirebaseFirestore.instance;

    final slotsTotalFuture = db.collection('slots').get().then((s) => s.size);

    final instructorsActiveFuture = db
        .collection('users')
        .where('role', isEqualTo: 'instructor')
        .where('status', isEqualTo: 'active')
        .get()
        .then((s) => s.size);

    final studentsActiveFuture = db
        .collection('users')
        .where('role', isEqualTo: 'student')
        .where('status', isEqualTo: 'active')
        .get()
        .then((s) => s.size);

    final results = await Future.wait<int>([
      slotsTotalFuture,
      instructorsActiveFuture,
      studentsActiveFuture,
    ]);

    const staticRevenue = 125000; // placeholder value

    return _DashData(
      slotsTotal: results[0],
      instructorsActive: results[1],
      studentsActive: results[2],
      revenue: staticRevenue,
    );
  }
}

class _StatsViewport extends StatelessWidget {
  final Map<String, String> stats;
  final double maxWidth;
  const _StatsViewport({required this.stats, required this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _StatCard(title: 'Total Slots', value: stats['slots']!, icon: Icons.event_available),
      _StatCard(title: 'Active Instructors', value: stats['instructors']!, icon: Icons.person),
      _StatCard(title: 'Total Revenue', value: stats['revenue']!, icon: Icons.attach_money),
      _StatCard(title: 'Active Students', value: stats['students']!, icon: Icons.school),
    ];

    final bool narrow = maxWidth < 600;
    final double aspect = narrow ? 2.8 : 2.4;
    final double maxExtent = narrow ? maxWidth : 300.0;

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: aspect,
      ),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }
}

class _RecentActivities extends StatelessWidget {
  final bool isCompact;
  const _RecentActivities({required this.isCompact});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('bookings')
                .orderBy('created_at', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('Failed to load activities: ${snapshot.error}');
              }
              final docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return const Center(child: Text('No recent activities'));
              }
              final bookings = docs.map((d) => d.data()).toList();

              if (isCompact) {
                return ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: bookings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final b = bookings[i];
                    final createdAt = (b['created_at'] is Timestamp)
                        ? (b['created_at'] as Timestamp).toDate()
                        : null;
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0x11000000)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _kv('Slot ID', (b['slot_id'] ?? '-').toString()),
                          _kv('Student ID', (b['user_id'] ?? '-').toString()),
                          _kv('Status', (b['status'] ?? '-').toString()),
                          _kv('Date', createdAt?.toString().split('.').first ?? '-'),
                        ],
                      ),
                    );
                  },
                );
              } else {
                return Scrollbar(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 760),
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Slot ID')),
                            DataColumn(label: Text('Student ID')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Date')),
                          ],
                          rows: bookings.map((b) {
                            final createdAt = (b['created_at'] is Timestamp)
                                ? (b['created_at'] as Timestamp).toDate()
                                : null;
                            return DataRow(cells: [
                              DataCell(Text((b['slot_id'] ?? '-').toString())),
                              DataCell(Text((b['student_id'] ?? '-').toString())),
                              DataCell(Text((b['status'] ?? '-').toString())),
                              DataCell(Text(createdAt?.toString().split('.').first ?? '-')),
                            ]);
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI helpers
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [
          BoxShadow(color: Color(0x07000000), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: AppColors.primary, size: 20),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0x1A4C008A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: AppColors.primary, size: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  final Widget child;
  const _CardSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x11000000)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: child,
    );
  }
}

String _formatNumber(num? number) {
  final n = number ?? 0;
  final s = n.toString();
  return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        SizedBox(width: 110, child: Text(k, style: const TextStyle(color: Color(0xFF6B7280)))),
        const SizedBox(width: 8),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],
    ),
  );
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return const Text(
      "Dashboard Overview",
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1F2937),
      ),
    );
  }
}