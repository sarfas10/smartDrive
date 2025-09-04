// student_details.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart'; // for view/download + opening links

class StudentDetailsPage extends StatelessWidget {
  const StudentDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final uid = args?['uid'] as String?;
    final studentId = args?['studentId'] as String?;

    if (uid == null || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Student Details')),
        body: const Center(child: Text('No UID provided')),
      );
    }

    return Scaffold(
      // Use theme surface to avoid washed-out text on dark themes
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        title: const Text('Student Details'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                'ID: ${studentId ?? _shortId(uid)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
      body: _StudentDetailsBody(uid: uid),
    );
  }

  static String _shortId(String uid) {
    final head =
        uid.length >= 6 ? uid.substring(0, 6).toUpperCase() : uid.toUpperCase();
    return 'STU$head';
  }
}

class _StudentDetailsBody extends StatefulWidget {
  final String uid;
  const _StudentDetailsBody({required this.uid});
  @override
  State<_StudentDetailsBody> createState() => _StudentDetailsBodyState();
}

class _StudentDetailsBodyState extends State<_StudentDetailsBody> {
  String? _userDocId;

  // search for Other Documents
  final _uploadsSearchCtrl = TextEditingController();
  String _uploadsQ = '';

  @override
  void dispose() {
    _uploadsSearchCtrl.dispose();
    super.dispose();
  }

  // ── Streams ────────────────────────────────────────────────────────────────
  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream() async* {
    final fs = FirebaseFirestore.instance;
    final q = await fs
        .collection('users')
        .where('uid', isEqualTo: widget.uid)
        .limit(1)
        .get();
    if (q.docs.isNotEmpty) {
      _userDocId = q.docs.first.id;
      yield* fs.collection('users').doc(_userDocId).snapshots();
      return;
    }
    _userDocId = widget.uid;
    yield* fs.collection('users').doc(_userDocId).snapshots();
  }

  Stream<Map<String, dynamic>> _profileStream() {
    return FirebaseFirestore.instance
        .collection('user_profiles')
        .where('uid', isEqualTo: widget.uid)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty ? s.docs.first.data() : <String, dynamic>{});
  }

  Stream<Map<String, dynamic>> _planStream() {
    return FirebaseFirestore.instance
        .collection('user_plans')
        .where('userId', isEqualTo: widget.uid)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty ? s.docs.first.data() : <String, dynamic>{});
  }

  /// Read user docs from top-level `documents`.
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _documentsStream() {
    return FirebaseFirestore.instance
        .collection('documents') // change to 'document' if that's your name
        .where('uid', isEqualTo: widget.uid)
        .snapshots()
        .map((s) => s.docs);
  }

  /// Read "Other Documents" from `user_uploads` (same as instructor details)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _uploadsStream() {
    return FirebaseFirestore.instance
        .collection('user_uploads')
        .where('uid', isEqualTo: widget.uid)
        .snapshots()
        .map((s) => s.docs);
  }

  // ── Direct notification helper ─────────────────────────────────────────────
  Future<void> _sendUserNotification({
    required String targetUid,
    required String title,
    required String message,
    String segment = 'students', // keeps compatibility with segment filter
    String? actionUrl,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'title': title,
      'message': message,
      'segments': [segment], // optional legacy segment
      'target_uids': [targetUid], // direct target
      'action_url': actionUrl,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _approveKyc() async {
    if (_userDocId == null) return;
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();
    batch.update(fs.collection('users').doc(_userDocId), {'status': 'active'});
    final prof = await fs
        .collection('user_profiles')
        .where('uid', isEqualTo: widget.uid)
        .limit(1)
        .get();
    if (prof.docs.isNotEmpty) {
      batch.update(prof.docs.first.reference, {
        'onboarding_status': 'kyc_approved',
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // 🔔 notify the user
    await _sendUserNotification(
      targetUid: widget.uid,
      title: 'KYC Approved',
      message: 'Your KYC has been approved. You now have full access.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('KYC approved')));
  }

  Future<void> _rejectKyc() async {
    if (_userDocId == null) return;
    final fs = FirebaseFirestore.instance;
    final batch = fs.batch();
    batch.update(fs.collection('users').doc(_userDocId), {'status': 'pending'});
    final prof = await fs
        .collection('user_profiles')
        .where('uid', isEqualTo: widget.uid)
        .limit(1)
        .get();
    if (prof.docs.isNotEmpty) {
      batch.update(prof.docs.first.reference, {
        'onboarding_status': 'kyc_rejected',
        'updated_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    // 🔔 notify the user
    await _sendUserNotification(
      targetUid: widget.uid,
      title: 'KYC Rejected',
      message: 'Your KYC was rejected. Please fix the issues and resubmit.',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('KYC rejected')));
  }

  // NEW: Block user when status is active
  Future<void> _blockUser() async {
    if (_userDocId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userDocId)
          .update({'status': 'blocked'});

      // Optional: notify the user about blocking
      await _sendUserNotification(
        targetUid: widget.uid,
        title: 'Account Blocked',
        message:
            'Your account has been blocked by the admin. Please contact support for assistance.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student has been blocked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to block user: $e')),
      );
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream(),
      builder: (context, userSnap) {
        if (userSnap.hasError) return _error('Failed to load user: ${userSnap.error}');
        if (!userSnap.hasData) return const Center(child: CircularProgressIndicator());
        final u = userSnap.data!.data() ?? {};
        final joined = _fmtDate(u['createdAt']);

        return StreamBuilder<Map<String, dynamic>>(
          stream: _profileStream(),
          builder: (context, profSnap) {
            final p = profSnap.data ?? {};
            final name = (u['name'] ?? 'Student').toString();
            final email = (u['email'] ?? '-').toString();
            final phone = (u['phone'] ?? '-').toString();
            final status = (u['status'] ?? 'active').toString();
            final kyc = (p['onboarding_status'] ?? 'pending').toString();

            final isActive = status.toLowerCase() == 'active';

            final dobStr = formatTimestampDate(p['dob']);
            final address1 = (p['address_line1'] ?? '-').toString();
            final address2 = (p['address_line2'] ?? '').toString();
            final zipcode = (p['zipcode'] ?? '').toString();
            final photo = (p['photo_url'] ?? '').toString();

            return StreamBuilder<Map<String, dynamic>>(
              stream: _planStream(),
              builder: (context, planSnap) {
                final planId = (planSnap.data?['planId'] ?? '—').toString();

                return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                  stream: _documentsStream(),
                  builder: (context, docsSnap) {
                    if (docsSnap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: _emptyRow(
                            context, 'Could not load documents. ${docsSnap.error}'),
                      );
                    }

                    var docs = docsSnap.data ?? const [];
                    docs = List.of(docs)
                      ..sort((a, b) {
                        final ma = a.data();
                        final mb = b.data();
                        final ta = _asDate(ma['created_at']);
                        final tb = _asDate(mb['created_at']);
                        if (ta == null && tb == null) return 0;
                        if (ta == null) return 1;
                        if (tb == null) return -1;
                        return ta.compareTo(tb);
                      });

                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header
                          _card(
                            context: context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundImage:
                                          photo.isNotEmpty ? NetworkImage(photo) : null,
                                      child: photo.isEmpty
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name.substring(0, 1).toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                  fontSize: 20,
                                                  fontWeight: FontWeight.w600),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  color: cs.onSurface,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Joined: $joined',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(height: 12),
                                          Row(
                                            children: [
                                              Text('Status:',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight: FontWeight.w600,
                                                        color: cs.onSurface,
                                                      )),
                                              const SizedBox(width: 8),
                                              _badge(
                                                text: 'Active',
                                                color: _okGreen,
                                                isOn: status.toLowerCase() == 'active',
                                              ),
                                              const SizedBox(width: 8),
                                              _badge(
                                                text: _prettyKyc(kyc),
                                                color: _warnAmber,
                                                isOn:
                                                    !kyc.toLowerCase().contains('approved'),
                                                altColors: _kycColors(kyc),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Contact Information
                          _sectionCard(
                            context: context,
                            title: 'Contact Information',
                            children: [
                              _iconRow(context, Icons.email_outlined, 'Email', email),
                              const SizedBox(height: 12),
                              _iconRow(context, Icons.phone_outlined, 'Phone', phone),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Personal Information
                          _sectionCard(
                            context: context,
                            title: 'Personal Information',
                            children: [
                              _iconRow(
                                  context, Icons.cake_outlined, 'Date of Birth', dobStr),
                              const SizedBox(height: 12),
                              _iconRow(
                                context,
                                Icons.location_on_outlined,
                                'Address',
                                [
                                  address1,
                                  if (address2.isNotEmpty) address2,
                                  if (zipcode.isNotEmpty) zipcode,
                                ]
                                    .where((s) => s.trim().isNotEmpty)
                                    .join(', '),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.card_membership_outlined, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Plan',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: cs.onSurface,
                                                )),
                                        const SizedBox(height: 6),
                                        _planChip(context, planId),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // KYC Documents
                          _card(
                            context: context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text('KYC Documents',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: cs.onSurface,
                                              )),
                                    ),
                                    _rightStatusBadge(context, _prettyKyc(kyc)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (docs.isEmpty)
                                  _emptyRow(context, 'No documents uploaded')
                                else
                                  Column(
                                    children: docs.map((d) {
                                      final m = d.data();
                                      final typeRaw =
                                          (m['type'] ?? 'Document').toString();
                                      final docName = _prettyDocType(typeRaw);
                                      final uploadedAt = _fmtDate(m['created_at']);
                                      final status = _prettyDocStatus(
                                          (m['status'] ?? 'pending').toString());
                                      final frontUrl = (m['front'] ?? '').toString();
                                      final backUrl = (m['back'] ?? '').toString();
                                      return _docImagesTile(
                                        context: context,
                                        title: docName,
                                        meta: 'Status: $status • Uploaded $uploadedAt',
                                        frontUrl: frontUrl,
                                        backUrl: backUrl,
                                      );
                                    }).toList(),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ──────────────────────────────────────────────
                          // Other Documents (from user_uploads)
                          // ──────────────────────────────────────────────
                          _card(
                            context: context,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Other Documents',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: cs.onSurface,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                _UploadsSearchField(
                                  controller: _uploadsSearchCtrl,
                                  onChanged: (v) =>
                                      setState(() => _uploadsQ = v.trim().toLowerCase()),
                                ),
                                const SizedBox(height: 10),
                                StreamBuilder<
                                    List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                                  stream: _uploadsStream(),
                                  builder: (context, upSnap) {
                                    if (upSnap.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Padding(
                                        padding: EdgeInsets.all(16),
                                        child:
                                            Center(child: CircularProgressIndicator()),
                                      );
                                    }
                                    if (upSnap.hasError) {
                                      return _emptyRow(context,
                                          'Could not load uploads. ${upSnap.error}');
                                    }

                                    final all = upSnap.data ?? const [];
                                    final sorted = [...all]
                                      ..sort((a, b) {
                                        final ta = a.data()['created_at'];
                                        final tb = b.data()['created_at'];
                                        final da = (ta is Timestamp)
                                            ? ta.toDate()
                                            : DateTime.fromMillisecondsSinceEpoch(0);
                                        final db = (tb is Timestamp)
                                            ? tb.toDate()
                                            : DateTime.fromMillisecondsSinceEpoch(0);
                                        return db.compareTo(da);
                                      });

                                    final q = _uploadsQ;
                                    final filtered = sorted.where((d) {
                                      if (q.isEmpty) return true;
                                      final m = d.data();
                                      final name = (m['document_name'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      final file = (m['file_name'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      final remarks = (m['remarks'] ?? '')
                                          .toString()
                                          .toLowerCase();
                                      return name.contains(q) ||
                                          file.contains(q) ||
                                          remarks.contains(q);
                                    }).toList();

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${all.length} document${all.length == 1 ? '' : 's'} uploaded',
                                          style: const TextStyle(
                                              color: Colors.black54, fontSize: 12),
                                        ),
                                        const SizedBox(height: 8),
                                        if (filtered.isEmpty)
                                          _emptyRow(context, 'No uploads found')
                                        else
                                          ListView.separated(
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            shrinkWrap: true,
                                            itemCount: filtered.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 10),
                                            itemBuilder: (context, i) {
                                              final d = filtered[i];
                                              final m = d.data();

                                              final url =
                                                  (m['cloudinary_url'] ?? '')
                                                      .toString();
                                              return _UploadItem(
                                                name: (m['document_name'] ?? '-')
                                                    .toString(),
                                                fileName:
                                                    (m['file_name'] ?? '').toString(),
                                                createdAt: m['created_at'],
                                                sizeBytes:
                                                    ((m['file_size'] as num?) ?? 0)
                                                        .toInt(),
                                                remarks:
                                                    (m['remarks'] ?? '').toString(),
                                                onView: () => _openUrl(url),
                                                onDownload: () =>
                                                    _openUrl(url, download: true),
                                              );
                                            },
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Footer actions
                          if (isActive)
                            // Show ONLY when status is active
                            ElevatedButton.icon(
                              icon: const Icon(Icons.block),
                              label: const Text('Block Student'),
                              onPressed: _blockUser,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _dangerRed,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            )
                          else
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon: const Icon(
                                        Icons.check_circle_outline),
                                    label: const Text('Approve KYC'),
                                    onPressed: _approveKyc,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    icon:
                                        const Icon(Icons.cancel_outlined),
                                    label: const Text('Reject KYC'),
                                    onPressed: _rejectKyc,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is Map && (v['seconds'] != null)) {
      final s = int.tryParse(v['seconds'].toString());
      if (s != null) {
        return DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true)
            .toLocal();
      }
    }
    return null;
  }

  Widget _sectionCard(
      {required BuildContext context,
      required String title,
      required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    return _card(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  )),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _card({required BuildContext context, required Widget child}) {
    // Use themed card color for proper contrast
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _iconRow(
      BuildContext context, IconData icon, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: cs.onSurface),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: tt.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
              const SizedBox(height: 4),
              Text(value, style: tt.bodyMedium?.copyWith(color: cs.onSurface)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planChip(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.primary.withOpacity(0.25)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary)),
    );
  }

  Widget _badge({
    required String text,
    required Color color,
    required bool isOn,
    List<Color>? altColors,
  }) {
    final c = altColors ?? [color, color.withOpacity(0.25)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (isOn ? c[0] : Colors.grey).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: (isOn ? c[1] : Colors.grey.withOpacity(0.25))),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: isOn ? (altColors == null ? color : c[0]) : Colors.grey[700],
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _rightStatusBadge(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    final colors = _kycColors(text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors[0].withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors[1]),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12,
              color: colors[0] == _warnAmber ? cs.primary : colors[0],
              fontWeight: FontWeight.w700)),
    );
  }

  List<Color> _kycColors(String s) {
    final t = s.toLowerCase();
    if (t.contains('approved')) return [_okGreen, _okGreen.withOpacity(0.25)];
    if (t.contains('rejected')) return [_dangerRed, _dangerRed.withOpacity(0.25)];
    return [_warnAmber, _warnAmber.withOpacity(0.25)];
  }

  // ── Document tiles with inline front/back images ───────────────────────────
  Widget _docImagesTile({
    required BuildContext context,
    required String title,
    required String meta,
    required String frontUrl,
    required String backUrl,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  )),
          const SizedBox(height: 4),
          Text(meta,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Row(
            children: [
              if (frontUrl.isNotEmpty) _imageThumb(context, frontUrl, 'Front'),
              if (frontUrl.isNotEmpty && backUrl.isNotEmpty) const SizedBox(width: 10),
              if (backUrl.isNotEmpty) _imageThumb(context, backUrl, 'Back'),
              if (frontUrl.isEmpty && backUrl.isEmpty)
                Expanded(
                    child: Text('No files attached',
                        style: TextStyle(color: cs.onSurfaceVariant))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageThumb(BuildContext context, String url, String label) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _showDocPreview(label, url, ''),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: 120,
              height: 76,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => Container(
                width: 120,
                height: 76,
                color: cs.surfaceContainerHighest,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: cs.onSurface, fontSize: 12)),
        ],
      ),
    );
  }

  void _showDocPreview(String title, String front, String back) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 700),
          padding: const EdgeInsets.all(12),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                if (front.isNotEmpty) ...[
                  const Text('Front', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(front, fit: BoxFit.contain)),
                  const SizedBox(height: 12),
                ],
                if (back.isNotEmpty) ...[
                  const Text('Back', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(back, fit: BoxFit.contain)),
                ],
                if (front.isEmpty && back.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child:
                        Text('No preview available', textAlign: TextAlign.center),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openUrl(String url, {bool download = false}) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _emptyRow(BuildContext context, String text) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: cs.onSurface))),
        ],
      ),
    );
  }

  // ── Utils ──────────────────────────────────────────────────────────────────
  static const _okGreen = Color(0xFF16A34A);
  static const _dangerRed = Color(0xFFEF4444);
  static const _warnAmber = Color(0xFFF59E0B);

  String _prettyDocType(String raw) {
    final parts =
        raw.trim().split(RegExp(r'[_\-\s]+')).where((e) => e.isNotEmpty);
    String cap(String s) => s[0].toUpperCase() + s.substring(1).toLowerCase();
    return parts.map(cap).join(' ');
  }

  String formatTimestampDate(dynamic v) {
    if (v == null) return '-';
    if (v is Timestamp) {
      final d = v.toDate();
      return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
    }
    if (v is DateTime) {
      return '${_dd(v.day)}/${_dd(v.month)}/${v.year}';
    }
    if (v is Map && v['seconds'] != null) {
      final s = int.tryParse(v['seconds'].toString());
      if (s != null) {
        final d = DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true)
            .toLocal();
        return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
      }
    }
    if (v is String) {
      final s = v.trim();
      final iso = DateTime.tryParse(s);
      if (iso != null) return '${_dd(iso.day)}/${_dd(iso.month)}/${iso.year}';
      final m = RegExp(r'seconds\s*[:=]\s*(\d+)').firstMatch(s);
      if (m != null) {
        final sec = int.parse(m.group(1)!);
        final d =
            DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true)
                .toLocal();
        return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
      }
      if (RegExp(r'^\d+$').hasMatch(s)) {
        final n = int.parse(s);
        final d = (n >= 1000000000000)
            ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal()
            : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true)
                .toLocal();
        return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
      }
    }
    if (v is num) {
      final n = v.toInt();
      final d = (n >= 1000000000000)
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true)
              .toLocal();
      return '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
    }
    return '-';
  }

  String _fmtDate(dynamic v) => formatTimestampDate(v);
  String _dd(int n) => n.toString().padLeft(2, '0');

  String _prettyKyc(String s) {
    final t = s.toLowerCase();
    if (t.contains('approved')) return 'Approved';
    if (t.contains('rejected')) return 'Rejected';
    if (t.contains('pending')) return 'Pending';
    if (t.contains('personal_saved')) return 'Pending';
    return s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1);
  }

  String _prettyDocStatus(String s) {
    final t = s.toLowerCase();
    if (t.contains('approved') || t.contains('verified')) return 'Approved';
    if (t.contains('rejected') || t.contains('failed')) return 'Rejected';
    if (t.contains('pending') || t.contains('review')) return 'Pending';
    return s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1);
  }

  Widget _error(String msg) => Center(child: Text(msg));
}

// ─────────────────────────────────────────────────────────────────────────────
// "Other Documents" pieces
// ─────────────────────────────────────────────────────────────────────────────

class _UploadsSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _UploadsSearchField(
      {required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search documents...',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }
}

class _UploadItem extends StatelessWidget {
  final String name;
  final String fileName;
  final dynamic createdAt; // Timestamp or DateTime
  final int sizeBytes;
  final String remarks;
  final VoidCallback onView;
  final VoidCallback onDownload;

  const _UploadItem({
    required this.name,
    required this.fileName,
    required this.createdAt,
    required this.sizeBytes,
    required this.remarks,
    required this.onView,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final ext = _ext(fileName);
    final icon = _fileIcon(ext);
    final date = _fmtDate(createdAt);
    final size = _fmtSize(sizeBytes);

    return Card(
      elevation: 0,
      color: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon,
                      size: 20, color: const Color(0xFF3559FF)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(fileName,
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 14, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text(date,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 12)),
                          const SizedBox(width: 14),
                          Text(size,
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (remarks.isNotEmpty)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6F8FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Remarks: ',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.black87)),
                    Expanded(
                        child: Text(remarks,
                            style: const TextStyle(
                                color: Colors.black87, height: 1.2))),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onView,
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    return i == -1 ? '' : name.substring(i + 1).toLowerCase();
  }

  static IconData _fileIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  static String _fmtDate(dynamic ts) {
    DateTime? dt;
    if (ts is Timestamp) dt = ts.toDate();
    if (ts is DateTime) dt = ts;
    dt ??= DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static String _fmtSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const k = 1024.0;
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    var v = bytes.toDouble();
    while (v >= k && i < units.length - 1) {
      v /= k;
      i++;
    }
    final s = (i <= 1) ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$s ${units[i]}';
  }
}
