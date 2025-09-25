// lib/admin_dashboard.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

// Branding row (keeps app brand look)
import 'package:smart_drive/reusables/branding.dart' hide AppColors;

// Blocks (keep these imports as in your project)
import 'users_block.dart';
import 'materials_block.dart';
import 'tests_block.dart';
import 'test_bookings_block.dart';
import 'notifications_block.dart';
import 'settings_block.dart';
import 'slots_block.dart';
import 'plans_block.dart';

// App theme
import 'theme/app_theme.dart';

// Hardcoded Hostinger endpoint (matches your public_html path)
const String _kRazorpayEndpoint =
    'https://tajdrivingschool.in/smartDrive/payments/getRazorpayTotal.php';

// Default days shown initially
const int _kDefaultRevenueDays = 30;

// Debug notifier shown as a small banner when issues occur
final ValueNotifier<String?> _razorpayDebug = ValueNotifier<String?>(null);

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});
  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String selected = 'dashboard';

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
          backgroundColor: AppColors.background,
          drawer: isDesktop ? null : _buildDrawer(),
          appBar: isDesktop ? null : _buildAppBar(context),
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
      backgroundColor: AppColors.surface,
      elevation: 8,
      child: Sidebar(selected: selected, onPick: _pick, isInDrawer: true),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final primary = AppColors.primary;
    return AppBar(
      backgroundColor: primary,
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
            child: _buildSection(),
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
      case 'test_bookings':
        return const TestBookingsBlock();
      case 'plans':
        return const PlansBlock();
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => _saveTestPool(controllers),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onSurfaceInverse,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    for (final c in controllers.values) c.dispose();
  }

  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
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

// -------------------- Sidebar & Menu --------------------

class Sidebar extends StatelessWidget {
  final String selected;
  final void Function(String) onPick;
  final bool isInDrawer;
  const Sidebar({super.key, required this.selected, required this.onPick, this.isInDrawer = false});

  static const _menuItems = [
    (Icons.dashboard_rounded, 'Dashboard', 'dashboard'),
    (Icons.group_rounded, 'Users', 'users'),
    (Icons.event_available_rounded, 'Slots', 'slots'),
    (Icons.menu_book_rounded, 'Materials', 'materials'),
    (Icons.quiz_rounded, 'Tests', 'tests'),
    (Icons.book_online_rounded, 'Test Bookings', 'test_bookings'),
    (Icons.payment_rounded, 'Plans', 'plans'),
    (Icons.notifications_rounded, 'Notifications', 'notifications'),
    (Icons.settings_rounded, 'Settings', 'settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // Dark sidebar; use theme slate for background and inverse text for contrast
    return Container(
      decoration: BoxDecoration(color: AppColors.slate, border: Border(right: BorderSide(color: AppColors.divider, width: 0.6))),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const AppBrandingRow(logoSize: 40, nameSize: 18, spacing: 10, textColor: Colors.white),
                const SizedBox(height: 16),
                Divider(color: AppColors.onSurfaceInverse.withOpacity(0.18), height: 1),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  children: List.generate(_menuItems.length, (index) {
                    final item = _menuItems[index];
                    final isActive = selected == item.$3;
                    return _MenuItem(icon: item.$1, title: item.$2, isActive: isActive, onTap: () {
                      Navigator.maybePop(context);
                      onPick(item.$3);
                    });
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
  const _MenuItem({required this.icon, required this.title, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.primary;
    const inactiveColor = Colors.white;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? AppColors.brand.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(width: 3, color: isActive ? activeColor : Colors.transparent)),
        ),
        child: Row(children: [
          Icon(icon, color: isActive ? activeColor : inactiveColor, size: 20),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(fontWeight: FontWeight.w500, color: isActive ? activeColor : inactiveColor))
        ]),
      ),
    );
  }
}

// -------------------- Dashboard content --------------------

class _DashData {
  final int slotsTotal;
  final int instructorsActive;
  final int studentsActive;
  final double revenue; // rupees (may be fractional)
  const _DashData({required this.slotsTotal, required this.instructorsActive, required this.studentsActive, required this.revenue});
}

/// DashboardBlock is stateful so admin can pick range (7/30/90 days) via the revenue card
class DashboardBlock extends StatefulWidget {
  const DashboardBlock({super.key});
  @override
  State<DashboardBlock> createState() => _DashboardBlockState();
}

class _DashboardBlockState extends State<DashboardBlock> {
  int selectedDays = _kDefaultRevenueDays;

  @override
  void initState() {
    super.initState();
    // start client-side cleanup of old notifications when the dashboard loads
    // non-blocking: we don't await here because we want UI to show immediately
    _cleanupOldNotifications(daysToKeep: 30);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashData>(
      future: _fetchDashboardData(selectedDays),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Error: ${snapshot.error}')));
        }

        final d = snapshot.data!;
        final stats = {
          'slots': _formatNumber(d.slotsTotal),
          'instructors': _formatNumber(d.instructorsActive),
          'revenue': _humanCurrency(d.revenue),
          'students': _formatNumber(d.studentsActive),
        };

        return LayoutBuilder(builder: (context, c) {
          final isCompact = c.maxWidth < 720;
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header row — header text remains on left
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _DashboardHeader(),
                // small label showing current range (keeps header tidy)
                Text('Showing last $selectedDays days', style: TextStyle(fontSize: 13, color: AppColors.onSurfaceMuted)),
              ],
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String?>(
              valueListenable: _razorpayDebug,
              builder: (context, val, _) {
                if (val == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warnBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warnFg),
                    ),
                    child: Text('Razorpay: $val', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.warnFg)),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            // build the stats viewport and inject a custom RevenueCard into it
            // UPDATED: make stats and recent activities split the available space 1:1 (half each)
            Expanded(
              flex: 1,
              child: _StatsViewport(
                stats: stats,
                maxWidth: c.maxWidth,
                revenueTile: RevenueCard(
                  amountLabel: stats['revenue']!,
                  selectedDays: selectedDays,
                  onDaysChanged: (v) {
                    // change selectedDays and cause re-fetch
                    setState(() => selectedDays = v);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // UPDATED: give RecentActivities equal vertical space (half the page)
            Expanded(flex: 1, child: _RecentActivities(isCompact: isCompact)),
          ]);
        });
      },
    );
  }

  Future<_DashData> _fetchDashboardData(int days) async {
    final db = FirebaseFirestore.instance;

    final slotsTotalFuture = db.collection('slots').get().then((s) => s.size);
    final instructorsActiveFuture = db.collection('users').where('role', isEqualTo: 'instructor').where('status', isEqualTo: 'active').get().then((s) => s.size);
    final studentsActiveFuture = db.collection('users').where('role', isEqualTo: 'student').where('status', isEqualTo: 'active').get().then((s) => s.size);

    final razorpayFuture = _fetchRazorpayTotalFromHostinger(days: days);

    final results = await Future.wait<dynamic>([slotsTotalFuture, instructorsActiveFuture, studentsActiveFuture, razorpayFuture]);

    final slots = (results[0] as int?) ?? 0;
    final instructors = (results[1] as int?) ?? 0;
    final students = (results[2] as int?) ?? 0;
    final double revenue = (results[3] as double?) ?? 0.0;

    return _DashData(slotsTotal: slots, instructorsActive: instructors, studentsActive: students, revenue: revenue);
  }

  /// Client-side cleanup: delete notifications older than [daysToKeep]
  /// This runs once when DashboardBlock initializes. It deletes in batches
  /// to respect Firestore batch limits. Shows a SnackBar if any documents were deleted.
  Future<void> _cleanupOldNotifications({int daysToKeep = 30}) async {
    try {
      final cutoff = DateTime.now().toUtc().subtract(Duration(days: daysToKeep));
      final cutoffTs = Timestamp.fromDate(cutoff);

      final col = FirebaseFirestore.instance.collection('notifications');
      // Query documents older than cutoff. We limit to 1000 per run to be safe.
      final qSnap = await col.where('created_at', isLessThan: cutoffTs).limit(1000).get();
      final docs = qSnap.docs;
      if (docs.isEmpty) {
        debugPrint('Cleanup: no old notifications found.');
        return;
      }

      // Delete in batches of 400 to be safe (Firestore max 500 per batch).
      const int batchSize = 400;
      int deleted = 0;
      for (var i = 0; i < docs.length; i += batchSize) {
        final end = (i + batchSize < docs.length) ? i + batchSize : docs.length;
        final batch = FirebaseFirestore.instance.batch();
        for (var j = i; j < end; ++j) {
          batch.delete(docs[j].reference);
        }
        await batch.commit();
        deleted += (end - i);
      }

      debugPrint('Cleanup: deleted $deleted old notifications.');
      if (mounted && deleted > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted $deleted old notifications'), backgroundColor: Colors.green));
      }
    } catch (e, st) {
      debugPrint('Cleanup failed: $e\n$st');
      // Non-fatal: show a lightweight debug message in the banner
      if (mounted) {
        _razorpayDebug.value = 'Cleanup failed';
      }
    }
  }
}

class _StatsViewport extends StatelessWidget {
  final Map<String, String> stats;
  final double maxWidth;
  final Widget? revenueTile;
  const _StatsViewport({required this.stats, required this.maxWidth, this.revenueTile});

  @override
  Widget build(BuildContext context) {
    // If caller provided a custom revenueTile, use it; otherwise fallback to _StatCard
    final revenueWidget = revenueTile ??
        _StatCard(
          title: 'Total Revenue',
          value: stats['revenue']!,
          icon: Icons.attach_money,
        );

    final tiles = [
      _StatCard(title: 'Total Slots', value: stats['slots']!, icon: Icons.event_available),
      _StatCard(title: 'Active Instructors', value: stats['instructors']!, icon: Icons.person),
      // the revenue tile (custom or default)
      revenueWidget,
      _StatCard(title: 'Active Students', value: stats['students']!, icon: Icons.school),
    ];

    final bool narrow = maxWidth < 600;
    // UPDATED: Use 1:1 aspect for stat cards (square tiles)
    final double aspect = 1.0;
    // adjust maxExtent so squares look good across widths
    final double maxExtent = narrow ? (maxWidth / 2).clamp(120.0, 220.0) : 240.0;

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const AlwaysScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: maxExtent, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: aspect),
      itemCount: tiles.length,
      itemBuilder: (_, i) => tiles[i],
    );
  }
}

/// Revenue card with a cleaner filter button (outlined button + bottom sheet selector)
class RevenueCard extends StatelessWidget {
  final String amountLabel;
  final int selectedDays;
  final ValueChanged<int> onDaysChanged;

  const RevenueCard({
    required this.amountLabel,
    required this.selectedDays,
    required this.onDaysChanged,
  });

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top row: left = icon + badge, right = clean filter button
          Row(
            children: [
              Expanded(
                child: Row(children: [
                  Icon(Icons.attach_money, color: primary, size: 20),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: primary.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Revenue', style: TextStyle(fontSize: 12,color: AppColors.onSurface, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),

              // custom filter button
              _FilterButton(
                selectedDays: selectedDays,
                onSelected: onDaysChanged,
              ),
            ],
          ),

          // big amount
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(height: 8),
            Text(
              amountLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.onSurface),
            ),
          ]),
        ],
      ),
    );
  }
}

/// A cleaner filter button that shows selected range (7d/30d/90d) and uses a bottom sheet selector
class _FilterButton extends StatelessWidget {
  final int selectedDays;
  final ValueChanged<int> onSelected;

  const _FilterButton({
    required this.selectedDays,
    required this.onSelected,
  });

  String get _label {
    switch (selectedDays) {
      case 7:
        return "7d";
      case 30:
        return "30d";
      case 90:
        return "90d";
      default:
        return "$selectedDays d";
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: primary.withOpacity(0.25)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: () {
        showModalBottomSheet(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (ctx) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                const Text(
                  "Select Range",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Divider(),
                ListTile(
                  leading: selectedDays == 7 ? const Icon(Icons.check) : null,
                  title: const Text("Last 7 days"),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelected(7);
                  },
                ),
                ListTile(
                  leading: selectedDays == 30 ? const Icon(Icons.check) : null,
                  title: const Text("Last 30 days"),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelected(30);
                  },
                ),
                ListTile(
                  leading: selectedDays == 90 ? const Icon(Icons.check) : null,
                  title: const Text("Last 90 days"),
                  onTap: () {
                    Navigator.pop(ctx);
                    onSelected(90);
                  },
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        );
      },
      icon: const Icon(Icons.filter_list, size: 18),
      label: Text(
        _label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: primary,
        ),
      ),
    );
  }
}

// -------------------- Improved Recent Activities UI --------------------

// Helper to get chip color based on status
Color _statusColor(String status, BuildContext ctx) {
  final s = status.toLowerCase();
  if (s.contains('confirm') || s.contains('completed') || s.contains('paid')) return AppColors.okBg;
  if (s.contains('fail') || s.contains('cancel') || s.contains('rejected')) return AppColors.errBg;
  if (s.contains('notification')) return AppColors.info.withOpacity(0.08);
  return AppColors.neuBg;
}

Color _statusTextColor(String status) {
  final s = status.toLowerCase();
  if (s.contains('confirm') || s.contains('completed') || s.contains('paid')) return AppColors.okFg;
  if (s.contains('fail') || s.contains('cancel') || s.contains('rejected')) return AppColors.errFg;
  if (s.contains('notification')) return AppColors.info;
  return AppColors.onSurfaceMuted;
}

class _RecentActivities extends StatefulWidget {
  final bool isCompact;
  const _RecentActivities({required this.isCompact});

  @override
  State<_RecentActivities> createState() => _RecentActivitiesState();
}

class _RecentActivitiesState extends State<_RecentActivities> {
  String _search = '';
  String _statusFilter = 'all';

  // userId -> userName cache to avoid repeated lookups
  final Map<String, String> _userNames = {};

  Future<String> _getUserName(String userId) async {
    if (userId.isEmpty || userId == '-') return '-';
    if (_userNames.containsKey(userId)) return _userNames[userId]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final data = doc.data();
      final name = (data != null && data['name'] != null && data['name'].toString().trim().isNotEmpty) ? data['name'].toString() : userId;
      _userNames[userId] = name;
      return name;
    } catch (e) {
      // fallback to id on error
      _userNames[userId] = userId;
      return userId;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header with title, search and filter
      Row(
        children: [
          Expanded(child: Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.onSurface))),
          const SizedBox(width: 12),
          // small search field
          SizedBox(
            width: widget.isCompact ? 150 : 220,
            child: TextField(
              onChanged: (v) => setState(() => _search = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search student/type/message',
                hintStyle: TextStyle(color: AppColors.onSurfaceFaint),
                prefixIcon: Icon(Icons.search, size: 18, color: AppColors.onSurfaceMuted),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // status filter menu
          PopupMenuButton<String>(
            tooltip: 'Filter status',
            onSelected: (v) => setState(() => _statusFilter = v),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'all', child: Text('All Statuses')),
              const PopupMenuItem(value: 'confirmed', child: Text('Confirmed')),
              const PopupMenuItem(value: 'pending', child: Text('Pending')),
              const PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
              const PopupMenuItem(value: 'notification', child: Text('Notifications')),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined, size: 18, color: AppColors.onSurfaceMuted),
                  const SizedBox(width: 8),
                  Text(
                    _statusFilter == 'all' ? 'Status' : _statusFilter[0].toUpperCase() + _statusFilter.substring(1),
                    style: TextStyle(color: AppColors.onSurfaceMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          // merged stream (bookings + admin_notifications)
          stream: _mergedActivitiesStream(limit: 200),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return Text('Failed to load activities: ${snapshot.error}');
            final combined = snapshot.data ?? <Map<String, dynamic>>[];

            // apply client-side search + status filters
            var activities = combined;
            if (_search.isNotEmpty) {
              final q = _search.toLowerCase();
              activities = activities.where((b) {
                final student = ((b['student_name'] ?? b['userName'] ?? b['user_id'] ?? b['user_id_raw']) ?? '').toString().toLowerCase();
                final activity = (b['activity_type'] ?? '').toString().toLowerCase();
                final message = (b['message'] ?? b['title'] ?? b['note'] ?? '').toString().toLowerCase();
                return student.contains(q) || activity.contains(q) || message.contains(q);
              }).toList();
            }

            if (_statusFilter != 'all') {
              activities = activities.where((b) {
                final s = (b['status'] ?? b['type'] ?? '').toString().toLowerCase();
                return s.contains(_statusFilter.toLowerCase());
              }).toList();
            }

            if (activities.isEmpty) return Center(child: Text('No recent activities', style: TextStyle(color: AppColors.onSurfaceMuted)));

            // Compact/mobile: vertical ListTiles
            if (widget.isCompact) {
              return ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: activities.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                itemBuilder: (_, i) {
                  final b = activities[i];
                  final createdAt = (b['createdAt'] is Timestamp) ? (b['createdAt'] as Timestamp).toDate() : (b['created_at'] is Timestamp) ? (b['created_at'] as Timestamp).toDate() : null;
                  final userId = (b['userId'] ?? b['student_id'] ?? b['user_id'] ?? '-').toString();
                  // compute activityType using the heuristic
                  final activityType = (b['activity_type'] ?? _inferActivityType(b)).toString();
                  // If it's a registration, set status to Completed
                  String status = (b['status'] ?? b['type'] ?? '-').toString();
                  if (activityType.toLowerCase() == 'registration') status = 'Completed';

                  final userNameCached = b['userName'] as String?; // may already be present for notifications

                  return FutureBuilder<String>(
                    future: userNameCached != null ? Future.value(userNameCached) : _getUserName(userId),
                    builder: (ctx, snap) {
                      final userName = snap.data ?? (b['userName'] ?? userId);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.neuBg,
                          child: _leadingContentForActivity(b, userName, '' /* no slot shown */),
                        ),
                        title: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(userName, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                            const SizedBox(height: 4),
                            Text(activityType, style: TextStyle(fontSize: 12, color: AppColors.onSurfaceMuted)),
                          ],
                        ),
                        subtitle: _subtitleForActivity(b, createdAt),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _statusColor(status, context),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(status, style: TextStyle(color: _statusTextColor(status), fontWeight: FontWeight.w600)),
                        ),
                        onTap: () {
                          // Optional: show booking/notification details
                        },
                      );
                    },
                  );
                },
              );
            }

            // Desktop/wide: header + aligned rows with alternating background
            return Column(
              children: [
                // Header row (slot column removed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.divider)),
                  ),
                  child: Row(
                    children: [
                      // Removed slot column here
                      Expanded(child: Text('Student / Source', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted))),
                      SizedBox(width: 220, child: Text('Date', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted))),
                      SizedBox(width: 160, child: Text('Activity', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted))),
                      SizedBox(width: 120, child: Text('Status', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.onSurfaceMuted))),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: activities.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (ctx, i) {
                      final b = activities[i];
                      final createdAt = (b['createdAt'] is Timestamp) ? (b['createdAt'] as Timestamp).toDate() : (b['created_at'] is Timestamp) ? (b['created_at'] as Timestamp).toDate() : null;
                      final userId = (b['userId'] ?? b['student_id'] ?? b['user_id'] ?? '-').toString();
                      final activityType = (b['activity_type'] ?? _inferActivityType(b)).toString();

                      // For registration activities, make status 'Completed'
                      String status = (b['status'] ?? b['type'] ?? '-').toString();
                      if (activityType.toLowerCase() == 'registration') status = 'Completed';

                      final bgColor = i.isEven ? AppColors.surface : AppColors.background;
                      final userNameCached = b['userName'] as String?;

                      return FutureBuilder<String>(
                        future: userNameCached != null ? Future.value(userNameCached) : _getUserName(userId),
                        builder: (ctx, snap) {
                          final userName = snap.data ?? (b['userName'] ?? userId);
                          return InkWell(
                            onTap: () {
                              // optional: open booking/notification details
                            },
                            child: Container(
                              color: bgColor,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              child: Row(
                                children: [
                                  // leading avatar + student name (slot column removed)
                                  Row(children: [
                                    CircleAvatar(radius: 18, backgroundColor: AppColors.neuBg, child: _leadingContentForActivity(b, userName, '')),
                                    const SizedBox(width: 8),
                                    SizedBox(width: 16),
                                  ]),
                                  Expanded(child: Text(userName, style: TextStyle(fontSize: 14, color: AppColors.onSurface))),
                                  SizedBox(width: 220, child: Text(createdAt != null ? createdAt.toString().split('.').first : '-', style: TextStyle(color: AppColors.onSurfaceMuted))),
                                  SizedBox(width: 160, child: Text(activityType, style: TextStyle(color: AppColors.onSurfaceMuted))),
                                  SizedBox(
                                    width: 120,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status, context),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(status, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: _statusTextColor(status))),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ]);
  }

  // Small helper: create leading widget content for activity (notification uses bell)
  Widget _leadingContentForActivity(Map<String, dynamic> b, String userName, String slotId) {
    final isNotification = ((b['source'] ?? b['type'] ?? b['activity_type'])?.toString().toLowerCase() ?? '').contains('notif') ||
        (b['isNotification'] == true) ||
        (b['type'] == 'new_student_registration') ||
        (b['type'] == 'new_instructor_registration');

    if (isNotification) {
      return Icon(Icons.notifications, size: 16, color: AppColors.info);
    }
    // otherwise initials
    final initials = _shortLabel(userName, slotId);
    return Text(initials, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurface));
  }

  Widget _subtitleForActivity(Map<String, dynamic> b, DateTime? createdAt) {
    if ((b['type'] ?? '').toString().toLowerCase().contains('registration') || (b['isNotification'] == true) || (b['type']?.toString().toLowerCase() == 'notification')) {
      final title = b['title'] ?? b['message'] ?? b['note'] ?? '';
      return Text(title.toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.onSurfaceMuted));
    }
    // booking-like
    return Text(createdAt != null ? createdAt.toString().split('.').first : '-', style: TextStyle(color: AppColors.onSurfaceMuted));
  }

  // Very small heuristic to label the type of activity. Adjust to match your schema.
  // UPDATED: return 'Registration' for new registrations (student/instructor/registration)
  String _inferActivityType(Map<String, dynamic> b) {
    final t = ((b['type'] ?? '') as String).toLowerCase();
    if (t.contains('student') || t.contains('instructor') || t.contains('registration')) return 'Registration';
    if (b.containsKey('payment_id') || b.containsKey('amount')) return 'Payment';
    if (b.containsKey('slot_id') && (b.containsKey('user_id') || b.containsKey('student_id'))) return 'Booking';
    if (b.containsKey('action')) return b['action'].toString();
    final s = (b['status'] ?? '').toString();
    if (s.isNotEmpty) return 'Booking - ${s[0].toUpperCase()}${s.substring(1)}';
    return 'Activity';
  }

  String _shortLabel(String studentId, String slotId) {
    final s = (studentId.isNotEmpty && studentId != '-') ? studentId : slotId;
    final parts = s.split(RegExp(r'\s+|[_\-]'));
    if (parts.isEmpty) return s.length > 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    final initials = parts.take(2).map((p) => p.isNotEmpty ? p[0].toUpperCase() : '').join();
    return initials.isNotEmpty ? initials : (s.length > 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase());
  }
}

// -------------------- Shared UI helpers --------------------

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _StatCard({required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.divider), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        // Only single left icon — removed top-right mini icon as requested
        Icon(icon, color: primary, size: 20),
        const SizedBox(height: 6),
        Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: AppColors.onSurfaceMuted)),
      ]),
    );
  }
}

class _CardSurface extends StatelessWidget {
  final Widget child;
  const _CardSurface({required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: Offset(0, 4))]), child: child);
  }
}

String _formatNumber(num? number) {
  final n = number ?? 0;
  final s = n.toString();
  return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
}

Widget _kv(String k, String v) {
  return Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [SizedBox(width: 110, child: Text(k, style: TextStyle(color: AppColors.onSurfaceMuted))), const SizedBox(width: 8), Expanded(child: Text(v, style: TextStyle(fontWeight: FontWeight.w500, color: AppColors.onSurface)))]));
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();
  @override
  Widget build(BuildContext context) {
    return Text("Dashboard Overview", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface));
  }
}

// -------------------- Networking helper --------------------

/// Calls Hostinger endpoint and returns total in rupees as double.
/// Uses `mode=payments` and adds from/to for the last [days] days.
/// Sets _razorpayDebug with an error message on failure (or clears it on success).
Future<double?> _fetchRazorpayTotalFromHostinger({int days = _kDefaultRevenueDays}) async {
  try {
    if (_kRazorpayEndpoint.isEmpty) {
      _razorpayDebug.value = 'Endpoint not configured';
      debugPrint('RZ: endpoint empty');
      return null;
    }

    // compute UNIX timestamps in seconds (UTC)
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final fromSec = nowSec - (days * 24 * 3600);

    final uri = Uri.parse('$_kRazorpayEndpoint?mode=payments&from=$fromSec&to=$nowSec');
    debugPrint('RZ: requesting $uri');

    final resp = await http.get(uri, headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 20));

    debugPrint('RZ: status ${resp.statusCode}');
    debugPrint('RZ: body ${resp.body}');

    if (resp.statusCode != 200) {
      _razorpayDebug.value = 'HTTP ${resp.statusCode}';
      return null;
    }

    final Map<String, dynamic> data = jsonDecode(resp.body);

    if (data['ok'] != true) {
      // show server-returned error (unauthorized/server_error/etc)
      final err = data['error'] ?? 'server_error';
      final detail = data['detail'] ?? '';
      _razorpayDebug.value = '$err ${detail.isNotEmpty ? ": $detail" : ""}';
      debugPrint('RZ: ok != true -> ${resp.body}');
      return null;
    }

    final dynamic totalVal = data['total'];
    if (totalVal == null) {
      _razorpayDebug.value = 'Response missing total';
      debugPrint('RZ: total missing -> ${resp.body}');
      return null;
    }

    double totalNum;
    if (totalVal is num) {
      totalNum = (totalVal).toDouble();
    } else if (totalVal is String) {
      totalNum = double.tryParse(totalVal) ?? 0.0;
    } else {
      totalNum = 0.0;
    }

    _razorpayDebug.value = null; // clear debug on success
    return totalNum;
  } on FormatException catch (e) {
    _razorpayDebug.value = 'Invalid JSON';
    debugPrint('RZ: JSON error ${e.message}');
    return null;
  } catch (e, st) {
    _razorpayDebug.value = 'Network error';
    debugPrint('RZ: fetch error: $e\n$st');
    return null;
  }
}

// -------------------- Helpers for human-friendly currency --------------------

String _humanCurrency(double amount) {
  // amount is rupees
  if (amount >= 1e12) return '₹' + (amount / 1e12).toStringAsFixed(2) + 'T';
  if (amount >= 1e7) return '₹' + (amount / 1e7).toStringAsFixed(2) + 'Cr';
  if (amount >= 1e5) return '₹' + (amount / 1e5).toStringAsFixed(2) + 'L';
  if (amount >= 1000) return '₹' + _formatNumber(amount.round());
  return '₹' + amount.toStringAsFixed(2);
}

// -------------------- NEW: merge bookings + admin_notifications into one stream --------------------

// Returns a broadcast stream that merges `bookings` (ordered by created_at desc)
// and `admin_notifications` (ordered by createdAt desc), normalizes fields and
// emits a combined sorted list on any update. Each emitted item is a Map with
// consistent keys (createdAt Timestamp, status/type, activity_type, userId, slot_id, title/message, etc).
Stream<List<Map<String, dynamic>>> _mergedActivitiesStream({int limit = 200}) {
  final controller = StreamController<List<Map<String, dynamic>>>.broadcast();
  // Keep latest snapshots in memory
  List<Map<String, dynamic>> latestBookings = [];
  List<Map<String, dynamic>> latestNotifs = [];

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? bookSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? notifSub;

  void emitCombined() {
    final combined = <Map<String, dynamic>>[];
    combined.addAll(latestBookings);
    combined.addAll(latestNotifs);
    // sort by createdAt/created_at timestamp descending
    combined.sort((a, b) {
      Timestamp? ta = (a['createdAt'] as Timestamp?) ?? (a['created_at'] as Timestamp?);
      Timestamp? tb = (b['createdAt'] as Timestamp?) ?? (b['created_at'] as Timestamp?);
      final da = ta?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      final db = tb?.toDate() ?? DateTime.fromMillisecondsSinceEpoch(0);
      return db.compareTo(da);
    });
    // enforce limit
    final limited = combined.take(limit).toList();
    if (!controller.isClosed) controller.add(limited);
  }

  bookSub = FirebaseFirestore.instance
      .collection('bookings')
      .orderBy('created_at', descending: true)
      .limit(limit)
      .snapshots()
      .listen((snap) {
    latestBookings = snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      // normalize keys: ensure createdAt present as Timestamp under 'created_at' (bookings use created_at)
      if (!m.containsKey('created_at') && m.containsKey('createdAt')) {
        m['created_at'] = m['createdAt'];
      }
      m['__source'] = 'booking';
      // also preserve doc id
      m['docId'] = d.id;
      return m;
    }).toList();
    emitCombined();
  }, onError: (e) {
    if (!controller.isClosed) controller.addError(e);
  });

  notifSub = FirebaseFirestore.instance
      .collection('admin_notifications')
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .listen((snap) {
    latestNotifs = snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      // normalize: notifications may use 'createdAt' - keep that
      if (!m.containsKey('createdAt') && m.containsKey('created_at')) {
        m['createdAt'] = m['created_at'];
      }
      // mark as notification and include standardized fields
      m['__source'] = 'notification';
      m['type'] = m['type'] ?? 'notification';
      // userId might be userId or user_id depending on how you saved it
      if (m.containsKey('userId')) {
        m['userId'] = m['userId'];
      } else if (m.containsKey('user_id')) {
        m['userId'] = m['user_id'];
      } else if (m.containsKey('uid')) {
        m['userId'] = m['uid'];
      }
      // keep userName if available
      if (m.containsKey('userName')) {
        // nothing
      } else if (m.containsKey('user_name')) {
        m['userName'] = m['user_name'];
      } else if (m.containsKey('name')) {
        m['userName'] = m['name'];
      }
      // doc id
      m['docId'] = d.id;
      // helpful flag
      m['isNotification'] = true;
      return m;
    }).toList();
    emitCombined();
  }, onError: (e) {
    if (!controller.isClosed) controller.addError(e);
  });

  controller.onCancel = () async {
    await bookSub?.cancel();
    await notifSub?.cancel();
    if (!controller.isClosed) await controller.close();
  };

  return controller.stream;
}
