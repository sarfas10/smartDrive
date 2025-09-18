// lib/student_documents_options.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'theme/app_theme.dart';

class StudentDocumentsOptionsPage extends StatefulWidget {
  final String uid;
  const StudentDocumentsOptionsPage({super.key, required this.uid});

  @override
  State<StudentDocumentsOptionsPage> createState() =>
      _StudentDocumentsOptionsPageState();
}

class _StudentDocumentsOptionsPageState
    extends State<StudentDocumentsOptionsPage> {
  bool _loading14 = false;
  bool _loading15 = false;
  bool _loading5 = false;
  String? _form14Url;
  String? _form15Url;
  String? _form5Url;

  // UI-only controllers for "Send Document" feature
  final TextEditingController _docHeaderCtrl = TextEditingController();
  final TextEditingController _docMessageCtrl = TextEditingController();
  List<String> _chosenFiles = []; // UI placeholder: list of selected filenames

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
  }

  @override
  void dispose() {
    _docHeaderCtrl.dispose();
    _docMessageCtrl.dispose();
    super.dispose();
  }

  /// Load any previously generated URLs from the student's user_profiles doc
  Future<void> _loadFromFirestore() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(widget.uid)
          .get();
      if (!mounted) return;
      if (snap.exists) {
        final data = snap.data() ?? <String, dynamic>{};
        setState(() {
          _form14Url = (data['form14_url'] as String?) ?? null;
          _form15Url = (data['form15_url'] as String?) ?? null;
          _form5Url = (data['form5_url'] as String?) ?? null;
        });
      } else {
        setState(() {
          _form14Url = null;
          _form15Url = null;
          _form5Url = null;
        });
      }
    } catch (e) {
      // ignore load errors silently (or show snack)
    }
  }

  String? _toDateString(dynamic v) {
    if (v == null) return null;
    try {
      DateTime? dt;
      if (v is Timestamp) dt = v.toDate();
      else if (v is DateTime) dt = v;
      else if (v is int) {
        if (v > 1000000000000) dt = DateTime.fromMillisecondsSinceEpoch(v);
        else dt = DateTime.fromMillisecondsSinceEpoch(v * 1000);
      } else if (v is String) {
        try {
          dt = DateTime.parse(v);
        } catch (_) {
          final s = v.split('T').first.split(' ').first;
          return s;
        }
      }
      if (dt == null) return null;
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      final s = v.toString();
      return s.split('T').first.split(' ').first;
    }
  }

  /// Collect fields common to form payloads but for the target `widget.uid`
  Future<Map<String, dynamic>> _collectCommonPayloadForUid(String targetUid) async {
    final profDoc = await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(targetUid)
        .get();
    final profile = profDoc.exists ? (profDoc.data() ?? <String, dynamic>{}) : {};

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
    final userRecord = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : {};

    final name = (userRecord['name'] as String?) ??
        (profile['name'] as String?) ??
        '';

    final enrolmentNumber = (userRecord['enrolment_number'] as String?) ??
        (profile['enrolment_number'] as String?) ??
        '';

    String enrolmentSeq = '';
    if (enrolmentNumber.isNotEmpty) {
      final parts = enrolmentNumber.split('/');
      if (parts.isNotEmpty) enrolmentSeq = parts.first.trim();
    }

    final createdAtValue = userRecord['createdAt'];
    final fallbackDateOfEnrolment = profile['date_of_enrolment'] ?? userRecord['date_of_enrolment'];
    final dateOfEnrolment = _toDateString(createdAtValue ?? fallbackDateOfEnrolment) ?? '';

    return {
      'uid': targetUid,
      'name': name,
      'enrolment_number': enrolmentNumber,
      'enrolment_seq': enrolmentSeq,
      'date_of_enrolment': dateOfEnrolment,
      'photo_url': profile['photo_url'] ?? userRecord['photo_url'] ?? '',
    };
  }

  /// Collect fields needed for Form 5 for the target uid.
  Future<Map<String, dynamic>> _collectForm5PayloadForUid(String targetUid) async {
    final profDoc = await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(targetUid)
        .get();
    final profile = profDoc.exists ? (profDoc.data() ?? <String, dynamic>{}) : {};

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(targetUid).get();
    final userRecord = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : {};

    final name = (userRecord['name'] as String?) ??
        (profile['name'] as String?) ??
        '';

    final relationOf = (profile['relation_of'] as String?) ??
        (userRecord['relation_of'] as String?) ??
        '';

    final permanentAddress = (profile['permanent_address'] as String?) ??
        (userRecord['permanent_address'] as String?) ??
        '';

    final enrolmentNumber = (userRecord['enrolment_number'] as String?) ??
        (profile['enrolment_number'] as String?) ??
        '';

    String enrolmentSeq = '';
    if (enrolmentNumber.isNotEmpty) {
      final parts = enrolmentNumber.split('/');
      if (parts.isNotEmpty) enrolmentSeq = parts.first.trim();
    }

    final createdAtValue = userRecord['createdAt'];
    final fallbackDateOfEnrolment = profile['date_of_enrolment'] ?? userRecord['date_of_enrolment'];
    final dateOfEnrolment = _toDateString(createdAtValue ?? fallbackDateOfEnrolment) ?? '';

    final completionDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

    return {
      'uid': targetUid,
      'name': name,
      'relation_of': relationOf,
      'permanent_address': permanentAddress,
      'enrolment_number': enrolmentNumber,
      'enrolment_seq': enrolmentSeq,
      'date_of_enrolment': dateOfEnrolment,
      'completion_date': completionDate,
      'photo_url': profile['photo_url'] ?? userRecord['photo_url'] ?? '',
    };
  }

  Future<void> _generateForm(
      String endpoint,
      String firestoreField,
      VoidCallback onStart,
      VoidCallback onFinish,
      Function(String) onSaved, {
      Map<String, dynamic>? extraFields,
    }) async {
    onStart();
    try {
      final payload = await _collectCommonPayloadForUid(widget.uid);
      if (extraFields != null) payload.addAll(extraFields);

      final uri = Uri.parse('https://tajdrivingschool.in/smartDrive/forms/$endpoint');
      final response = await http
          .post(uri,
              headers: {
                'Content-Type': 'application/json',
                'x-api-key': 'supersecretlkjhgfdsa12341234',
              },
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}: ${response.body}');
      }

      final jsonResp = jsonDecode(response.body);
      if (jsonResp['ok'] != true) {
        throw Exception(jsonResp['error'] ?? 'Unknown server error');
      }

      final secureUrl = jsonResp['secure_url'] as String?;
      final publicId = jsonResp['public_id'] as String?;
      final filenameDocx = jsonResp['filename_docx'] as String?;

      if (secureUrl == null) throw Exception('No secure_url returned');

      await FirebaseFirestore.instance.collection('user_profiles').doc(widget.uid).set({
        firestoreField: secureUrl,
        '${firestoreField.split('_')[0]}_public_id': publicId,
        '${firestoreField.split('_')[0]}_generated_at': FieldValue.serverTimestamp(),
        if (filenameDocx != null) '${firestoreField.split('_')[0]}_docx_filename': filenameDocx,
      }, SetOptions(merge: true));

      onSaved(secureUrl);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form generated successfully')));
    } on TimeoutException {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request timed out — please try again')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      onFinish();
    }
  }

  Future<void> _generateForm14() async {
    await _generateForm(
      'generate_form14.php',
      'form14_url',
      () => setState(() => _loading14 = true),
      () => setState(() => _loading14 = false),
      (url) => setState(() => _form14Url = url),
    );
  }

  Future<void> _generateForm15() async {
    final basic = await _collectCommonPayloadForUid(widget.uid);
    final traineeName = basic['name'] ?? '';
    final dateOfEnrolment = basic['date_of_enrolment'] ?? '';
    final enrolmentNumber = basic['enrolment_number'] ?? '';

    final entries = await _fetchAttendanceEntriesForUid(widget.uid);

    await _generateForm(
      'generate_form15.php',
      'form15_url',
      () => setState(() => _loading15 = true),
      () => setState(() => _loading15 = false),
      (url) => setState(() => _form15Url = url),
      extraFields: {
        'trainee_name': traineeName,
        'date_of_enrolment': dateOfEnrolment,
        'enrolment_number': enrolmentNumber,
        'entries': entries,
      },
    );
  }

  Future<void> _generateForm5() async {
    final form5Payload = await _collectForm5PayloadForUid(widget.uid);

    await _generateForm(
      'generate_form5.php',
      'form5_url',
      () => setState(() => _loading5 = true),
      () => setState(() => _loading5 = false),
      (url) => setState(() => _form5Url = url),
      extraFields: form5Payload,
    );
  }

  /// Fetch attendance rows for a given uid
  Future<List<Map<String, String>>> _fetchAttendanceEntriesForUid(String targetUid) async {
    final qSnapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('userId', isEqualTo: targetUid)
        .get();

    final docs = qSnapshot.docs;

    docs.sort((a, b) {
      final aVal = a.data()['slot_day'];
      final bVal = b.data()['slot_day'];

      DateTime? ad, bd;
      if (aVal is Timestamp) ad = aVal.toDate();
      else if (aVal is String) {
        try { ad = DateTime.parse(aVal); } catch (_) { ad = null; }
      }

      if (bVal is Timestamp) bd = bVal.toDate();
      else if (bVal is String) {
        try { bd = DateTime.parse(bVal); } catch (_) { bd = null; }
      }

      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return ad.compareTo(bd);
    });

    final List<Map<String, String>> rows = [];

    for (final doc in docs) {
      final data = doc.data();
      final slotDayRaw = data['slot_day'] ?? data['slotDay'] ?? data['date'];
      final slotDay = _toDateString(slotDayRaw) ?? '';

      final slotTimeRaw = (data['slot_time'] ?? data['slotTime'] ?? '').toString();
      final times = _parseStartEndFromSlotTime(slotTimeRaw);
      final start = times['start'] ?? '';
      final end = times['end'] ?? '';

      rows.add({
        'date': slotDay,
        'start_time': start,
        'end_time': end,
      });
    }

    return rows;
  }

  Map<String, String> _parseStartEndFromSlotTime(String slotTime) {
    if (slotTime.trim().isEmpty) return {'start': '', 'end': ''};

    String s = slotTime.trim();
    if (s.contains('-')) {
      final parts = s.split('-');
      if (parts.length >= 2) return {'start': parts[0].trim(), 'end': parts[1].trim()};
    } else if (s.toUpperCase().contains('TO')) {
      final parts = s.toUpperCase().split('TO');
      if (parts.length >= 2) return {'start': parts[0].trim(), 'end': parts[1].trim()};
    }

    final parts = s.split(RegExp(r'\s+'));
    if (parts.length >= 3) {
      return {'start': parts[0].trim(), 'end': parts[2].trim()};
    }
    return {'start': s, 'end': ''};
  }

  Future<void> _openUrl(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid URL')));
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _statusChip({required bool ready}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ready ? AppColors.success.withOpacity(0.12) : AppColors.warning.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check_circle : Icons.hourglass_empty,
            size: 14,
            color: ready ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 6),
          Text(
            ready ? 'Ready' : 'Not generated',
            style: AppText.hintSmall.copyWith(
              color: ready ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }

  // -----------------------------
  // UI-only "Send Document" helpers
  // -----------------------------
  Widget _buildSendDocumentCard(BuildContext context, double maxWidth) {
    final cs = Theme.of(context).colorScheme;
    final isNarrow = maxWidth < 560;

    return Card(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 12 : 16,
          vertical: isNarrow ? 12 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text('Send Documents', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: cs.onSurface)),
            const SizedBox(height: 12),

            // Document Header
            Text('Document Header *', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _docHeaderCtrl,
              decoration: InputDecoration(
                hintText: 'Enter document header or title...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.onSurface.withOpacity(0.08))),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),

            const SizedBox(height: 12),

            // Upload box (UI-only)
            GestureDetector(
              onTap: () {
                // UI only — show snackbar
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File picker not implemented (UI only)')));
              },
              child: DottedUploadBox(
                isNarrow: isNarrow,
                files: _chosenFiles,
                onChoose: () {
                  // UI-only placeholder: add a fake filename for visualization
                  setState(() {
                    _chosenFiles.add('document_${_chosenFiles.length + 1}.pdf');
                  });
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose files (UI-only) — added placeholder filename')));
                },
              ),
            ),

            const SizedBox(height: 12),

            // Additional Message
            Text('Additional Message (Optional)', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            TextField(
              controller: _docMessageCtrl,
              decoration: InputDecoration(
                hintText: 'Add a message to accompany the documents...',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: cs.onSurface.withOpacity(0.08))),
                filled: true,
                fillColor: Theme.of(context).scaffoldBackgroundColor,
              ),
              minLines: 3,
              maxLines: 6,
            ),

            const SizedBox(height: 14),

            // Buttons row
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      // UI-only: not implemented
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Send document not implemented (UI only)')));
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Send Documents'),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _docHeaderCtrl.clear();
                      _docMessageCtrl.clear();
                      _chosenFiles.clear();
                    });
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cleared (UI only)')));
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // Main list item builder (same as before)
  // -----------------------------
  Widget _buildListItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String tagLabel,
    required String tagDate,
    required String subtitle,
    required bool ready,
    required bool loading,
    required VoidCallback onGenerate,
    required VoidCallback onOpen,
    String? url,
  }) {
    final c = context.c;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final isNarrow = width < 560;
      final isVeryNarrow = width < 420;

      final titleColumn = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.onSurface.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 22, color: c.onSurface.withOpacity(0.9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(title, style: AppText.tileTitle.copyWith(color: c.onSurface))),
                    if (!isNarrow) const SizedBox(width: 8),
                    if (!isNarrow) _statusChip(ready: ready),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          Text(tagLabel, style: AppText.hintSmall.copyWith(color: AppColors.primary)),
                          const SizedBox(width: 8),
                          Text(tagDate, style: AppText.hintSmall.copyWith(color: c.onSurface.withOpacity(0.7))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(subtitle, style: AppText.tileSubtitle.copyWith(color: c.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      );

      Widget actionsArea;
      if (isVeryNarrow) {
        actionsArea = PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) async {
            switch (v) {
              case 'generate':
                if (!loading) onGenerate();
                break;
              case 'view':
                if (url != null)  onOpen();
                break;
              case 'download':
                if (url != null)  onOpen();
                break;
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'generate', child: Row(children: [const Icon(Icons.playlist_add_rounded), const SizedBox(width: 8), Text(loading ? 'Generating...' : 'Generate')])),
            PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.remove_red_eye_rounded), const SizedBox(width: 8), const Text('View')])),
            PopupMenuItem(value: 'download', child: Row(children: [const Icon(Icons.download_rounded), const SizedBox(width: 8), const Text('Download')])),
          ],
        );
      } else {
        actionsArea = Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: loading ? null : onGenerate,
              icon: loading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.playlist_add_rounded, size: 16),
              label: Text(loading ? 'Generating' : 'Generate', style: const TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: AppColors.onSurfaceInverse,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(0, 36),
              ),
            ),
            IconButton(
              onPressed: url == null ? null : onOpen,
              icon: const Icon(Icons.remove_red_eye_rounded),
              color: url != null ? c.onSurface : c.onSurface.withOpacity(0.4),
              tooltip: 'Open',
            ),
            IconButton(
              onPressed: url == null ? null : onOpen,
              icon: const Icon(Icons.download_rounded),
              color: url != null ? c.onSurface : c.onSurface.withOpacity(0.4),
              tooltip: 'Download DOCX',
            ),
          ],
        );
      }

      final cardChild = Padding(
        padding: EdgeInsets.symmetric(
          vertical: isNarrow ? 12 : 16,
          horizontal: isNarrow ? 12 : 14,
        ),
        child: isNarrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  titleColumn,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: Align(alignment: Alignment.centerLeft, child: _statusChip(ready: ready))),
                      const SizedBox(width: 12),
                      actionsArea,
                    ],
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: titleColumn),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _statusChip(ready: ready),
                        const SizedBox(height: 8),
                        actionsArea,
                      ],
                    ),
                  )
                ],
              ),
      );

      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
        elevation: 1,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: c.surface,
        child: cardChild,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final mq = MediaQuery.of(context);
    final width = mq.size.width;

    // Responsive horizontal padding and max content width
    final horizontalPadding = width >= 1200 ? 48.0 : width >= 900 ? 28.0 : 16.0;
    final maxContentWidth = width >= 1200 ? 1100.0 : width >= 1000 ? 980.0 : 720.0;

    final todayStr = DateFormat('dd MMM yyyy').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Options'),
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0.5,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(horizontalPadding, 20, horizontalPadding, 20 + 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Document Options', style: AppText.sectionTitle.copyWith(color: c.onSurface)),
                            const SizedBox(height: 6),
                            Text(
                              'Generate official forms for this student and download personalised DOCX files.',
                              style: AppText.tileSubtitle.copyWith(color: c.onSurface),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          _loadFromFirestore();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing...')));
                        },
                        tooltip: 'Refresh status',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Form 14
                  _buildListItem(
                    context: context,
                    icon: Icons.description_rounded,
                    title: 'Form 14 — Application for licence',
                    tagLabel: 'Form 14',
                    tagDate: _form14Url != null ? 'Generated' : 'Not generated',
                    subtitle: 'Personalised DOCX for licence application (includes enrolment number).',
                    ready: _form14Url != null,
                    loading: _loading14,
                    onGenerate: _generateForm14,
                    onOpen: () => _openUrl(_form14Url),
                    url: _form14Url,
                  ),

                  // Form 15
                  _buildListItem(
                    context: context,
                    icon: Icons.insert_drive_file_rounded,
                    title: 'Form 15 — Driving hours register',
                    tagLabel: 'Form 15',
                    tagDate: _form15Url != null ? 'Generated' : 'Not generated',
                    subtitle: 'Register of training hours (pulls attendance entries for this student).',
                    ready: _form15Url != null,
                    loading: _loading15,
                    onGenerate: _generateForm15,
                    onOpen: () => _openUrl(_form15Url),
                    url: _form15Url,
                  ),

                  // Form 5
                  _buildListItem(
                    context: context,
                    icon: Icons.assignment_rounded,
                    title: 'Form 5 — Completion certificate',
                    tagLabel: 'Form 5',
                    tagDate: _form5Url != null ? 'Generated' : todayStr,
                    subtitle: 'Certificate-like form (name, relation, address, enrolment & completion date).',
                    ready: _form5Url != null,
                    loading: _loading5,
                    onGenerate: _generateForm5,
                    onOpen: () => _openUrl(_form5Url),
                    url: _form5Url,
                  ),

                  const SizedBox(height: 18),

                  // -------------------------
                  // SEND DOCUMENT SECTION (moved to bottom)
                  // -------------------------
                  LayoutBuilder(builder: (context, constraints) {
                    return _buildSendDocumentCard(context, constraints.maxWidth);
                  }),

                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small dotted upload box widget used as a visual placeholder.
/// UI-only: onChoose triggers a callback but no real file selection is implemented.
class DottedUploadBox extends StatelessWidget {
  final bool isNarrow;
  final List<String> files;
  final VoidCallback onChoose;

  const DottedUploadBox({
    super.key,
    required this.isNarrow,
    required this.files,
    required this.onChoose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: isNarrow ? 18 : 24, horizontal: isNarrow ? 12 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.onSurface.withOpacity(0.12), width: 1.5, style: BorderStyle.solid),
        color: Theme.of(context).cardColor,
      ),
      child: Column(
        children: [
          // Upper area with icon and text
          Icon(Icons.cloud_upload_outlined, size: isNarrow ? 36 : 48, color: cs.onSurface.withOpacity(0.45)),
          const SizedBox(height: 8),
          Text('Upload Documents', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface)),
          const SizedBox(height: 6),
          Text('Drag and drop files here or click to browse', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurface.withOpacity(0.7)), textAlign: TextAlign.center),
          const SizedBox(height: 12),

          // Choose files button
          ElevatedButton(
            onPressed: onChoose,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Choose Files'),
          ),

          // Chosen filenames UI-only preview
          if (files.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: files.map((f) => Chip(label: Text(f), visualDensity: VisualDensity.compact)).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
