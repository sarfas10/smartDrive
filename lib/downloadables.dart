// lib/downloadables.dart
// Full page source adapted to your app_theme.dart (uses AppText.tileSubtitle / hintSmall).
// Replace 'https://tajdrivingschool.in/...' and API key with your actual values.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'theme/app_theme.dart';

class DownloadablesPage extends StatefulWidget {
  const DownloadablesPage({super.key});

  @override
  State<DownloadablesPage> createState() => _DownloadablesPageState();
}

class _DownloadablesPageState extends State<DownloadablesPage> {
  bool _loading = false;
  String? _form14Url;

  @override
  void initState() {
    super.initState();
    _loadFromFirestore();
  }

  Future<void> _loadFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('user_profiles').doc(user.uid).get();
      if (!mounted) return;
      if (snap.exists) {
        setState(() {
          _form14Url = snap.data()?['form14_url'] as String?;
        });
      }
    } catch (e) {
      // ignore or show message
    }
  }

  /// Convert many possible types (Timestamp, DateTime, ISO string, epoch int)
  /// into a date-only string 'yyyy-MM-dd' or null.
  String? _toDateString(dynamic v) {
    if (v == null) return null;

    try {
      DateTime? dt;

      if (v is Timestamp) {
        dt = v.toDate();
      } else if (v is DateTime) {
        dt = v;
      } else if (v is int) {
        // numeric epoch: try ms first (if very large), otherwise treat as seconds
        if (v > 1000000000000) {
          // looks like milliseconds
          dt = DateTime.fromMillisecondsSinceEpoch(v);
        } else {
          // probably seconds
          dt = DateTime.fromMillisecondsSinceEpoch(v * 1000);
        }
      } else if (v is String) {
        // try parse ISO string
        try {
          dt = DateTime.parse(v);
        } catch (_) {
          // fallback: attempt to extract date portion from token before 'T' or space
          final s = v.split('T').first.split(' ').first;
          return s;
        }
      } else {
        // unknown type - attempt to string convert and extract date-like token
        final s = v.toString();
        final token = s.split('T').first.split(' ').first;
        return token;
      }

      if (dt == null) return null;
      // return yyyy-MM-dd
      return dt.toIso8601String().split('T').first;
    } catch (_) {
      // last resort: return the raw string truncated to date-looking portion
      final s = v.toString();
      return s.split('T').first.split(' ').first;
    }
  }

  /// Debug printing helper — only prints in debug builds.
  void _debugLog(String tag, dynamic obj) {
    assert(() {
      // ignore: avoid_print
      print('DEBUG $tag: ${jsonEncode(obj)}');
      return true;
    }());
  }

  Future<void> _generateForm14() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not logged in')));
      return;
    }

    setState(() => _loading = true);

    try {
      // Load profile from user_profiles (primary source for most fields)
      final profDoc = await FirebaseFirestore.instance.collection('user_profiles').doc(user.uid).get();
      final profile = profDoc.exists ? (profDoc.data() ?? <String, dynamic>{}) : <String, dynamic>{};

      // ALSO load basic user doc for name, createdAt and phone (users collection)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userRecord = userDoc.exists ? (userDoc.data() ?? <String, dynamic>{}) : <String, dynamic>{};

      // Prefer users.name, fall back to profile.name and finally FirebaseAuth displayName
      String? name = (userRecord['name'] as String?) ?? (profile['name'] as String?) ?? user.displayName;
      // relation_of usually stored in profile; fall back to users collection if available
      String? relationOf = (profile['relation_of'] as String?) ?? (userRecord['relation_of'] as String?);

      // phone: prefer users collection -> profile -> FirebaseAuth phoneNumber
      String? phone = (userRecord['phone'] as String?) ?? (profile['phone'] as String?) ?? user.phoneNumber;

      // **Take date_of_enrolment from users.createdAt if present**
      final createdAtValue = userRecord['createdAt'];
      final fallbackDateOfEnrolment = profile['date_of_enrolment'] ?? userRecord['date_of_enrolment'];
      final String? dateOfEnrolment = _toDateString(createdAtValue ?? fallbackDateOfEnrolment);

      // Build payload with safe date serialization (date-only for dob and other date fields)
      final payload = <String, dynamic>{
        'uid': user.uid,
        'name': name,
        'relation_of': relationOf,
        'phone': phone,
        'permanent_address': profile['permanent_address'] ?? userRecord['permanent_address'],
        'dob': _toDateString(profile['dob'] ?? userRecord['dob']),
        'learner_number': profile['learner_number'] ?? userRecord['learner_number'],
        'learner_expiry': _toDateString(profile['learner_expiry'] ?? userRecord['learner_expiry']),
        'license_number': profile['license_number'] ?? userRecord['license_number'],
        'license_expiry': _toDateString(profile['license_expiry'] ?? userRecord['license_expiry']),
        'vehicle_class': profile['vehicle_class'] ?? userRecord['vehicle_class'],
        'date_of_enrolment': dateOfEnrolment,
        'remarks': profile['remarks'] ?? userRecord['remarks'],
        'photo_url': profile['photo_url'] ?? userRecord['photo_url'],
        // optional fields you might want:
        'enrolment_number': profile['enrolment_number'] ?? userRecord['enrolment_number'],
      };

      // Debug: print payload so you can confirm name, phone and relation_of values
      _debugLog('form14_payload', payload);

      final res = await http.post(
        Uri.parse('https://tajdrivingschool.in/smartDrive/forms/generate_form14.php'),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': 'supersecretlkjhgfdsa12341234', // keep in sync with server
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        throw Exception('Server error ${res.statusCode}: ${res.body}');
      }

      final jsonResp = jsonDecode(res.body) as Map<String, dynamic>;
      if (jsonResp['ok'] != true) {
        throw Exception(jsonResp['error'] ?? 'Unknown server error');
      }

      final secureUrl = jsonResp['secure_url'] as String?;
      final publicId = jsonResp['public_id'] as String?;

      if (secureUrl == null) throw Exception('No secure_url returned from server');

      // Save to Firestore for later downloads
      await FirebaseFirestore.instance.collection('user_profiles').doc(user.uid).set({
        'form14_url': secureUrl,
        'form14_public_id': publicId,
        'form14_generated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _form14Url = secureUrl;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Form 14 generated successfully')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadForm14() async {
    if (_form14Url == null) return;
    final uri = Uri.tryParse(_form14Url!);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid URL')));
      return;
    }
    if (!await canLaunchUrl(uri)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not launch URL')));
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Downloadables'),
        backgroundColor: c.surface,
        foregroundColor: c.onSurface,
        elevation: 0.5,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            color: c.surface,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.xl)),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Text('Downloadables', style: AppText.sectionTitle.copyWith(color: c.onSurface)),
                  const SizedBox(height: 18),
                  // Use AppText.tileSubtitle (available in your AppText)
                  Text(
                    'Generate your Form 14 (personalised). A downloadable link will be stored in your profile.',
                    style: AppText.tileSubtitle.copyWith(color: c.onSurface),
                  ),
                  const SizedBox(height: 24),

                  // Generate button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _generateForm14,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.primary,
                        foregroundColor: AppColors.onSurfaceInverse,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
                        elevation: 0,
                      ),
                      child: _loading
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 12),
                                Text('Generating...')
                              ],
                            )
                          : const Text('Generate Form 14'),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (_form14Url != null) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _downloadForm14,
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Download Form 14'),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.primary),
                          foregroundColor: c.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Last generated: stored in your profile.',
                      style: AppText.hintSmall.copyWith(color: c.onSurface.withOpacity(0.8)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
