// lib/pages/report_page.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../ui_common.dart';
import '../theme/app_theme.dart';

class ReportPage extends StatefulWidget {
  final String? initialPreset;

  const ReportPage({Key? key, this.initialPreset}) : super(key: key);

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String _selectedPreset = '30D';
  bool _loading = false;

  static const String serverEndpoint =
      'https://tajdrivingschool.in/smartDrive/payments/razorpay_report.php';

  // Safety limits
  static const int maxAttendanceRows = 300;
  static const int maxBookingRows = 300;
  static const int maxSubscribersRowsPerPlan = 500;
  static const int maxUsersListRows = 200;
  static const int maxPaymentsRows = 1000; // NEW: cap payments rows to avoid huge PDFs

  @override
  void initState() {
    super.initState();
    if (widget.initialPreset != null) _selectedPreset = widget.initialPreset!;
  }

  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final pad = (sw * 0.04).clamp(12.0, 28.0);
    final gap = (pad * 0.75).clamp(8.0, 24.0);
    final radius = (sw * 0.02).clamp(8.0, 14.0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Generate Report'),
        backgroundColor: context.c.primary,
        foregroundColor: context.c.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select period',
                style: AppText.sectionTitle.copyWith(color: context.c.onSurface)),
            SizedBox(height: gap),
            Wrap(spacing: 12, runSpacing: 8, children: [
              _presetButton('30D', '30 days'),
              _presetButton('90D', '90 days'),
              _presetButton('6M', '6 months'),
              _presetButton('1Y', '1 year'),
            ]),
            SizedBox(height: gap),
            Container(
              padding: EdgeInsets.all(pad * 0.8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: AppColors.divider),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected range',
                        style: AppText.tileTitle
                            .copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(_describeSelectedRange(), style: AppText.tileSubtitle),
                    SizedBox(height: gap),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _loading ? null : _generateReport,
                            icon: Icon(Icons.download,
                                color: AppColors.onSurfaceInverse),
                            label: Text('Generate PDF',
                                style: AppText.tileSubtitle.copyWith(
                                    color: AppColors.onSurfaceInverse)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brand),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: _loading ? null : _previewSamplePdf,
                          icon: Icon(Icons.preview,
                              color: AppColors.onSurfaceInverse),
                          label: Text('Preview',
                              style: AppText.tileSubtitle.copyWith(
                                  color: AppColors.onSurfaceInverse)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: context.c.primary),
                        ),
                      ],
                    ),
                    if (_loading) ...[
                      SizedBox(height: gap),
                      Row(children: [
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text('Generating report...',
                            style: AppText.tileSubtitle),
                      ]),
                    ],
                    SizedBox(height: gap),
                    Text(
                      'Report includes: users (lists), attendance (with user info), test bookings, subscribers by plan (student name + createdAt + active), and Razorpay summary and per-payment details.',
                      style: AppText.hintSmall
                          .copyWith(color: AppColors.onSurfaceMuted),
                    ),
                  ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetButton(String id, String label) {
    final selected = _selectedPreset == id;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedPreset = id),
      selectedColor: context.c.primary.withOpacity(0.14),
      backgroundColor: AppColors.neuBg,
      labelStyle:
          TextStyle(color: selected ? context.c.primary : context.c.onSurface),
    );
  }

  String _describeSelectedRange() {
    final now = DateTime.now();
    final range = _computeRange(_selectedPreset, now);
    final start = range.item1;
    final end = range.item2;
    return '${_formatDate(start)} → ${_formatDate(end)}';
  }

  Tuple2<DateTime, DateTime> _computeRange(String preset, DateTime now) {
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    DateTime start;
    switch (preset) {
      case '30D':
        start = end
            .subtract(const Duration(days: 30))
            .copyWith(hour: 0, minute: 0, second: 0);
        break;
      case '90D':
        start = end
            .subtract(const Duration(days: 90))
            .copyWith(hour: 0, minute: 0, second: 0);
        break;
      case '6M':
        final m = now.month - 6;
        final year = m <= 0 ? now.year - 1 : now.year;
        final month = m <= 0 ? m + 12 : m;
        final day = now.day.clamp(1, DateUtils.getDaysInMonth(year, month));
        start =
            DateTime(year, month, day).copyWith(hour: 0, minute: 0, second: 0);
        break;
      case '1Y':
        start = DateTime(now.year - 1, now.month, now.day)
            .copyWith(hour: 0, minute: 0, second: 0);
        break;
      default:
        start = end
            .subtract(const Duration(days: 30))
            .copyWith(hour: 0, minute: 0, second: 0);
    }
    return Tuple2(start, end);
  }

  Future<void> _generateReport() async {
    setState(() => _loading = true);
    final now = DateTime.now();
    final range = _computeRange(_selectedPreset, now);
    final start = range.item1;
    final end = range.item2;

    String razorDebugShort = '';

    try {
      final colUsers = FirebaseFirestore.instance.collection('users');

      // fetch users once (lookup by uid -> data)
      final usersSnap = await colUsers.get();
      final totalUsers = usersSnap.size;
      final Map<String, Map<String, dynamic>> usersById = {};
      for (final d in usersSnap.docs) {
        usersById[d.id] = d.data() as Map<String, dynamic>;
      }

      // Build user lists (no IDs)
      final List<List<String>> totalUsersRows = [];
      final List<List<String>> newUsersRows = [];
      final List<List<String>> studentsRows = [];
      final List<List<String>> instructorsRows = [];

      for (final d in usersSnap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final name = (m['name'] ?? m['user_name'] ?? m['userName'] ?? '').toString();
        final phone = (m['phone'] ?? m['phone_no'] ?? m['phoneNumber'] ?? '').toString();
        final email = (m['email'] ?? '').toString();
        final role = (m['role'] ?? '').toString().toLowerCase();

        DateTime? createdAt;
        if (m['created_at'] is Timestamp) createdAt = (m['created_at'] as Timestamp).toDate();
        else if (m['createdAt'] is Timestamp) createdAt = (m['createdAt'] as Timestamp).toDate();
        else if (m['created_at'] is String) {
          try {
            createdAt = DateTime.parse(m['created_at']);
          } catch (_) {}
        }

        // total users (sample)
        if (totalUsersRows.length < maxUsersListRows) {
          totalUsersRows.add([
            name.isNotEmpty ? name : '-',
            role.isNotEmpty ? role : '-',
            phone.isNotEmpty ? phone : '-',
            email.isNotEmpty ? email : '-',
            createdAt != null ? _formatDateTime(createdAt) : '-',
          ]);
        }

        // new registrations (createdAt in range)
        if (createdAt != null && !createdAt.isBefore(start) && !createdAt.isAfter(end)) {
          if (newUsersRows.length < maxUsersListRows) {
            newUsersRows.add([
              name.isNotEmpty ? name : '-',
              role.isNotEmpty ? role : '-',
              phone.isNotEmpty ? phone : '-',
              email.isNotEmpty ? email : '-',
              _formatDateTime(createdAt),
            ]);
          }
        }

        // students / instructors lists
        if (role == 'student' && studentsRows.length < maxUsersListRows) {
          studentsRows.add([
            name.isNotEmpty ? name : '-',
            phone.isNotEmpty ? phone : '-',
            email.isNotEmpty ? email : '-',
            createdAt != null ? _formatDate(createdAt) : '-',
          ]);
        } else if (role == 'instructor' && instructorsRows.length < maxUsersListRows) {
          instructorsRows.add([
            name.isNotEmpty ? name : '-',
            phone.isNotEmpty ? phone : '-',
            email.isNotEmpty ? email : '-',
            createdAt != null ? _formatDate(createdAt) : '-',
          ]);
        }
      }

      final newRegistrations = newUsersRows.length;
      final studentCount = studentsRows.length;
      final instructorCount = instructorsRows.length;

      // Attendance
      final attendanceSnap = await FirebaseFirestore.instance
          .collection('attendance')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      final totalSlotBookings = attendanceSnap.size;
      int presentCount = 0;
      int absentCount = 0;

      final List<List<String>> attendanceRows = [];
      for (final d in attendanceSnap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final s = (m['status'] ?? '').toString().toLowerCase();
        if (s == 'present') presentCount++;
        else if (s == 'absent') absentCount++;

        final userId = (m['userId'] ?? m['user_id'] ?? '').toString();
        final dateTs = m['date'] as Timestamp?;
        final date = dateTs != null ? dateTs.toDate() : null;
        final slot = (m['slot_time'] ?? '').toString();

        final user = usersById[userId] ?? {};
        final userName = (user['name'] ?? 'Unknown').toString();
        final phone = (user['phone'] ?? '-').toString();
        final userEmail = (user['email'] ?? '-').toString();

        attendanceRows.add([
          date != null ? _formatDate(date) : '-',
          slot,
          s,
          userName,
          phone,
          userEmail,
        ]);

        if (attendanceRows.length >= maxAttendanceRows) break;
      }

      // Test bookings
      final testSnap = await FirebaseFirestore.instance
          .collection('test_bookings')
          .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('created_at', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .get();

      final totalDrivingTestBookings = testSnap.size;
      final List<List<String>> bookingRows = [];
      for (final d in testSnap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final userId = (m['user_id'] ?? '').toString();
        final user = usersById[userId] ?? {};
        final userName = (user['name'] ?? 'Unknown').toString();
        final phone = (user['phone'] ?? '-').toString();
        final status = (m['status'] ?? '').toString();
        final testTypes = (m['test_types'] is List)
            ? (m['test_types'] as List).join(', ')
            : (m['test_types'] ?? '').toString();
        final totalPrice = (m['total_price'] ?? '').toString();

        bookingRows.add([userName, phone, status, testTypes, totalPrice]);
        if (bookingRows.length >= maxBookingRows) break;
      }

      // Subscribers per plan (detailed)
      final userPlansSnap =
          await FirebaseFirestore.instance.collection('user_plans').get();

      final Map<String, int> subscribersByPlan = {};
      final Map<String, List<List<String>>> subscribersDetailsByPlan = {};

      for (final d in userPlansSnap.docs) {
        final m = d.data() as Map<String, dynamic>;
        final planId = (m['planId'] ?? m['plan_id'] ?? '').toString();
        final userId = (m['userId'] ?? m['user_id'] ?? '').toString();
        if (planId.isEmpty) continue;

        subscribersByPlan[planId] = (subscribersByPlan[planId] ?? 0) + 1;

        final userName = usersById[userId] != null
            ? ((usersById[userId]!['name'] ?? usersById[userId]!['user_name'] ?? 'Unknown').toString())
            : 'Unknown';

        String createdAtStr = '-';
        if (m['createdAt'] is Timestamp) {
          createdAtStr = _formatDateTime((m['createdAt'] as Timestamp).toDate());
        } else if (m['created_at'] is Timestamp) {
          createdAtStr = _formatDateTime((m['created_at'] as Timestamp).toDate());
        } else if (m['createdAt'] is String) {
          try {
            createdAtStr = _formatDateTime(DateTime.parse(m['createdAt']));
          } catch (_) {}
        }

        final activeFlag = (m['active'] is bool) ? ((m['active'] as bool) ? 'true' : 'false') : (m['active']?.toString() ?? '-');

        subscribersDetailsByPlan.putIfAbsent(planId, () => []);
        if (subscribersDetailsByPlan[planId]!.length < maxSubscribersRowsPerPlan) {
          subscribersDetailsByPlan[planId]!.add([userName, createdAtStr, activeFlag]);
        }
      }

      // Razorpay summary from server (optional)
      Map<String, dynamic>? razorJson;
      try {
        final res = await http.post(Uri.parse(serverEndpoint),
            body: jsonEncode({
              'start_iso': start.toUtc().toIso8601String(),
              'end_iso': end.toUtc().toIso8601String()
            }),
            headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          razorJson = jsonDecode(res.body) as Map<String, dynamic>?;
        }
      } catch (_) {}

      final serverTotalRevenue =
          razorJson != null ? (razorJson['total_revenue']?.toString() ?? '0.00') : 'N/A';
      final serverRevenueCurrency =
          razorJson != null ? (razorJson['revenue_currency'] ?? 'INR') : 'INR';
      final serverSuccessCount =
          razorJson != null ? (razorJson['success_count']?.toString() ?? '0') : 'N/A';
      final serverFailureCount =
          razorJson != null ? (razorJson['failure_count']?.toString() ?? '0') : 'N/A';

      // --- NEW: fetch per-payment documents directly from Firestore 'payments' collection ---
      final List<List<String>> paymentsRows = [];
      double paymentsTotalAmount = 0.0;
      int paymentsCount = 0;
      try {
        // Query payments documents whose created_at falls within the selected timeframe.
        // Some documents may use 'created_at' or 'createdAt'. We'll query by 'created_at' first.
        Query paymentsQuery = FirebaseFirestore.instance.collection('payments')
            .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('created_at', isLessThanOrEqualTo: Timestamp.fromDate(end))
            .orderBy('created_at', descending: false)
            .limit(maxPaymentsRows);

        final paymentsSnap = await paymentsQuery.get();

        for (final d in paymentsSnap.docs) {
          final m = d.data() as Map<String, dynamic>;

          final payerName = (m['payer_name'] ?? m['user_name'] ?? m['user_name'] ?? '').toString();
          final type = (m['type'] ?? '').toString();
          final method = (m['method'] ?? '').toString();
          double amount = 0.0;
          if (m['amount'] is num) amount = (m['amount'] as num).toDouble();
          else if (m['amount_paise'] is num) amount = ((m['amount_paise'] as num).toDouble()) / 100.0;
          else if (m['amount'] is String) {
            amount = double.tryParse(m['amount']) ?? 0.0;
          }

          final currency = (m['currency'] ?? 'INR').toString();
          final rPaymentId = (m['razorpay_payment_id'] ?? m['payment_id'] ?? '').toString();
          final rOrderId = (m['razorpay_order_id'] ?? m['order_id'] ?? '').toString();

          DateTime? createdAt;
          if (m['created_at'] is Timestamp) createdAt = (m['created_at'] as Timestamp).toDate();
          else if (m['createdAt'] is Timestamp) createdAt = (m['createdAt'] as Timestamp).toDate();
          else if (m['created_at'] is String) {
            try {
              createdAt = DateTime.parse(m['created_at']);
            } catch (_) {}
          }

          final createdAtStr = createdAt != null ? _formatDateTime(createdAt) : '-';

          paymentsRows.add([
            payerName.isNotEmpty ? payerName : '-',
            type.isNotEmpty ? type : '-',
            method.isNotEmpty ? method : '-',
            amount.toStringAsFixed(2),
            currency,
            rPaymentId.isNotEmpty ? rPaymentId : '-',
            rOrderId.isNotEmpty ? rOrderId : '-',
            createdAtStr,
          ]);

          paymentsTotalAmount += amount;
          paymentsCount++;
          if (paymentsRows.length >= maxPaymentsRows) break;
        }

        // If payments query returned empty, attempt fallback query by createdAt (different field name)
        if (paymentsCount == 0) {
          try {
            Query fallbackQuery = FirebaseFirestore.instance.collection('payments')
                .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
                .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
                .orderBy('createdAt', descending: false)
                .limit(maxPaymentsRows);

            final fallbackSnap = await fallbackQuery.get();
            for (final d in fallbackSnap.docs) {
              final m = d.data() as Map<String, dynamic>;
              final payerName = (m['payer_name'] ?? m['user_name'] ?? '').toString();
              final type = (m['type'] ?? '').toString();
              final method = (m['method'] ?? '').toString();
              double amount = 0.0;
              if (m['amount'] is num) amount = (m['amount'] as num).toDouble();
              else if (m['amount_paise'] is num) amount = ((m['amount_paise'] as num).toDouble()) / 100.0;
              else if (m['amount'] is String) {
                amount = double.tryParse(m['amount']) ?? 0.0;
              }
              final currency = (m['currency'] ?? 'INR').toString();
              final rPaymentId = (m['razorpay_payment_id'] ?? m['payment_id'] ?? '').toString();
              final rOrderId = (m['razorpay_order_id'] ?? m['order_id'] ?? '').toString();

              DateTime? createdAt;
              if (m['createdAt'] is Timestamp) createdAt = (m['createdAt'] as Timestamp).toDate();
              else if (m['created_at'] is Timestamp) createdAt = (m['created_at'] as Timestamp).toDate();
              else if (m['createdAt'] is String) {
                try {
                  createdAt = DateTime.parse(m['createdAt']);
                } catch (_) {}
              }

              final createdAtStr = createdAt != null ? _formatDateTime(createdAt) : '-';

              paymentsRows.add([
                payerName.isNotEmpty ? payerName : '-',
                type.isNotEmpty ? type : '-',
                method.isNotEmpty ? method : '-',
                amount.toStringAsFixed(2),
                currency,
                rPaymentId.isNotEmpty ? rPaymentId : '-',
                rOrderId.isNotEmpty ? rOrderId : '-',
                createdAtStr,
              ]);

              paymentsTotalAmount += amount;
              paymentsCount++;
              if (paymentsRows.length >= maxPaymentsRows) break;
            }
          } catch (_) {
            // ignore fallback errors
          }
        }
      } catch (e, st) {
        debugPrint('Payments fetch failed: $e\n$st');
      }

      // Build PDF
      final pdf = pw.Document();
      final sectionStyle = pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
      final labelStyle = pw.TextStyle(fontSize: 11, color: PdfColors.grey800);

      pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
        final List<pw.Widget> content = [];

        content.add(pw.Header(level: 0, child: pw.Text('Log Report')));
        content.add(pw.Text('Period: ${_formatDate(start)} to ${_formatDate(end)}'));
        content.add(pw.SizedBox(height: 12));

        content.add(pw.Text('User Metrics', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        content.add(_pwMetricRow('Total users', totalUsers.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(_pwMetricRow('New registrations', newRegistrations.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(_pwMetricRow('Students', studentCount.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(_pwMetricRow('Instructors', instructorCount.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(pw.SizedBox(height: 12));

        // Total users (sample)
        content.add(pw.Text('Total users (${totalUsersRows.length})', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        if (totalUsersRows.isNotEmpty) {
          content.add(pw.Table.fromTextArray(
            headers: ['Name', 'Role', 'Phone', 'Email', 'Created'],
            data: totalUsersRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No users found.', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // New Registrations
        content.add(pw.Text('New Registrations ( ${newUsersRows.length})', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        if (newUsersRows.isNotEmpty) {
          content.add(pw.Table.fromTextArray(
            headers: ['Name', 'Role', 'Phone', 'Email', 'Created'],
            data: newUsersRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No new registrations in this range.', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // Students
        content.add(pw.Text('Students (${studentsRows.length})', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        if (studentsRows.isNotEmpty) {
          content.add(pw.Table.fromTextArray(
            headers: ['Name', 'Phone', 'Email', 'Registered'],
            data: studentsRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No students found or list truncated.', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // Instructors
        content.add(pw.Text('Instructors (${instructorsRows.length})', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        if (instructorsRows.isNotEmpty) {
          content.add(pw.Table.fromTextArray(
            headers: ['Name', 'Phone', 'Email', 'Registered'],
            data: instructorsRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No instructors found or list truncated.', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // Attendance
        content.add(pw.Text('Attendance Summary', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        content.add(_pwMetricRow('Total slot bookings', totalSlotBookings.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(_pwMetricRow('Present', presentCount.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(_pwMetricRow('Absent', absentCount.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(pw.SizedBox(height: 8));

        if (attendanceRows.isNotEmpty) {
          content.add(pw.Text('Attendance details (${attendanceRows.length} rows)', style: labelStyle));
          content.add(pw.SizedBox(height: 6));
          content.add(pw.Table.fromTextArray(
            headers: ['Date', 'Slot', 'Status', 'Name', 'Phone', 'Email'],
            data: attendanceRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No attendance records found for range.', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // Test bookings
        content.add(pw.Text('Driving Test Bookings ($totalDrivingTestBookings)', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        if (bookingRows.isNotEmpty) {
          content.add(pw.Table.fromTextArray(
            headers: ['Name', 'Phone', 'Status', 'Tests', 'Price'],
            data: bookingRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No test bookings found for range.', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // Razorpay: payments from Firestore
        content.add(pw.Text('Orders ', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        content.add(_pwMetricRow('Payments found', paymentsCount.toString(), pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(_pwMetricRow('Payments total (sum)', 'INR ${paymentsTotalAmount.toStringAsFixed(2)}', pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold), labelStyle));
        content.add(pw.SizedBox(height: 8));

        if (paymentsRows.isNotEmpty) {
          content.add(pw.Text('Payments ( ${paymentsRows.length} rows)', style: labelStyle));
          content.add(pw.SizedBox(height: 6));
          content.add(pw.Table.fromTextArray(
            headers: ['Payer', 'Type', 'Method', 'Amount', 'Currency', 'Razorpay Payment ID', 'Razorpay Order ID', 'Created'],
            data: paymentsRows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
        } else {
          content.add(pw.Text('No payments found for this range .', style: labelStyle));
        }
        content.add(pw.SizedBox(height: 12));

        // Server-side Razorpay summary (optional)
        content.add(pw.Text('Razorpay summary', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        content.add(pw.Text('Server revenue summary: $serverRevenueCurrency $serverTotalRevenue'));
        content.add(pw.Text('Server success: $serverSuccessCount, failure: $serverFailureCount'));
        content.add(pw.SizedBox(height: 12));

        // Subscribers by plan (detailed)
        content.add(pw.Text('Subscribers by Plan (details)', style: sectionStyle));
        content.add(pw.SizedBox(height: 8));
        if (subscribersByPlan.isEmpty) {
          content.add(pw.Text('No plans found in user_plans collection', style: labelStyle));
        } else {
          // Summary table
          final rows = subscribersByPlan.entries.map((e) => [e.key, e.value.toString()]).toList();
          content.add(pw.Table.fromTextArray(
            headers: ['PlanId', 'Subscribers'],
            data: rows,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
          ));
          content.add(pw.SizedBox(height: 8));

          // Detailed table per plan
          for (final planId in subscribersDetailsByPlan.keys) {
            final details = subscribersDetailsByPlan[planId]!;
            content.add(pw.Text('Plan: $planId (showing up to $maxSubscribersRowsPerPlan)', style: labelStyle));
            content.add(pw.SizedBox(height: 6));
            if (details.isNotEmpty) {
              content.add(pw.Table.fromTextArray(
                headers: ['Student Name', 'Created', 'Active'],
                data: details,
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                cellAlignment: pw.Alignment.centerLeft,
              ));
            } else {
              content.add(pw.Text('No subscribers for this plan (or truncated).', style: labelStyle));
            }
            content.add(pw.SizedBox(height: 8));
          }
        }

        content.add(pw.SizedBox(height: 20));

        // Final summary table
        content.add(pw.Text('Summary table', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));
        content.add(pw.SizedBox(height: 8));
        content.add(pw.Table.fromTextArray(
          headers: ['Metric', 'Value'],
          data: [
            ['Total users', totalUsers.toString()],
            ['New registrations', newRegistrations.toString()],
            ['Students (sample)', studentCount.toString()],
            ['Instructors (sample)', instructorCount.toString()],
            ['Slot bookings', totalSlotBookings.toString()],
            ['Present', presentCount.toString()],
            ['Absent', absentCount.toString()],
            ['Driving test bookings', totalDrivingTestBookings.toString()],
            ['Payments (Firestore count)', paymentsCount.toString()],
            ['Payments (Firestore total)', 'INR ${paymentsTotalAmount.toStringAsFixed(2)}'],
            ['Razorpay server revenue', razorJson != null ? '$serverRevenueCurrency $serverTotalRevenue' : 'N/A'],
            ['Razorpay server success', razorJson != null ? serverSuccessCount.toString() : 'N/A'],
            ['Razorpay server failure', razorJson != null ? serverFailureCount.toString() : 'N/A'],
          ],
        ));

        return content;
      }));

      setState(() => _loading = false);
      final filename = 'report_${_selectedPreset}_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: filename);
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Report generation failed: $e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _previewSamplePdf() async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (ctx) => pw.Center(child: pw.Text('Sample report preview'))));
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  pw.Widget _pwMetricRow(String label, String value, pw.TextStyle valueStyle, pw.TextStyle labelStyle) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: labelStyle), pw.Text(value, style: valueStyle)],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatDateTime(DateTime d) {
    final date = _formatDate(d);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }
}

class Tuple2<T1, T2> {
  final T1 item1;
  final T2 item2;
  Tuple2(this.item1, this.item2);
}
