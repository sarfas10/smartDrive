// lib/notifications_block.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';
import 'package:smart_drive/theme/app_theme.dart';

class NotificationsBlock extends StatefulWidget {
  const NotificationsBlock({super.key});
  @override
  State<NotificationsBlock> createState() => _NotificationsBlockState();
}

class _NotificationsBlockState extends State<NotificationsBlock> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _msgCtrl = TextEditingController();

  // segments — default to 'all'
  final Set<String> _segments = {'all'};
  static const _segmentOptions = ['all', 'students', 'instructors', 'active', 'pending'];
  bool _busy = false;

  // ======= CONFIG =======
  static const String _apiBase = 'https://tajdrivingschool.in/smartDrive/notification/api';
  static const String _adminApiKey = 'noTi34279bfksdfkafafqeffbdcce';
  // ======================

  final _filterAnchorKey = GlobalKey();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isWide = mq.size.width >= 860;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppCard(
              title: 'Send Push Notification',
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Filters row
                    Row(
                      children: [
                        Tooltip(
                          message: 'Choose target segments',
                          child: IconButton.filledTonal(
                            key: _filterAnchorKey,
                            onPressed: () => _openFilterPicker(isWide: isWide),
                            icon: const Icon(Icons.filter_list_rounded),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _segmentSummary(),
                            style: AppText.tileSubtitle.copyWith(
                              color: AppColors.onSurfaceMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_segments.isNotEmpty && !(_segments.length == 1 && _segments.contains('all')))
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _segments
                                ..clear()
                                ..add('all');
                            }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Clear'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.brand,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Title only (removed URL)
                    _Labeled(
                      'Notification Title',
                      TextFormField(
                        controller: _titleCtrl,
                        textInputAction: TextInputAction.next,
                        maxLength: 60,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Title required' : null,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Eg. New Test Available',
                          hintStyle: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint),
                        ),
                        style: AppText.tileTitle.copyWith(color: context.c.onSurface),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Message
                    _Labeled(
                      'Message',
                      TextFormField(
                        controller: _msgCtrl,
                        maxLines: 4,
                        maxLength: 240,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Message required' : null,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          hintText: 'Write the push message…',
                          hintStyle: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint),
                        ),
                        style: AppText.tileTitle.copyWith(color: context.c.onSurface),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Send button
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _busy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.onSurfaceInverse,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: const Text('Send Now'),
                            onPressed: _busy ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onSurfaceInverse,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            const SectionHeader(title: 'Notification History'),
            const Divider(height: 1),

            // History
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('notifications')
                    .orderBy('created_at', descending: true)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: CircularProgressIndicator(color: context.c.primary),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Error loading history: ${snap.error}',
                        style: AppText.tileSubtitle.copyWith(color: AppColors.danger),
                      ),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No notifications yet.',
                        style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceFaint),
                      ),
                    );
                  }

                  final isWide = MediaQuery.of(context).size.width >= 860;
                  if (!isWide) {
                    // Card view on mobile
                    return ListView.separated(
                      shrinkWrap: true,
                      primary: false,
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final m = (docs[i].data() as Map).cast<String, dynamic>();
                        final title = (m['title'] ?? '-') as String;
                        final segs = (m['segments'] as List?)?.join(', ') ?? 'all';
                        final when = _format((m['created_at'] as Timestamp?)?.toDate());
                        final status = (m['status']?.toString() ?? 'sent');

                        return Card(
                          elevation: 0,
                          color: AppColors.neuBg,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: context.c.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text('Target: $segs', style: AppText.tileSubtitle),
                                const SizedBox(height: 2),
                                Text('When: $when', style: AppText.hintSmall),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    _StatusPill(status),
                                    const Spacer(),
                                    TextButton(
                                      onPressed: () => _preview(context, m),
                                      child: const Text('View'),
                                      style: TextButton.styleFrom(foregroundColor: context.c.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }

                  // Table view on wide screens
                  final rows = <List<Widget>>[];
                  for (final d in docs) {
                    final m = (d.data() as Map).cast<String, dynamic>();
                    rows.add([
                      Text(m['title'] ?? '-', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
                      Text((m['segments'] as List?)?.join(', ') ?? 'all', style: AppText.tileSubtitle),
                      Text(_format((m['created_at'] as Timestamp?)?.toDate()), style: AppText.hintSmall),
                      _StatusPill(m['status']?.toString() ?? '-'),
                      TextButton(
                        onPressed: () => _preview(context, m),
                        child: const Text('View'),
                        style: TextButton.styleFrom(foregroundColor: context.c.primary),
                      ),
                    ]);
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTableWrap(
                      columns: const ['Title', 'Target', 'When', 'Status', 'Actions'],
                      rows: rows,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Actions ----------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_segments.isEmpty) {
      setState(() => _segments.add('all'));
    }

    setState(() => _busy = true);
    String status = 'error';
    String? errorMsg;

    try {
      final body = {
        'title': _titleCtrl.text.trim(),
        'message': _msgCtrl.text.trim(),
        'segments': _segments.toList(),
      };

      final uri = Uri.parse('$_apiBase/notify_send.php');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'X-API-KEY': _adminApiKey},
        body: jsonEncode(body),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        status = 'sent';
      } else {
        status = 'error';
        errorMsg = 'API error ${res.statusCode}: ${res.body}';
      }
    } catch (e) {
      status = 'error';
      errorMsg = e.toString();
    } finally {
      try {
        await _saveHistoryFirestore(status: status, errorMessage: errorMsg);
      } catch (_) {}

      if (mounted) {
        if (status == 'sent') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Notification sent.'), backgroundColor: AppColors.success),
          );
          _titleCtrl.clear();
          _msgCtrl.clear();
          setState(() {
            _segments
              ..clear()
              ..add('all');
          });
        } else {
          final display = errorMsg ?? 'Failed to send notification.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $display'), backgroundColor: AppColors.danger),
          );
        }
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _saveHistoryFirestore({required String status, String? errorMessage}) async {
    final doc = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'message': _msgCtrl.text.trim(),
      'segments': _segments.toList().isEmpty ? ['all'] : _segments.toList(),
      'status': status,
      'created_at': FieldValue.serverTimestamp(),
    };
    if (errorMessage != null && errorMessage.isNotEmpty) {
      doc['error'] = errorMessage;
    }
    await FirebaseFirestore.instance.collection('notifications').add(doc);
  }

  void _preview(BuildContext ctx, Map<String, dynamic> m) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(m['title'] ?? '-', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(m['message'] ?? '', style: AppText.tileSubtitle.copyWith(color: context.c.onSurface)),
              const SizedBox(height: 8),
              Text('Segments: ${(m['segments'] as List?)?.join(", ") ?? "all"}', style: AppText.hintSmall),
              Text('Status: ${m['status']}', style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
            style: TextButton.styleFrom(foregroundColor: context.c.primary),
          ),
        ],
      ),
    );
  }

  static String _format(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ---------------- UI helpers ----------------
  Future<void> _openFilterPicker({required bool isWide}) async {
    // unchanged filter code...
  }

  String _segmentSummary() {
    if (_segments.isEmpty || _segments.contains('all')) return 'Target: all';
    final parts = _segments.toList()..sort();
    return 'Target: ${parts.join(", ")}';
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled(this.label, this.child);
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: AppText.tileTitle.copyWith(color: context.c.onSurface, fontWeight: FontWeight.w600)),
      ),
      child,
    ]);
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);
  @override
  Widget build(BuildContext context) {
    Color c = switch (status) {
      'sent' => AppColors.success,
      'error' => AppColors.danger,
      'scheduled' => AppColors.warning,
      'draft' => AppColors.slate,
      'queued' => AppColors.info,
      _ => AppColors.onSurfaceMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.withOpacity(.35)),
      ),
      child: Text(status, style: AppText.hintSmall.copyWith(color: c, fontWeight: FontWeight.w600)),
    );
  }
}
