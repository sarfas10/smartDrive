// lib/downloadables.dart
// Page to generate Form 14, Form 15 and Form 5 DOCX and open them.
// Form 15 collects user attendance rows for the logged-in user and sends only:
//   trainee_name, date_of_enrolment, entries[] { date, start_time, end_time }
// Form 5 collects: name, relation_of, permanent_address, enrolment_number, date_of_enrolment, completion_date
// Both Form 14 and Form 15 payloads will include `enrolment_number`.
// UI: compact "list" cards like assignment list — title, small tag/date row below, actions on right (view/download/generate).
// Uses your app_theme.dart tokens (AppText, AppColors, AppRadii).

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
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

  /// Collects name, enrolment date and enrolment_number (and other fallbacks) from users & user_profiles.
  /// Also extracts `enrolment_seq` which is the part before the '/' in enrolment_number.
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

    // enrolment_number: prefer users collection, fallback to user_profiles
    final enrolmentNumber = (userRecord['enrolment_number'] as String?) ??
        (profile['enrolment_number'] as String?) ??
        '';

    // extract seq part (left side before slash)
    String enrolmentSeq = '';
    if (enrolmentNumber.isNotEmpty) {
      final parts = enrolmentNumber.split('/');
      if (parts.isNotEmpty) enrolmentSeq = parts.first.trim();
    }

    // use createdAt or profile.date_of_enrolment or userRecord.date_of_enrolment
    final createdAtValue = userRecord['createdAt'];
    final fallbackDateOfEnrolment = profile['date_of_enrolment'] ?? userRecord['date_of_enrolment'];
    final dateOfEnrolment = _toDateString(createdAtValue ?? fallbackDateOfEnrolment) ?? '';

    return {
      'uid': user.uid,
      'name': name,
      'enrolment_number': enrolmentNumber,
      'enrolment_seq': enrolmentSeq,
      'date_of_enrolment': dateOfEnrolment,
      // keep other fields available if needed later
      'photo_url': profile['photo_url'] ?? userRecord['photo_url'] ?? '',
    };
  }

  /// Collect specific fields needed for Form 5
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

    // extract seq part
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
    // _collectCommonPayload already includes enrolment_seq now, so no extraFields required.
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

  /// Fetch attendance rows for currently logged in user and return list of maps
  /// Each map: { date, start_time, end_time } (strings)
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
          // left column: icon + text, right column: actions
          final left = Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // icon circle
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
              // title & tag/date row
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row with small trailing status (on wide screens)
                    Row(
                      children: [
                        Expanded(child: Text(title, style: AppText.tileTitle.copyWith(color: c.onSurface))),
                        if (!isNarrow) const SizedBox(width: 8),
                        if (!isNarrow) _statusChip(ready: ready),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Tag + date (chip style on left), small subtitle expanded
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
              // Generate button (compact)
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

              // Quick view (eye)
              IconButton(
                onPressed: url == null ? null : onOpen,
                icon: const Icon(Icons.remove_red_eye_rounded),
                color: url != null ? c.onSurface : c.onSurface.withOpacity(0.4),
                tooltip: 'Open',
              ),

              // Download (same as open in this flow - opens docx link)
              IconButton(
                onPressed: url == null ? null : onOpen,
                icon: const Icon(Icons.download_rounded),
                color: url != null ? c.onSurface : c.onSurface.withOpacity(0.4),
                tooltip: 'Download DOCX',
              ),
            ],
          );

          if (isNarrow) {
            // stacked layout: left (title) then actions below
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
            // inline: left and actions to the right
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

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    // small helper to format "tag date" — for simplicity we show today for forms that use completion
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refreshing...')));
                      },
                      tooltip: 'Refresh status',
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // List items
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
              ],
            ),
          ),
        ),
      ),

      // fixed footer similar to previous but slightly taller
      
    );
  }
}
