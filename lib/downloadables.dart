// lib/downloadables.dart
// Page to generate Form 14, Form 15 and Form 5 DOCX and open them.
// Additionally: show Admin-uploaded documents for the logged-in user and allow
// downloading for offline viewing.
//
// Required packages (add to pubspec.yaml):
//   path_provider: ^2.0.0
//   shared_preferences: ^2.0.0
//   open_file: ^3.2.1
// (versions indicative — use latest compatible versions)

import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_file/open_file.dart';

import 'theme/app_theme.dart';

class DownloadablesPage extends StatefulWidget {
  const DownloadablesPage({super.key});

  @override
  State<DownloadablesPage> createState() => _DownloadablesPageState();
}

class _DownloadablesPageState extends State<DownloadablesPage> {
  bool _loading14 = false;
  bool _loading15 = false;
  bool _loading5 = false;
  String? _form14Url;
  String? _form15Url;
  String? _form5Url;

  // Admin uploads state
  bool _loadingAdminUploads = true;
  List<Map<String, dynamic>> _adminUploads = []; // each map includes docId + metadata + sender_role
  Map<String, String> _downloadedLocalPaths = {}; // docId -> localPath

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
    _loadDownloadedMap();
    _loadAdminUploads(); // fetch admin uploads for current user
  }

  Future<void> _loadDownloadedMap() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = sp.getString('downloaded_docs_map') ?? '{}';
      final Map<String, dynamic> m = jsonDecode(jsonStr) as Map<String, dynamic>;
      setState(() {
        _downloadedLocalPaths = m.map((k, v) => MapEntry(k, v as String));
      });
    } catch (_) {
      // ignore
      setState(() => _downloadedLocalPaths = {});
    }
  }

  Future<void> _saveDownloadedMap() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('downloaded_docs_map', jsonEncode(_downloadedLocalPaths));
    } catch (_) {}
  }

  Future<void> _loadFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_profiles')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      if (snap.exists) {
        setState(() {
          _form14Url = snap.data()?['form14_url'] as String?;
          _form15Url = snap.data()?['form15_url'] as String?;
          _form5Url = snap.data()?['form5_url'] as String?;
        });
      }
    } catch (_) {}
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

  Future<Map<String, dynamic>> _collectCommonPayload() async {
    final user = FirebaseAuth.instance.currentUser!;
    final profDoc = await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(user.uid)
        .get();
    final profile = profDoc.exists ? (profDoc.data() ?? <String, dynamic>{}) : {};

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final userRecord = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : {};

    final name = (userRecord['name'] as String?) ??
        (profile['name'] as String?) ??
        user.displayName ??
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
      'uid': user.uid,
      'name': name,
      'enrolment_number': enrolmentNumber,
      'enrolment_seq': enrolmentSeq,
      'date_of_enrolment': dateOfEnrolment,
      'photo_url': profile['photo_url'] ?? userRecord['photo_url'] ?? '',
    };
  }

  Future<Map<String, dynamic>> _collectForm5Payload() async {
    final user = FirebaseAuth.instance.currentUser!;
    final profDoc = await FirebaseFirestore.instance
        .collection('user_profiles')
        .doc(user.uid)
        .get();
    final profile = profDoc.exists ? (profDoc.data() ?? <String, dynamic>{}) : {};

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final userRecord = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : {};

    final name = (userRecord['name'] as String?) ??
        (profile['name'] as String?) ??
        user.displayName ??
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
      'uid': user.uid,
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

  Future<void> _generateForm(String endpoint, String firestoreField,
      VoidCallback onStart, VoidCallback onFinish, Function(String) onSaved,
      { Map<String, dynamic>? extraFields }) async {

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not logged in')));
      return;
    }

    onStart();

    try {
      final payload = await _collectCommonPayload();

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

      await FirebaseFirestore.instance.collection('user_profiles').doc(user.uid).set({
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
    final basic = await _collectCommonPayload();
    final traineeName = basic['name'] ?? '';
    final dateOfEnrolment = basic['date_of_enrolment'] ?? '';
    final enrolmentNumber = basic['enrolment_number'] ?? '';

    final entries = await _fetchAttendanceEntries();

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
    final form5Payload = await _collectForm5Payload();

    await _generateForm(
      'generate_form5.php',
      'form5_url',
      () => setState(() => _loading5 = true),
      () => setState(() => _loading5 = false),
      (url) => setState(() => _form5Url = url),
      extraFields: form5Payload,
    );
  }

  Future<List<Map<String, String>>> _fetchAttendanceEntries() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final qSnapshot = await FirebaseFirestore.instance
        .collection('attendance')
        .where('userId', isEqualTo: user.uid)
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

  /// Load admin uploads for current user:
  /// - Query user_document where recipient_uid == currentUser.uid
  /// - For each doc, fetch sender's role and include only those with role == 'admin'
  Future<void> _loadAdminUploads() async {
    setState(() {
      _loadingAdminUploads = true;
      _adminUploads = [];
    });

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _loadingAdminUploads = false);
      return;
    }

    try {
      final q = await FirebaseFirestore.instance
          .collection('user_document')
          .where('recipient_uid', isEqualTo: user.uid)
          .orderBy('created_at', descending: true)
          .get();

      final results = <Map<String, dynamic>>[];

      for (final doc in q.docs) {
        final data = doc.data();
        final senderUid = (data['sender_uid'] as String?) ?? '';
        String senderRole = '';
        if (senderUid.isNotEmpty) {
          try {
            final sDoc = await FirebaseFirestore.instance.collection('users').doc(senderUid).get();
            senderRole = (sDoc.exists ? (sDoc.data()?['role'] as String?) ?? '' : '');
          } catch (_) {
            senderRole = '';
          }
        }

        // If sender role is admin, include the document
        if (senderRole.toLowerCase() == 'admin') {
          results.add({
            'docId': doc.id,
            'data': data,
            'sender_uid': senderUid,
            'sender_role': senderRole,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _adminUploads = results;
      });
    } catch (e) {
      // ignore errors silently, but keep empty list
    } finally {
      if (mounted) setState(() => _loadingAdminUploads = false);
    }
  }

  // Download remote file and save to local app documents directory for offline viewing.
  // Saves mapping docId -> localPath into SharedPreferences so it persists.
  Future<String?> _downloadAndSaveLocally(String docId, String remoteUrl, {String? suggestedFileName}) async {
    if (kIsWeb) {
      // web: cannot reliably save to app dir; fallback to opening in new tab
      return null;
    }

    try {
      final resp = await http.get(Uri.parse(remoteUrl));
      if (resp.statusCode != 200) throw Exception('Download failed ${resp.statusCode}');

      final bytes = resp.bodyBytes;
      final dir = await getApplicationDocumentsDirectory();
      final safeName = (suggestedFileName ?? docId).replaceAll(RegExp(r'[^A-Za-z0-9_\-\.]'), '_');
      final filePath = '${dir.path}/$safeName';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      // store mapping
      setState(() {
        _downloadedLocalPaths[docId] = filePath;
      });
      await _saveDownloadedMap();
      return filePath;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _openDocument(Map<String, dynamic> doc) async {
    final docId = doc['docId'] as String;
    final data = doc['data'] as Map<String, dynamic>;
    final remoteUrl = data['document_url'] as String?;
    final filename = (data['file_name'] as String?) ?? docId;

    // If we have local copy, open it
    final local = _downloadedLocalPaths[docId];
    if (local != null) {
      try {
        await OpenFile.open(local);
        return;
      } catch (e) {
        // fallthrough to remote open
      }
    }

    // else open remote url (web/in-app)
    if (remoteUrl != null) {
      await _openUrl(remoteUrl);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No document URL available')));
    }
  }

  Future<void> _downloadDocAction(Map<String, dynamic> doc) async {
    final docId = doc['docId'] as String;
    final data = doc['data'] as Map<String, dynamic>;
    final remoteUrl = data['document_url'] as String?;
    final filename = (data['file_name'] as String?) ?? docId;

    if (remoteUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No URL to download')));
      return;
    }

    if (kIsWeb) {
      // On web just open the URL in a new tab to allow browser download
      await _openUrl(remoteUrl);
      return;
    }

    // If already downloaded
    if (_downloadedLocalPaths.containsKey(docId)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Already downloaded for offline use')));
      return;
    }

    // show progress indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: const [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator()),
              SizedBox(width: 16),
              Expanded(child: Text('Downloading — please wait...')),
            ],
          ),
        ),
      ),
    );

    try {
      final localPath = await _downloadAndSaveLocally(docId, remoteUrl, suggestedFileName: filename);
      Navigator.of(context).pop(); // close progress
      if (localPath != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloaded for offline use')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opened in browser (web)')));
      }
    } catch (e) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  /// Build compact list item similar to the assignment list in the screenshot.
  Widget _buildListItem({
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

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: c.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 560;
          final left = Row(
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

          final actions = Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
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

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                left,
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _statusChip(ready: ready)),
                    const SizedBox(width: 12),
                    actions,
                  ],
                )
              ],
            );
          } else {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: left),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _statusChip(ready: ready),
                    const SizedBox(height: 8),
                    actions,
                  ],
                )
              ],
            );
          }
        }),
      ),
    );
  }

  Widget _buildAdminDocCard(Map<String, dynamic> doc) {
    final data = doc['data'] as Map<String, dynamic>;
    final docId = doc['docId'] as String;
    final name = (data['document_name'] as String?) ?? (data['file_name'] as String?) ?? 'Document';
    final uploadedAt = data['created_at'];
    String dateLabel = '';
    if (uploadedAt is Timestamp) {
      dateLabel = DateFormat('dd MMM yyyy').format(uploadedAt.toDate());
    } else if (uploadedAt is String) {
      dateLabel = uploadedAt;
    } else {
      dateLabel = DateFormat('dd MMM yyyy').format(DateTime.now());
    }
    final subtitle = (data['remarks'] as String?) ?? (data['file_name'] as String?) ?? '';

    final hasLocal = _downloadedLocalPaths.containsKey(docId);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: AppText.tileTitle),
                const SizedBox(height: 8),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(children: [
                      Text('Admin', style: AppText.hintSmall.copyWith(color: AppColors.primary)),
                      const SizedBox(width: 8),
                      Text(dateLabel, style: AppText.hintSmall),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(subtitle, style: AppText.tileSubtitle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // View / Open
                IconButton(
                  tooltip: hasLocal ? 'Open (offline)' : 'View',
                  onPressed: () => _openDocument(doc),
                  icon: Icon(hasLocal ? Icons.folder_open : Icons.remove_red_eye_rounded),
                ),
                // Download
                IconButton(
                  tooltip: hasLocal ? 'Downloaded' : 'Download for offline',
                  onPressed: hasLocal ? null : () => _downloadDocAction(doc),
                  icon: Icon(hasLocal ? Icons.check_circle_outline : Icons.download_rounded),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    final todayStr = DateFormat('dd MMM yyyy').format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloadables'),
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0.5,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20 + 72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // header row
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Downloadables', style: AppText.sectionTitle.copyWith(color: c.onSurface)),
                          const SizedBox(height: 6),
                          Text(
                            'Generate official forms and download personalised DOCX files.',
                            style: AppText.tileSubtitle.copyWith(color: c.onSurface),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        _loadFromFirestore();
                        _loadAdminUploads();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing...')));
                      },
                      tooltip: 'Refresh status',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                _buildListItem(
                  icon: Icons.description_rounded,
                  title: 'Form 14 — Application for licence',
                  tagLabel: 'Form 14',
                  tagDate: _form14Url != null ? 'Generated' : 'Not generated',
                  subtitle: 'Personalised DOCX for licence application (includes your enrolment number).',
                  ready: _form14Url != null,
                  loading: _loading14,
                  onGenerate: _generateForm14,
                  onOpen: () => _openUrl(_form14Url),
                  url: _form14Url,
                ),

                _buildListItem(
                  icon: Icons.insert_drive_file_rounded,
                  title: 'Form 15 — Driving hours register',
                  tagLabel: 'Form 15',
                  tagDate: _form15Url != null ? 'Generated' : 'Not generated',
                  subtitle: 'Register of training hours (pulls attendance entries from your account).',
                  ready: _form15Url != null,
                  loading: _loading15,
                  onGenerate: _generateForm15,
                  onOpen: () => _openUrl(_form15Url),
                  url: _form15Url,
                ),

                _buildListItem(
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

                const SizedBox(height: 28),

                // -----------------------
                // Admin Documents section
                // -----------------------
                Text('Admin documents', style: AppText.sectionTitle.copyWith(color: c.onSurface)),
                const SizedBox(height: 8),
                Text('Documents uploaded by the admin for you. Download once to keep for offline viewing.', style: AppText.tileSubtitle.copyWith(color: c.onSurface)),
                const SizedBox(height: 12),

                if (_loadingAdminUploads)
                  const Center(child: CircularProgressIndicator())
                else if (_adminUploads.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F7FB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('No admin documents found.'),
                  )
                else
                  ..._adminUploads.map((d) => _buildAdminDocCard(d)).toList(),

                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
