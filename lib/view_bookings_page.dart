// lib/view_bookings_page.dart
// Page to view current user's test bookings (reads from `test_bookings` collection).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart'; // adjust import path if needed

class ViewBookingsPage extends StatelessWidget {
  const ViewBookingsPage({Key? key}) : super(key: key);

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'confirmed':
      case 'active':
      case 'approved':
        return AppColors.okFg;
      case 'pending':
        return AppColors.warnFg;
      case 'cancelled':
      case 'rejected':
        return AppColors.errFg;
      default:
        return AppColors.onSurfaceMuted;
    }
  }

  String _formatDate(dynamic date) {
    try {
      if (date == null) return '-';
      DateTime dt;
      if (date is Timestamp) {
        dt = date.toDate();
      } else if (date is DateTime) {
        dt = date;
      } else {
        dt = DateTime.parse(date.toString());
      }
      return DateFormat.yMMMd().format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  String _formatCreated(dynamic created) {
    try {
      if (created == null) return '-';
      DateTime dt;
      if (created is Timestamp) dt = created.toDate();
      else if (created is DateTime) dt = created;
      else dt = DateTime.parse(created.toString());
      return DateFormat.yMMMd().add_jm().format(dt);
    } catch (_) {
      return created?.toString() ?? '-';
    }
  }

  /// Helper to interpret a "rescheduled" value that might be bool, string, number, etc.
  bool _isRescheduledValue(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    return s == 'true' || s == 'yes' || s == '1';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          title: const Text('My Bookings'),
        ),
        body: Center(child: Text('Please sign in to view your bookings.', style: AppText.tileSubtitle)),
      );
    }

    final bookingsQuery = FirebaseFirestore.instance
        .collection('test_bookings')
        .where('user_id', isEqualTo: user.uid)
        .orderBy('created_at', descending: true)
        .limit(100);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text('My Bookings'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: bookingsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load bookings: ${snap.error}', style: AppText.tileSubtitle));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(child: Text('No bookings found.', style: AppText.tileSubtitle));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, idx) {
              final doc = docs[idx];
              final d = doc.data();
              final id = doc.id;
              final date = d['date'];
              final types = (d['test_types'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              final status = (d['status'] ?? 'pending').toString();
              final paid = d['paid_amount'] ?? d['paid'] ?? 0;
              final created = d['created_at'];
              final isRescheduled = _isRescheduledValue(d['rescheduled']);

              return Material(
                color: AppColors.surface,
                elevation: 0,
                borderRadius: BorderRadius.circular(AppRadii.m),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.m),
                  onTap: () => _showBookingDetails(context, id, d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.m),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.neuBg,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              DateFormat.d().format(_dateForPreview(date)),
                              style: AppText.tileTitle.copyWith(fontSize: 16, color: AppColors.onSurface),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(types.isNotEmpty ? types.join(', ') : 'Test', style: AppText.tileTitle),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(_formatDate(date), style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
                                  if (isRescheduled) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'RESCHEDULED',
                                        style: AppText.hintSmall.copyWith(
                                          color: Colors.orange,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ]
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('Booked: ${_formatCreated(created)}', style: AppText.hintSmall),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(status.toUpperCase(),
                                  style: AppText.tileSubtitle.copyWith(color: _statusColor(status), fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(height: 8),
                            Text('₹${paid.toString()}', style: AppText.tileTitle.copyWith(color: AppColors.onSurface)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  DateTime _dateForPreview(dynamic date) {
    try {
      if (date == null) return DateTime.now();
      if (date is Timestamp) return date.toDate();
      if (date is DateTime) return date;
      return DateTime.parse(date.toString());
    } catch (_) {
      return DateTime.now();
    }
  }

  void _showBookingDetails(BuildContext context, String id, Map<String, dynamic> data) {
    final date = data['date'];
    final types = (data['test_types'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final status = (data['status'] ?? 'pending').toString();
    final paid = data['paid_amount'] ?? data['paid'] ?? 0;
    final created = data['created_at'];
    final special = data['special_requests'] ?? '';
    final payment = data['payment'] ?? data['razorpay_payment'] ?? data['razorpay_payment_id'];
    final isRescheduled = _isRescheduledValue(data['rescheduled']);

    showDialog<void>(
      context: context,
      builder: (c) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
          title: Row(
            children: [
              Text('Booking Details', style: AppText.sectionTitle),
              if (isRescheduled) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'RESCHEDULED',
                    style: AppText.hintSmall.copyWith(
                      color: Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ]
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Booking ID', id),
                _detailRow('Date', _formatDate(date)),
                _detailRow('Test Types', types.join(', ')),
                _detailRow('Status', status),
                _detailRow('Paid Amount', '₹$paid'),
                const SizedBox(height: 8),
                if (special.toString().isNotEmpty) ...[
                  Text('Special Requests', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(special.toString(), style: AppText.tileSubtitle),
                ],
                const SizedBox(height: 8),
                if (payment != null) ...[
                  Text('Payment Info', style: AppText.tileSubtitle.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(payment.toString(), style: AppText.hintSmall),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: Text('Close', style: AppText.tileTitle.copyWith(color: AppColors.brand)),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppText.hintSmall.copyWith(fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: AppText.tileSubtitle)),
        ],
      ),
    );
  }
}
