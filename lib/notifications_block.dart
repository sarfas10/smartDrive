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
  final _urlCtrl = TextEditingController();

  // segments
  final Set<String> _segments = {'all'}; // default to 'all'
  static const _segmentOptions = ['all', 'students', 'instructors', 'active', 'pending'];
  bool _busy = false;

  // ======= CONFIG: point to your Hostinger API and admin key =======
  static const String _apiBase = 'https://tajdrivingschool.in/smartDrive/notification/api';
  static const String _adminApiKey = 'noTi34279bfksdfkafafqeffbdcce';
  // ================================================================

  final _filterAnchorKey = GlobalKey();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final isWide = mq.size.width >= 860; // breakpoint for desktop/tablet

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
                    // Top row: Filters + quick summary
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
                        if (_segments.isNotEmpty && !(_segments.length==1 && _segments.contains('all')))
                          TextButton.icon(
                            onPressed: () => setState(_segments.clear),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text('Clear'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.brand,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Title + URL (adaptive, no Expanded in vertical)
                    _twoUp(
                      isWide: isWide,
                      left: _Labeled(
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
                      right: _Labeled(
                        'Action URL (optional)',
                        TextFormField(
                          controller: _urlCtrl,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            border: const OutlineInputBorder(),
                            hintText: 'https://example.com',
                            hintStyle: AppText.hintSmall.copyWith(color: AppColors.onSurfaceFaint),
                          ),
                          style: AppText.tileTitle.copyWith(color: context.c.onSurface),
                        ),
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

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: _busy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onSurfaceInverse),
                                  )
                                : const Icon(Icons.send_outlined),
                            label: const Text('Send'),
                            onPressed: _busy ? null : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.onSurfaceInverse,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.warning,
                              foregroundColor: AppColors.onSurfaceInverse,
                            ),
                            icon: const Icon(Icons.drafts_outlined),
                            label: const Text('Save Draft (Firestore only)'),
                            onPressed: _busy
                                ? null
                                : () async {
                                    await _saveHistoryFirestore(status: 'draft');
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: const Text('Draft saved.'), backgroundColor: AppColors.success),
                                      );
                                    }
                                  },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 8),
            const SectionHeader(title: 'Notification History (Firestore)'),
            const Divider(height: 1),

            // History — adaptive: cards on phones, table on wide
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
                      child: Center(child: CircularProgressIndicator(color: context.c.primary)),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Error loading history: ${snap.error}', style: AppText.tileSubtitle.copyWith(color: AppColors.danger)),
                    );
                  }
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No notifications yet.', style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceFaint)),
                    );
                  }

                  if (!isWide) {
                    // PHONE: render as vertical cards (avoid nested unbounded flex)
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
                        final status = (m['status']?.toString() ?? '-');

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
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600, color: context.c.onSurface),
                                ),
                                const SizedBox(height: 4),
                                Text('Target: $segs', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppText.tileSubtitle),
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

                  // WIDE: tabular view
                  final rows = <List<Widget>>[];
                  for (final d in docs) {
                    final m = (d.data() as Map).cast<String, dynamic>();
                    rows.add([
                      Text(m['title'] ?? '-', overflow: TextOverflow.ellipsis, style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
                      Text((m['segments'] as List?)?.join(', ') ?? 'all', overflow: TextOverflow.ellipsis, style: AppText.tileSubtitle),
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

  // ---------------- UI helpers ----------------

  /// Layout helper: two fields side-by-side on wide screens, stacked on phones.
  /// IMPORTANT: On phones this returns a Column with NO Expanded/Flexible.
  Widget _twoUp({
    required bool isWide,
    required Widget left,
    required Widget right,
  }) {
    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        left,
        const SizedBox(height: 12),
        right,
      ],
    );
  }

  Future<void> _openFilterPicker({required bool isWide}) async {
    if (isWide) {
      // Desktop/tablet: contextual menu near the icon
      final box = _filterAnchorKey.currentContext?.findRenderObject() as RenderBox?;
      final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
      if (box == null) return;

      final position = RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
        ),
        Offset.zero & overlay.size,
      );

      final selected = await showMenu<String>(
        context: context,
        position: position,
        items: [
          for (final s in _segmentOptions)
            CheckedPopupMenuItem<String>(
              value: s,
              checked: _segments.contains(s) || (_segments.isEmpty && s == 'all'),
              child: Text(s),
            ),
        ],
      );

      if (selected != null) {
        _toggleSegment(selected);
      }
      return;
    }

    // Phone: bottom sheet with checkboxes (better for small screens)
    final localSelections = Set<String>.from(_segments.isEmpty ? {'all'} : _segments);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Text('Choose target segments', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(color: context.c.onSurface)),
              const SizedBox(height: 8),
              ..._segmentOptions.map((s) {
                final checked = localSelections.contains(s) || (localSelections.isEmpty && s == 'all');
                return CheckboxListTile(
                  value: checked,
                  title: Text(s, style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
                  onChanged: (v) {
                    if (v == null) return;
                    if (s == 'all') {
                      localSelections
                        ..clear()
                        ..add('all');
                    } else {
                      if (checked) {
                        localSelections.remove(s);
                      } else {
                        localSelections.add(s);
                      }
                      if (localSelections.length > 1 && localSelections.contains('all')) {
                        localSelections.remove('all');
                      }
                    }
                    // rebuild sheet
                    (ctx as Element).markNeedsBuild();
                  },
                );
              }),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(foregroundColor: context.c.onSurface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _segments
                            ..clear()
                            ..addAll(localSelections);
                        });
                        Navigator.pop(ctx);
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _toggleSegment(String selected) {
    setState(() {
      if (selected == 'all') {
        _segments
          ..clear()
          ..add('all');
      } else {
        if (_segments.contains(selected)) {
          _segments.remove(selected);
        } else {
          _segments.add(selected);
        }
        if (_segments.length > 1 && _segments.contains('all')) {
          _segments.remove('all');
        }
      }
    });
  }

  String _segmentSummary() {
    if (_segments.isEmpty || _segments.contains('all')) return 'Target: all';
    final parts = _segments.toList()..sort();
    return 'Target: ${parts.join(", ")}';
  }

  // ---------------- Actions ----------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    // default to 'all' if user didn't pick any segment
    if (_segments.isEmpty) {
      setState(() => _segments.add('all'));
    }

    setState(() => _busy = true);
    try {
      final body = {
        'title': _titleCtrl.text.trim(),
        'message': _msgCtrl.text.trim(),
        'segments': _segments.toList(),
        'action_url': _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      };

      final uri = Uri.parse('$_apiBase/notify_send.php');

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'X-API-KEY': _adminApiKey},
        body: jsonEncode(body),
      );

      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _saveHistoryFirestore(status: 'queued');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: const Text('Queued to send.'), backgroundColor: AppColors.success),
          );
        }
        _titleCtrl.clear();
        _msgCtrl.clear();
        _urlCtrl.clear();
        setState(() {
          _segments
            ..clear()
            ..add('all');
        });
      } else {
        throw Exception('API error ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveHistoryFirestore({required String status}) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': _titleCtrl.text.trim(),
      'message': _msgCtrl.text.trim(),
      'segments': _segments.toList().isEmpty ? ['all'] : _segments.toList(),
      'action_url': _urlCtrl.text.trim(),
      'status': status, // draft | queued
      'created_at': FieldValue.serverTimestamp(),
    });
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
              if ((m['action_url'] ?? '').toString().isNotEmpty)
                SelectableText('URL: ${m['action_url']}', style: AppText.hintSmall),
              const SizedBox(height: 8),
              Text('Segments: ${(m['segments'] as List?)?.join(", ") ?? "all"}', style: AppText.hintSmall),
              Text('Status: ${m['status']}', style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'), style: TextButton.styleFrom(foregroundColor: context.c.primary)),
        ],
      ),
    );
  }

  static String _format(DateTime? dt) {
    if (dt == null) return '-';
    final d = dt.toLocal();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ------- small UI helpers -------
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
      'draft' => AppColors.slate,
      'queued' => AppColors.info,
      'scheduled' => AppColors.warning,
      'sent' => AppColors.success,
      'error' => AppColors.danger,
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
