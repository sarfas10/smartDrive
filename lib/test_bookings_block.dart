// lib/test_bookings_block.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:smart_drive/theme/app_theme.dart';
import 'package:smart_drive/ui_common.dart';

class TestBookingsBlock extends StatefulWidget {
  const TestBookingsBlock({super.key});

  @override
  State<TestBookingsBlock> createState() => _TestBookingsBlockState();
}

class _TestBookingsBlockState extends State<TestBookingsBlock> with SingleTickerProviderStateMixin {
  final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('test_bookings');

  late TabController _tabController;
  // Only two tabs now: pending and confirmed
  final List<String> _tabs = ['pending', 'confirmed'];

  // Search
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {}); // rebuild when tab changes
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(() {}); // safe no-op
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _prettyDate(DateTime? d) {
    if (d == null) return '-';
    try {
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {
      return d.toIso8601String();
    }
  }

  void _onSearchChanged(String v) => setState(() => _query = v.trim().toLowerCase());

  /// Generic status update helper (keeps existing behaviour for simple updates)
  Future<void> _setStatus(String id, String status, {DateTime? date}) async {
    try {
      final updateData = <String, dynamic>{
        'status': status,
        'updated_at': FieldValue.serverTimestamp(),
      };
      if (date != null) {
        updateData['date'] = Timestamp.fromDate(DateTime(date.year, date.month, date.day));
      }
      await _col.doc(id).update(updateData);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status set to "$status"')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  Future<void> _markUserTestAttempted(String userId) async {
    try {
      final usersCol = FirebaseFirestore.instance.collection('users');
      await usersCol.doc(userId).update({'test_attempted': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update user: $e')),
        );
      }
    }
  }

  /// Confirm booking from admin:
  /// - sets status = 'confirmed'
  /// - sets rescheduled flag (true if this is a reschedule)
  /// - optionally updates date (for reschedule)
  ///
  /// Also:
  /// - creates a user_notification document when a userId exists
  /// - uses a WriteBatch so booking + user update + notification are committed together
  Future<void> _confirmBooking(String id, {bool rescheduled = false, DateTime? date}) async {
    final bookingsCol = _col; // 'test_bookings'
    final usersCol = FirebaseFirestore.instance.collection('users');
    final notificationsCol = FirebaseFirestore.instance.collection('user_notification');
    final adminUid = FirebaseAuth.instance.currentUser?.uid;

    try {
      // Read booking doc to determine user ID and existing date (so we can archive previous date if needed)
      final bookingSnap = await bookingsCol.doc(id).get();
      if (!bookingSnap.exists) throw 'Booking document not found';

      final bookingData = bookingSnap.data() ?? <String, dynamic>{};
      final userId = bookingData['user_id'] ?? bookingData['userId'];

      // Build update map for booking
      final updateData = <String, dynamic>{
        'status': 'confirmed',
        'rescheduled': rescheduled,
        'updated_at': FieldValue.serverTimestamp(),
      };

      // If a new date is provided, normalise it (midnight) and include in update.
      if (date != null) {
        final normalized = DateTime(date.year, date.month, date.day);
        updateData['date'] = Timestamp.fromDate(normalized);

        // If there's an existing date and it's different, append it to previous_dates array.
        // We append the old date as a Timestamp so history is queryable.
        final existingDateRaw = bookingData['date'];
        Timestamp? existingTs;
        if (existingDateRaw is Timestamp) {
          existingTs = existingDateRaw;
        } else if (existingDateRaw is Map && existingDateRaw.containsKey('_seconds')) {
          try {
            final seconds = existingDateRaw['_seconds'] as int;
            existingTs = Timestamp(seconds, existingDateRaw['_nanoseconds'] ?? 0);
          } catch (_) {}
        } else if (existingDateRaw is String) {
          try {
            final parsed = DateTime.parse(existingDateRaw);
            existingTs = Timestamp.fromDate(DateTime(parsed.year, parsed.month, parsed.day));
          } catch (_) {}
        }

        // Append only if existingTs is present and different from the new normalized date
        if (existingTs != null) {
          final existingDt = existingTs.toDate();
          final existingNormalized = DateTime(existingDt.year, existingDt.month, existingDt.day);
          if (existingNormalized != DateTime(date.year, date.month, date.day)) {
            // we'll include this with FieldValue.arrayUnion in the batch below
          } else {
            // same day -> no need to push into previous_dates
            existingTs = null;
          }
        }

        // Note: we don't modify updateData for previous_dates here; handle it in the batch using existingTs
      }

      // Prepare notification payload
      String title = rescheduled ? 'Test Rescheduled' : 'Booking Confirmed';
      String formattedDate = date != null ? DateFormat.yMMMd().format(date) : '';
      String message;
      if (rescheduled && date != null) {
        message = 'Your test has been rescheduled to $formattedDate. Please arrive on time.';
      } else {
        message = 'Your booking has been confirmed. Please follow further instructions.';
      }

      // Start a write batch to do all updates atomically
      final batch = FirebaseFirestore.instance.batch();

      // Update booking
      batch.update(bookingsCol.doc(id), updateData);

      // If we decided to archive an old date, add arrayUnion to booking doc
      if (date != null) {
        final existingDateRaw = bookingData['date'];
        Timestamp? existingTs;
        if (existingDateRaw is Timestamp) {
          existingTs = existingDateRaw;
        } else if (existingDateRaw is Map && existingDateRaw.containsKey('_seconds')) {
          try {
            final seconds = existingDateRaw['_seconds'] as int;
            final nanos = existingDateRaw['_nanoseconds'] ?? 0;
            existingTs = Timestamp(seconds, nanos);
          } catch (_) {}
        } else if (existingDateRaw is String) {
          try {
            final parsed = DateTime.parse(existingDateRaw);
            existingTs = Timestamp.fromDate(DateTime(parsed.year, parsed.month, parsed.day));
          } catch (_) {}
        }
        if (existingTs != null) {
          final existingDt = existingTs.toDate();
          final existingNormalized = DateTime(existingDt.year, existingDt.month, existingDt.day);
          final newNormalized = DateTime(date.year, date.month, date.day);
          if (existingNormalized != newNormalized) {
            batch.update(bookingsCol.doc(id), {
              'previous_dates': FieldValue.arrayUnion([existingTs]),
            });
          }
        }
      }

      // Update user doc if available
      if (userId != null) {
        batch.update(usersCol.doc(userId.toString()), {'test_attempted': true});
        // Create notification doc targeted to user
        final notifDoc = notificationsCol.doc(); // auto-id
        batch.set(notifDoc, <String, dynamic>{
          'action_url': null,
          'created_at': FieldValue.serverTimestamp(),
          'delivered_at': null,
          'delivered_by': adminUid,
          'message': message,
          'read': false,
          'title': title,
          'uid': userId.toString(),
        });
      } else {
        // If there is no userId, skip user update and notification.
      }

      // Commit batch
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking confirmed')));
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to confirm: $e')));
      }
    }
  }

  /// Reschedule flow: pick a date, then mark booking as confirmed + rescheduled
  Future<void> _rescheduleFlow(BuildContext ctx, String id, DateTime? current) async {
    try {
      // If the current booking date is in the past, we must not use it as initialDate (DatePicker requires initialDate >= firstDate)
      final now = DateTime.now();
      DateTime initial = current ?? now;
      if (initial.isBefore(DateTime(now.year, now.month, now.day))) {
        initial = now;
      }

      final picked = await showDatePicker(
        context: ctx,
        initialDate: initial,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (c, child) => Theme(
          data: Theme.of(c).copyWith(colorScheme: Theme.of(c).colorScheme),
          // protect against child being null
          child: child ?? const SizedBox.shrink(),
        ),
      );

      if (picked != null) {
        await _confirmBooking(id, rescheduled: true, date: picked);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to reschedule: $e')));
      }
    }
  }

  /// Manual refresh helper (used by RefreshIndicator)
  Future<void> _manualRefresh() async {
    try {
      await _col.limit(1).get();
      await Future<void>.delayed(const Duration(milliseconds: 350));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final mq = MediaQuery.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header with improved overflow handling (dropdown + search)
        Container(
          color: primary,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Test Booking Management',
                  style: AppText.sectionTitle.copyWith(color: AppColors.onSurfaceInverse)),
              const SizedBox(height: 10),

              // header row: dropdown (pending/confirmed + counts) + search
              LayoutBuilder(builder: (context, headerConstraints) {
                final maxSearch = headerConstraints.maxWidth < 600 ? 160.0 : 320.0;
                return SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      // Live counts via StreamBuilder, shown inside a Dropdown
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _col.snapshots(),
                        builder: (context, snap) {
                          int pendingCount = 0;
                          int confirmedCount = 0;
                          if (snap.hasData) {
                            final docs = snap.data!.docs;
                            for (final d in docs) {
                              final m = d.data();
                              final s = (m['status'] as String?)?.toLowerCase();
                              final paid = m['paid_amount'];
                              final fallback = (paid is num && paid > 0) ? 'confirmed' : 'pending';
                              final status = s ?? fallback;
                              if (status == 'pending') pendingCount++;
                              if (status == 'confirmed') confirmedCount++;
                            }
                          }
                          final selectedIndex = _tabController.index;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child:DropdownButton<int>(
                              value: selectedIndex,
                              underline: const SizedBox.shrink(),
                              // menu background when expanded
                              dropdownColor: AppColors.surface,
                              // caret/icon color when collapsed
                              iconEnabledColor: AppColors.onSurfaceInverse,
                              // style applied to the currently selected item (collapsed state)
                              style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse),
                              isDense: true,
                              items: [
                                DropdownMenuItem(
                                  value: 0,
                                  child: Text('Pending ($pendingCount)',
                                      style: AppText.tileSubtitle.copyWith(color: const Color.fromARGB(255, 241, 95, 95))),
                                ),
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('Confirmed ($confirmedCount)',
                                      style: AppText.tileSubtitle.copyWith(color: const Color.fromARGB(255, 8, 133, 19))),
                                ),
                              ],
                              // Force the collapsed/selected widget to use the same visible style
                              selectedItemBuilder: (context) => <Widget>[
                                Text('Pending ($pendingCount)',
                                    style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
                                Text('Confirmed ($confirmedCount)',
                                    style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse)),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                _tabController.animateTo(v);
                              },
                            ),

                          );
                        },
                      ),

                      const SizedBox(width: 12),

                      // search (constrained)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxSearch, minWidth: 100),
                        child: SizedBox(
                          height: 40,
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _onSearchChanged,
                            style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, color: Colors.white70),
                              hintText: 'Search name / id / date',
                              hintStyle: AppText.tileSubtitle.copyWith(color: Colors.white70),
                              filled: true,
                              fillColor: Colors.white24,
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(AppRadii.s),
                                  borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),

        // Cards list
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _col.orderBy('created_at', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Error: ${snap.error}'));
              }

              final docs = snap.data?.docs ?? [];
              final bookings = docs.map((d) => _CardModel.fromDoc(d)).toList();

              // Filter by active "tab" (pending / confirmed)
              final activeTab = _tabs[_tabController.index];
              List<_CardModel> tabFiltered = bookings.where((b) => b.status == activeTab).toList();

              // client-side search
              final visible = tabFiltered.where((b) {
                if (_query.isEmpty) return true;
                final hay = [
                  b.displayName ?? '',
                  b.userId ?? '',
                  b.testTypes.join(' '),
                  b.dateString,
                ].join(' ').toLowerCase();
                return hay.contains(_query);
              }).toList();

              if (visible.isEmpty) {
                return Center(child: Text('No bookings', style: AppText.tileSubtitle));
              }

              return LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth;
                final int columns = width >= 1100 ? 3 : (width >= 760 ? 2 : 1);

                if (columns == 1) {
                  return RefreshIndicator(
                    onRefresh: _manualRefresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) => _BookingCard(
                        model: visible[i],
                        compact: true,
                        onConfirm: () => _confirmBooking(visible[i].id, rescheduled: false),
                        onReschedule: () => _rescheduleFlow(context, visible[i].id, visible[i].date),
                        onViewDetails: () => _showDetailDialog(context, visible[i]),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _manualRefresh,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: columns == 2 ? 3.0 : 2.6,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final b = visible[index];
                      return _BookingCard(
                        model: b,
                        compact: false,
                        onConfirm: () => _confirmBooking(b.id, rescheduled: false),
                        onReschedule: () => _rescheduleFlow(context, b.id, b.date),
                        onViewDetails: () => _showDetailDialog(context, b),
                      );
                    },
                  ),
                );
              });
            },
          ),
        ),
      ],
    );
  }

  void _showDetailDialog(BuildContext ctx, _CardModel b) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(b.displayName ?? b.userId ?? 'Booking'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info
              if (b.userId != null) _kv('User ID', b.userId!),
              if (b.displayName != null) _kv('Name', b.displayName!),
              if (b.email != null) _kv('Email', b.email!),
              if (b.phone != null) _kv('Phone', b.phone!),

              _kv('Requested Date', _prettyDate(b.date)),
              _kv('Test Types', b.testTypes.join(', ')),
              if (b.totalPrice != null) _kv('Total (₹)', b.totalPrice.toString()),
              if (b.paidAmount != null) _kv('Paid (₹)', b.paidAmount.toString()),
              if (b.razorpayOrderId != null) _kv('Razorpay Order ID', b.razorpayOrderId!),
              if (b.charges != null && b.charges!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Charges', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ...b.charges!.entries.map((e) => _kv(e.key, '₹${e.value}')).toList(),
              ],

              if (b.payment != null && b.payment!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Payment Info', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ..._flattenPaymentMap(b.payment!).map((p) => _kv(p.key, p.value)).toList(),
              ],

              if (b.specialRequests != null && b.specialRequests!.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Additional Requests', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(b.specialRequests!),
              ],

              const SizedBox(height: 8),
              _kv('Created at', b.createdAtString),
              if (b.updatedAtString.isNotEmpty) _kv('Updated at', b.updatedAtString),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          // VIEW RAW JSON option removed as requested
        ],
      ),
    );
  }

  /// Flatten nested payment maps to list of key/value for display
  List<MapEntry<String, String>> _flattenPaymentMap(Map<String, dynamic> m, [String prefix = '']) {
    final out = <MapEntry<String, String>>[];
    m.forEach((k, v) {
      final key = prefix.isEmpty ? k : '$prefix.$k';
      if (v is Map) {
        out.addAll(_flattenPaymentMap(Map<String, dynamic>.from(v), key));
      } else if (v is List) {
        out.add(MapEntry(key, v.join(', ')));
      } else {
        out.add(MapEntry(key, v?.toString() ?? ''));
      }
    });
    return out;
  }

  /// Show raw document JSON (pretty printed) for debugging
  Future<void> _showRawJson(BuildContext ctx, String docId) async {
    try {
      final snap = await _col.doc(docId).get();
      if (!snap.exists) {
        if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Document not found')));
        return;
      }
      final data = snap.data() ?? <String, dynamic>{};
      final pretty = const JsonEncoder.withIndent('  ').convert(data);

      if (!mounted) return;
      showDialog(
        context: ctx,
        builder: (_) => AlertDialog(
          title: Text('Raw document: $docId'),
          content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: SelectableText(pretty))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Failed to load raw doc: $e')));
    }
  }

  String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}

/// Live tab pill (no longer used in header dropdown, kept for reuse)
class _LiveTabPill extends StatelessWidget {
  final TabController controller;
  final int index;
  final String label;
  final CollectionReference<Map<String, dynamic>> collection;

  const _LiveTabPill({
    required this.controller,
    required this.index,
    required this.label,
    required this.collection,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final selected = controller.index == index;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: collection.snapshots(),
      builder: (context, snap) {
        int count = 0;
        if (snap.hasData) {
          final docs = snap.data!.docs;
          final key = label.toLowerCase();
          count = docs.where((d) {
            final m = d.data();
            final s = (m['status'] as String?)?.toLowerCase();
            final paid = m['paid_amount'];
            final fallback = (paid is num && paid > 0) ? 'confirmed' : 'pending';
            final status = s ?? fallback;
            return status == key;
          }).length;
        }

        final bg = selected ? Colors.white.withOpacity(0.12) : Colors.transparent;
        final border = selected ? Border(bottom: BorderSide(color: Colors.white, width: 3)) : null;

        return InkWell(
          onTap: () => controller.animateTo(index),
          child: Container(
            decoration: BoxDecoration(color: bg, border: border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              '$label${count > 0 ? " ($count)" : ""}',
              style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceInverse, fontWeight: FontWeight.w600),
            ),
          ),
        );
      },
    );
  }
}

/// Compact/expanded booking card used in list & grid.
/// - compact: single-column small device style
/// - expanded: richer layout for tablet/desktop
class _BookingCard extends StatelessWidget {
  final _CardModel model;
  final bool compact;
  final VoidCallback onConfirm;
  final VoidCallback onReschedule;
  final VoidCallback onViewDetails;

  const _BookingCard({
    required this.model,
    required this.compact,
    required this.onConfirm,
    required this.onReschedule,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    // card container
    final card = Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.m),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // title + status (status is small badge)
            Row(
              children: [
                Expanded(
                  child: Text(model.displayName ?? model.userId ?? 'Unknown',
                      style: AppText.tileTitle.copyWith(fontSize: compact ? 16 : 18, fontWeight: FontWeight.w800)),
                ),
                StatusBadge(text: (model.status.isEmpty ? 'Pending' : model.status.toUpperCase()), type: model.status),
              ],
            ),
            const SizedBox(height: 8),

            // contact row: use Flexible so long email / phone don't overflow
            Row(
              children: [
                if (model.email != null) ...[
                  const Icon(Icons.email_outlined, size: 16, color: AppColors.onSurfaceMuted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(model.email!, style: AppText.tileSubtitle, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 12),
                ],
                if (model.phone != null) ...[
                  const Icon(Icons.phone_outlined, size: 16, color: AppColors.onSurfaceMuted),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(model.phone!, style: AppText.tileSubtitle, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            const Divider(color: AppColors.divider),
            const SizedBox(height: 10),

            // date row
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.onSurfaceMuted),
                const SizedBox(width: 8),
                Expanded(child: Text('Requested: ${model.dateString}', style: AppText.tileSubtitle)),
              ],
            ),
            const SizedBox(height: 8),

            // chips row
            Row(
              children: [
                const Icon(Icons.directions_car_filled, size: 16, color: AppColors.onSurfaceMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: model.testTypes.map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(t, style: AppText.tileSubtitle.copyWith(color: primary)),
                      );
                    }).toList(),
                  ),
                )
              ],
            ),
            const SizedBox(height: 10),

            // totals / order id row - make order id flexible to avoid overflow
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Total:', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(model.totalPrice != null ? '₹${model.totalPrice}' : '-', style: AppText.tileSubtitle),
                const SizedBox(width: 16),
                Text('Paid:', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 8),
                Text(model.paidAmount != null ? '₹${model.paidAmount}' : '-', style: AppText.tileSubtitle),
                if (model.razorpayOrderId != null) ...[
                  const SizedBox(width: 12),
                  Text('Order:', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 6),
                  Flexible(child: Text(model.razorpayOrderId!, overflow: TextOverflow.ellipsis, style: AppText.hintSmall)),
                ],
              ],
            ),
            const SizedBox(height: 10),

            // special requests box (if present)
            if (model.specialRequests != null && model.specialRequests!.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.neuBg,
                  borderRadius: BorderRadius.circular(AppRadii.s),
                ),
                child: Text(model.specialRequests!, style: AppText.tileSubtitle),
              ),
              const SizedBox(height: 12),
            ],

            // actions: use Wrap to avoid horizontal overflow on small screens
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton.icon(
                      onPressed: model.status == 'confirmed' ? null : onConfirm,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Confirm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.okBg,
                        foregroundColor: AppColors.okFg,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: onReschedule,
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: const Text('Reschedule'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: AppColors.onSurfaceInverse,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
                      ),
                    ),
                  ],
                ),

                // View details aligned to the end when enough space; it will wrap below buttons on narrow widths.
                TextButton(onPressed: onViewDetails, child: Text('View Details', style: AppText.tileSubtitle.copyWith(color: primary))),
              ],
            ),
          ],
        ),
      ),
    );

    return card;
  }
}

/// Internal model mapping Firestore document into usable fields for the card UI.
class _CardModel {
  final String id;
  final List<String> testTypes;
  final DateTime? date;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? specialRequests;
  final Map<String, int>? charges;
  final int? totalMinutes;
  final int? totalPrice;
  final num? paidAmount;
  final Map<String, dynamic>? payment;
  final String? razorpayOrderId;
  final String status;
  final String? userId;
  final String? displayName;
  final String? email;
  final String? phone;

  _CardModel({
    required this.id,
    required this.testTypes,
    required this.date,
    required this.createdAt,
    required this.updatedAt,
    required this.specialRequests,
    required this.charges,
    required this.totalMinutes,
    required this.totalPrice,
    required this.paidAmount,
    required this.payment,
    required this.razorpayOrderId,
    required this.status,
    this.userId,
    this.displayName,
    this.email,
    this.phone,
  });

  factory _CardModel.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data();

    // test types
    final rawTypes = m['test_types'] ?? m['testTypes'];
    List<String> testTypes = [];
    if (rawTypes is List) {
      testTypes = rawTypes.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).cast<String>().toList();
    } else if (rawTypes is String) {
      testTypes = [rawTypes];
    }

    // date parsing
    DateTime? date;
    final dateRaw = m['date'];
    if (dateRaw is Timestamp) date = dateRaw.toDate();
    else if (dateRaw is String) {
      try {
        date = DateTime.parse(dateRaw);
      } catch (_) {}
    } else if (dateRaw is Map && dateRaw.containsKey('_seconds')) {
      try {
        date = DateTime.fromMillisecondsSinceEpoch((dateRaw['_seconds'] as int) * 1000);
      } catch (_) {}
    }

    // created / updated
    DateTime? created;
    final ca = m['created_at'];
    if (ca is Timestamp) created = ca.toDate();
    else if (ca is String) {
      try {
        created = DateTime.parse(ca);
      } catch (_) {}
    }

    DateTime? updated;
    final ua = m['updated_at'];
    if (ua is Timestamp) updated = ua.toDate();
    else if (ua is String) {
      try {
        updated = DateTime.parse(ua);
      } catch (_) {}
    }

    // charges map
    Map<String, int>? charges;
    final chargesRaw = m['charges'];
    if (chargesRaw is Map) {
      charges = {};
      chargesRaw.forEach((k, v) {
        try {
          charges![k.toString()] = (v is num) ? v.toInt() : int.parse(v.toString());
        } catch (_) {}
      });
    }

    final totalMinutes = (m['total_minutes'] is num) ? (m['total_minutes'] as num).toInt() : (m['total_minutes'] == null ? null : int.tryParse(m['total_minutes'].toString()));
    final totalPrice = (m['total_price'] is num) ? (m['total_price'] as num).toInt() : (m['total_price'] == null ? null : int.tryParse(m['total_price'].toString()));
    final paidRaw = m['paid_amount'];
    final paidAmount = (paidRaw is num) ? paidRaw : (paidRaw == null ? null : num.tryParse(paidRaw.toString()));

    // payment: either nested map or top-level keys
    Map<String, dynamic>? payment;
    if (m['payment'] is Map) {
      payment = Map<String, dynamic>.from(m['payment'] as Map);
    } else {
      final topKeys = ['razorpay_order_id', 'razorpay_payment_id', 'razorpay_signature', 'razorpayOrderId', 'razorpayPaymentId'];
      final hasAnyTop = topKeys.any((k) => m.containsKey(k));
      if (hasAnyTop) {
        payment = <String, dynamic>{};
        for (final k in topKeys) {
          if (m.containsKey(k)) payment[k] = m[k];
        }
      }
    }

    final razorpayOrderId = (m['razorpay_order_id'] ?? m['razorpayOrderId'] ?? (payment?['razorpay_order_id']))?.toString();

    // status fallback
    final status = (m['status'] as String?)?.toLowerCase() ?? ((paidAmount != null && paidAmount > 0) ? 'confirmed' : 'pending');

    // user info (try multiple field names)
    final userId = (m['user_id'] as String?) ?? (m['userId'] as String?);
    final displayName = (m['user_name'] as String?) ?? (m['userName'] as String?);
    final email = (m['email'] as String?) ?? (m['user_email'] as String?);
    final phone = (m['phone'] as String?) ?? (m['user_phone'] as String?);

    return _CardModel(
      id: doc.id,
      testTypes: testTypes,
      date: date,
      createdAt: created,
      updatedAt: updated,
      specialRequests: (m['special_requests'] as String?) ?? (m['specialRequests'] as String?),
      charges: charges,
      totalMinutes: totalMinutes,
      totalPrice: totalPrice,
      paidAmount: paidAmount,
      payment: payment,
      razorpayOrderId: razorpayOrderId,
      status: status,
      userId: userId,
      displayName: displayName,
      email: email,
      phone: phone,
    );
  }

  String get dateString {
    if (date == null) return '-';
    try {
      return DateFormat.yMMMd().format(date!);
    } catch (_) {
      return date!.toIso8601String();
    }
  }

  String get createdAtString {
    if (createdAt == null) return '-';
    try {
      return DateFormat.yMMMd().add_jm().format(createdAt!);
    } catch (_) {
      return createdAt!.toIso8601String();
    }
  }

  String get updatedAtString {
    if (updatedAt == null) return '';
    try {
      return DateFormat.yMMMd().add_jm().format(updatedAt!);
    } catch (_) {
      return updatedAt!.toIso8601String();
    }
  }
}

/// Small helper for key/value rows used in dialogs.
Widget _kv(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 120, child: Text(k, style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted))),
        const SizedBox(width: 8),
        Expanded(child: Text(v, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w600))),
      ],
    ),
  );
}
