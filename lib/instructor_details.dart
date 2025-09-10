// lib/instructor_details.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

// Import your design tokens & theme helpers
import 'theme/app_theme.dart'; // <-- adjust this path to match your project

/// Instructor details page (Admin view)
/// Usage (already wired in users_block.dart):
/// Navigator.push(
///   context,
///   PageRouteBuilder(
///     pageBuilder: (_, __, ___) => const InstructorDetailsPage(),
///     settings: RouteSettings(arguments: {'uid': instructorUid}),
///   ),
/// );

class InstructorDetailsPage extends StatefulWidget {
  const InstructorDetailsPage({super.key});

  @override
  State<InstructorDetailsPage> createState() => _InstructorDetailsPageState();
}

class _InstructorDetailsPageState extends State<InstructorDetailsPage> {
  final _db = FirebaseFirestore.instance;

  String? _uid; // from RouteSettings.arguments
  bool _loading = true;
  Map<String, dynamic> _user = {}; // users/{uid}
  Map<String, dynamic> _profile = {}; // instructor_profiles/{uid}
  String _status = 'active';

  // search in uploads
  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busyDelete = false;
  bool _busyApprove = false; // approve busy
  bool _busyBlock = false; // NEW: block busy

  // Cloudinary (same as my_uploads.dart)
  static const String _cloudName = 'dxeunc4vd';
  static const String _hostingerBase =
      'https://tajdrivingschool.in/smartDrive/cloudinary';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_uid != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map &&
        args['uid'] is String &&
        (args['uid'] as String).isNotEmpty) {
      _uid = args['uid'] as String;
      _load();
    } else {
      _loading = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing instructor UID')),
        );
        Navigator.of(context).pop();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = _uid!;
      final u = await _db.collection('users').doc(uid).get();
      final p = await _db.collection('instructor_profiles').doc(uid).get();
      _user = u.data() ?? {};
      _profile = p.data() ?? {};
      _status = (_user['status'] ?? 'active').toString();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _payoutIncomplete {
    // If no profile at all → incomplete
    if (_profile.isEmpty) return true;

    // Check personal stuff minimally (phone/address often needed for payout KYC)
    final phone = (_user['phone'] ?? '').toString().trim();
    final addr = (_profile['address'] as Map<String, dynamic>?) ?? {};
    final hasSomeAddress = [
      addr['street'],
      addr['city'],
      addr['state'],
      addr['zip'],
      addr['country']
    ].any((v) => v != null && v.toString().trim().isNotEmpty);

    final pay = (_profile['payment'] as Map<String, dynamic>?) ?? {};
    final method = (pay['method'] ?? '').toString();

    bool payOk = false;
    if (method == 'bank') {
      final bank = (pay['bank'] as Map<String, dynamic>?) ?? {};
      payOk = _nonEmpty(bank['bankName']) &&
          _nonEmpty(bank['accountHolder']) &&
          _nonEmpty(bank['accountNumber']) &&
          _nonEmpty(bank['routingNumber']);
    } else if (method == 'upi') {
      final upi = (pay['upi'] as Map<String, dynamic>?) ?? {};
      payOk = _nonEmpty(upi['id']) && upi['id'].toString().contains('@');
    }

    return !(payOk && phone.isNotEmpty && hasSomeAddress);
  }

  bool _nonEmpty(dynamic v) => v != null && v.toString().trim().isNotEmpty;

  // ───────────────────────── uploads query ─────────────────────────
  Query<Map<String, dynamic>> _uploadsQuery() =>
      _db.collection('user_uploads').where('uid', isEqualTo: _uid);

  // ───────────────────── Cloudinary destroy (with fallback) ─────────────────────
  Future<void> _confirmDeleteAndDestroy({
    required String docId,
    required String folder,
    required String publicIdBase,
    required String fileExt,
    required String fileUrl,
  }) async {
    if (_busyDelete) return;

    if (folder.trim().isEmpty || publicIdBase.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Delete failed: missing Cloudinary folder/public_id')),
      );
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete document?'),
            content: const Text(
                'This will permanently delete the file from Cloudinary and remove the record from Firestore.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      setState(() => _busyDelete = true);

      final fullPublicId = _composePublicId(folder, publicIdBase);
      final primaryType = _resourceTypeFromUrl(fileUrl) ?? _resourceTypeFromExt(fileExt);

      await _cloudinaryDestroyWithFallback(
        fullPublicId: fullPublicId,
        primaryType: primaryType,
      );

      await _db.collection('user_uploads').doc(docId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Deleted successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyDelete = false);
    }
  }

  String _composePublicId(String folder, String publicId) {
    final f = folder.replaceAll(RegExp(r'/+$'), '');
    final p = publicId.replaceAll(RegExp(r'^/+'), '');
    return f.isEmpty ? p : '$f/$p';
  }

  String? _resourceTypeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('/image/upload/')) return 'image';
    if (u.contains('/raw/upload/')) return 'raw';
    if (u.contains('/video/upload/')) return 'video';
    return null;
  }

  String _resourceTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'svg']
        .contains(e)) return 'image';
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(e)) return 'video';
    return 'raw';
  }

  Future<Map<String, dynamic>> _getSignatureForDestroy({
    required String fullPublicId,
  }) async {
    final uri = Uri.parse('$_hostingerBase/signature.php');
    final body = {
      'op': 'destroy',
      'public_id': fullPublicId.replaceAll(RegExp(r'\s+'), ''),
      'invalidate': 'true',
    };
    final res = await http.post(uri, body: body);
    if (res.statusCode != 200) {
      throw Exception('Signature server error: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['signature'] == null ||
        json['api_key'] == null ||
        json['timestamp'] == null) {
      throw Exception('Invalid signature response: $json');
    }
    return json;
  }

  Future<String> _cloudinaryDestroyOnce({
    required String fullPublicId,
    required String resourceType, // image|raw|video
    required Map<String, dynamic> signed,
  }) async {
    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy');
    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = signed['api_key'].toString()
      ..fields['timestamp'] = signed['timestamp'].toString()
      ..fields['signature'] = signed['signature'].toString()
      ..fields['public_id'] = fullPublicId.replaceAll(RegExp(r'\s+'), '')
      ..fields['invalidate'] = 'true';

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary destroy failed: ${streamed.statusCode} $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    final result = (json['result'] ?? '').toString();
    return result.isEmpty ? 'error' : result; // 'ok', 'not found', etc.
  }

  Future<void> _cloudinaryDestroyWithFallback({
    required String fullPublicId,
    required String primaryType,
  }) async {
    final signed = await _getSignatureForDestroy(fullPublicId: fullPublicId);
    final candidates = <String>[
      primaryType,
      if (primaryType != 'image') 'image',
      if (primaryType != 'raw') 'raw',
      if (primaryType != 'video') 'video',
    ];

    for (final t in candidates) {
      final result = await _cloudinaryDestroyOnce(
        fullPublicId: fullPublicId,
        resourceType: t,
        signed: signed,
      );
      if (result == 'ok') return;
      if (result != 'not found') {
        throw Exception('Cloudinary destroy unexpected result: {$result}');
      }
    }
    throw Exception(
        'Cloudinary destroy did not find the asset under any resource_type.');
  }

  // ───────────────────── Notifications helper (direct-target) ─────────────────
  Future<void> _sendUserNotification({
    required String targetUid,
    required String title,
    required String message,
    String segment = 'instructors', // keeps compatibility with segment filter
    String? actionUrl,
  }) async {
    await _db.collection('notifications').add({
      'title': title,
      'message': message,
      'segments': [segment], // optional legacy segment
      'target_uids': [targetUid], // direct target for bell filter
      'action_url': actionUrl,
      'created_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _approveUser() async {
    if (_uid == null || _busyApprove) return;
    try {
      setState(() => _busyApprove = true);
      await _db.collection('users').doc(_uid!).update({'status': 'active'});
      setState(() => _status = 'active');

      // Optional: let the instructor know
      await _sendUserNotification(
        targetUid: _uid!,
        title: 'Account Approved',
        message: 'Your instructor account has been approved. Welcome aboard!',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Instructor approved and activated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to approve: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyApprove = false);
    }
  }

  // NEW: Block an active instructor
  Future<void> _blockUser() async {
    if (_uid == null || _busyBlock) return;

    final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Block instructor?'),
            content: const Text(
              'This will set the instructor’s status to BLOCKED and restrict access. '
              'You can unblock later from the user management screen.',
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Block'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirm) return;

    try {
      setState(() => _busyBlock = true);
      await _db.collection('users').doc(_uid!).update({'status': 'blocked'});
      setState(() => _status = 'blocked');

      await _sendUserNotification(
        targetUid: _uid!,
        title: 'Account Blocked',
        message: 'Your instructor account has been blocked. Please contact support.',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Instructor has been blocked')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to block user: $e')));
      }
    } finally {
      if (mounted) setState(() => _busyBlock = false);
    }
  }

  // ───────────────────────────── UI ─────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        title: const Text('Instructor Details'),
        backgroundColor: context.c.surface,
        foregroundColor: context.c.onSurface,
        elevation: 0.5,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(context.c.primary),
              ),
            )
          : LayoutBuilder(
              builder: (context, c) {
                final isWide = c.maxWidth >= 980;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeaderCard(
                            name: (_user['name'] ?? 'Instructor').toString(),
                            email: (_user['email'] ?? '').toString(),
                            phone: (_user['phone'] ?? '').toString(),
                            active: _status.toLowerCase() == 'active',
                          ),
                          const SizedBox(height: 12),

                          // Pending → Approve
                          if (_status.toLowerCase() == 'pending')
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.warnBg,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.m),
                                border: Border.all(color: AppColors.warnBg.withOpacity(0.9)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.hourglass_bottom_rounded,
                                      color: AppColors.warning),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'This instructor is pending approval.',
                                      style: context.t.bodyMedium
                                          ?.copyWith(color: AppColors.warnFg),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed:
                                        _busyApprove ? null : _approveUser,
                                    icon: _busyApprove
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation(
                                                      context.c.onPrimary),
                                            ),
                                          )
                                        : const Icon(Icons.check_circle_outline),
                                    label: Text(
                                        _busyApprove ? 'Approving…' : 'Approve User'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.success,
                                      foregroundColor: context.c.onPrimary,
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(AppRadii.m)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // ACTIVE → Block (NEW)
                          if (_status.toLowerCase() == 'active')
                            Container(
                              margin: const EdgeInsets.only(top: 0),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.errBg,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.m),
                                border: Border.all(color: AppColors.errBg.withOpacity(0.9)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.verified_user_outlined,
                                      color: AppColors.danger),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'This instructor is active. You can block access if needed.',
                                      style: context.t.bodyMedium?.copyWith(color: AppColors.errFg),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _busyBlock ? null : _blockUser,
                                    icon: _busyBlock
                                        ? SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation(context.c.onPrimary),
                                            ),
                                          )
                                        : const Icon(Icons.block),
                                    label: Text(_busyBlock ? 'Blocking…' : 'Block User'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.danger,
                                      foregroundColor: context.c.onPrimary,
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(AppRadii.m)),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 12),

                          if (_payoutIncomplete)
                            _BannerWarning(
                              text:
                                  'Payout will not be processed: Personal information or payment preferences are not fully set.',
                            ),

                          const SizedBox(height: 12),

                          if (isWide)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _ProfileCard(user: _user, profile: _profile)),
                                const SizedBox(width: 16),
                                Expanded(child: _PayoutCard(profile: _profile)),
                              ],
                            )
                          else ...[
                            _ProfileCard(user: _user, profile: _profile),
                            const SizedBox(height: 16),
                            _PayoutCard(profile: _profile),
                          ],

                          const SizedBox(height: 20),
                          _SectionTitle(
                            icon: Icons.upload_file_rounded,
                            title: 'Documents',
                            subtitle: 'Uploads from this instructor',
                          ),
                          const SizedBox(height: 8),
                          _SearchField(
                            controller: _searchCtrl,
                            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                            hint: 'Search documents...',
                          ),
                          const SizedBox(height: 10),
                          _UploadsList(
                            query: _uploadsQuery(),
                            filterText: _q,
                            onView: _openUrl,
                            onDownload: (url) => _openUrl(url, download: true),
                            onDelete: (docId, folder, publicId, fileExt, fileUrl) =>
                                _confirmDeleteAndDestroy(
                              docId: docId,
                              folder: folder,
                              publicIdBase: publicId,
                              fileExt: fileExt,
                              fileUrl: fileUrl,
                            ),
                            showDelete: true,
                            busy: _busyDelete,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _openUrl(String url, {bool download = false}) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// ────────────────────── Header & Sections ──────────────────────

class _HeaderCard extends StatelessWidget {
  final String name;
  final String email;
  final String phone;
  final bool active;
  const _HeaderCard({
    required this.name,
    required this.email,
    required this.phone,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: context.c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: AppColors.brand,
              child: Text(
                _initials(name),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: AppText.sectionTitle.copyWith(color: context.c.onSurface)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Text(email,
                            style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text('•', style: TextStyle(color: context.c.onSurface.withOpacity(.35))),
                        const SizedBox(width: 10),
                        Text(phone,
                            style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: active ? AppColors.okBg : AppColors.neuBg,
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? AppColors.success : AppColors.onSurfaceMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    active ? 'Active' : 'Inactive',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? AppColors.okFg : AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          decoration:
              BoxDecoration(color: AppColors.neuBg, borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: context.c.primary, size: 18),
        ),
        const SizedBox(width: 8),
        Text(title, style: AppText.sectionTitle.copyWith(color: context.c.onSurface)),
        const Spacer(),
        if (subtitle != null)
          Text(subtitle!, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
      ],
    );
  }
}

class _BannerWarning extends StatelessWidget {
  final String text;
  const _BannerWarning({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warnBg,
        borderRadius: BorderRadius.circular(AppRadii.m),
        border: Border.all(color: AppColors.warnBg.withOpacity(0.95)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: context.t.bodyMedium?.copyWith(color: AppColors.warnFg)),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  const _ProfileCard({required this.user, required this.profile});

  @override
  Widget build(BuildContext context) {
    final addr = (profile['address'] as Map<String, dynamic>?) ?? {};
    final street = (addr['street'] ?? '').toString();
    final city = (addr['city'] ?? '').toString();
    final state = (addr['state'] ?? '').toString();
    final zip = (addr['zip'] ?? '').toString();
    final country = (addr['country'] ?? '').toString();

    return Card(
      elevation: 0,
      color: context.c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Profile', style: AppText.sectionTitle.copyWith(color: context.c.onSurface)),
            const SizedBox(height: 10),
            _line('Name', (user['name'] ?? '—').toString()),
            _line('Email', (user['email'] ?? '—').toString()),
            _line('Phone', (user['phone'] ?? '—').toString()),
            const SizedBox(height: 8),
            Divider(color: AppColors.divider),
            const SizedBox(height: 8),
            Text('Address', style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
            const SizedBox(height: 8),
            Text(
              _joinLines([street, _joinComma([city, state, zip]), country]),
              style: AppText.tileSubtitle.copyWith(color: context.c.onSurface),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child:
                  Text(label, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted))),
          const SizedBox(width: 12),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String _joinComma(List<String> parts) =>
      parts.where((e) => e.trim().isNotEmpty).join(', ');
  String _joinLines(List<String> parts) =>
      parts.where((e) => e.trim().isNotEmpty).join('\n');
}

class _PayoutCard extends StatelessWidget {
  final Map<String, dynamic> profile;
  const _PayoutCard({required this.profile});

  @override
  Widget build(BuildContext context) {
    final pay = (profile['payment'] as Map<String, dynamic>?) ?? {};
    final method = (pay['method'] ?? '').toString();

    String methodText = 'Not configured';
    String detailA = '—';
    String detailB = '';

    if (method == 'bank') {
      final bank = (pay['bank'] as Map<String, dynamic>?) ?? {};
      methodText = 'Bank Transfer';
      detailA = (bank['bankName'] ?? '—').toString();
      final masked = _maskAccount((bank['accountNumber'] ?? '').toString());
      final ifsc = (bank['routingNumber'] ?? '').toString();
      detailB = '$masked  •  IFSC: ${ifsc.isEmpty ? '—' : ifsc}';
    } else if (method == 'upi') {
      final upi = (pay['upi'] as Map<String, dynamic>?) ?? {};
      methodText = 'UPI';
      final id = (upi['id'] ?? '').toString();
      detailA = _maskUPI(id);
      detailB = id.isEmpty ? '' : 'UPI for payouts';
    }

    return Card(
      elevation: 0,
      color: context.c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.l)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Payout Preference',
                style: AppText.sectionTitle.copyWith(color: context.c.onSurface)),
            const SizedBox(height: 10),
            _kv('Method', methodText),
            const SizedBox(height: 6),
            _kv('Primary', detailA),
            if (detailB.isNotEmpty) ...[
              const SizedBox(height: 6),
              _kv('Notes', detailB),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
            width: 120,
            child: Text(k, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted))),
        const SizedBox(width: 12),
        Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }

  String _maskAccount(String? n) {
    final s = (n ?? '').trim();
    if (s.length <= 4) return '••••';
    return '•••• ${s.substring(s.length - 4)}';
  }

  String _maskUPI(String? id) {
    final s = (id ?? '').trim();
    if (s.isEmpty) return '—';
    final at = s.indexOf('@');
    if (at <= 1) return '••••@${at >= 0 ? s.substring(at + 1) : 'upi'}';
    return '${s[0]}••••${s[at - 1]}${s.substring(at)}';
  }
}

/// ─────────────────────── Uploads (inline) ───────────────────────

class _UploadsList extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final String filterText;
  final void Function(String url) onView;
  final void Function(String url) onDownload;
  final void Function(String docId, String folder, String publicIdBase, String fileExt, String fileUrl)
      onDelete;
  final bool showDelete;
  final bool busy;

  const _UploadsList({
    required this.query,
    required this.filterText,
    required this.onView,
    required this.onDownload,
    required this.onDelete,
    required this.showDelete,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Could not load uploads: ${snap.error}',
                style: TextStyle(color: AppColors.danger)),
          );
        }

        final docs = snap.data?.docs ?? const [];
        final sorted = [...docs]..sort((a, b) {
            final ta = a.data()['created_at'];
            final tb = b.data()['created_at'];
            final da = (ta is Timestamp) ? ta.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            final db = (tb is Timestamp) ? tb.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
            return db.compareTo(da);
          });

        final q = filterText.trim().toLowerCase();
        final filtered = sorted.where((d) {
          if (q.isEmpty) return true;
          final m = d.data();
          final name = (m['document_name'] ?? '').toString().toLowerCase();
          final file = (m['file_name'] ?? '').toString().toLowerCase();
          final remarks = (m['remarks'] ?? '').toString().toLowerCase();
          return name.contains(q) || file.contains(q) || remarks.contains(q);
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Text(
                '${docs.length} document${docs.length == 1 ? '' : 's'} uploaded',
                style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted),
              ),
            ),
            if (filtered.isEmpty)
              const _EmptyHint()
            else
              ListView.separated(
                physics: const NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final d = filtered[i];
                  final m = d.data();

                  final folder = (m['cloudinary_folder'] ?? '').toString();
                  final publicIdBase = (m['cloudinary_public_id'] ?? '').toString();
                  final url = (m['cloudinary_url'] ?? '').toString();
                  final fileExt = (m['file_ext'] ?? '').toString();

                  return _UploadCard(
                    docId: d.id,
                    name: (m['document_name'] ?? '-').toString(),
                    fileName: (m['file_name'] ?? '').toString(),
                    url: url,
                    createdAt: m['created_at'],
                    sizeBytes: ((m['file_size'] as num?) ?? 0).toInt(),
                    remarks: (m['remarks'] ?? '').toString(),
                    onView: () => onView(url),
                    onDownload: () => onDownload(url),
                    onDelete: !showDelete || busy
                        ? null
                        : () => onDelete(d.id, folder, publicIdBase, fileExt, url),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  const _SearchField({required this.controller, required this.onChanged, this.hint = 'Search...'});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search, color: context.c.onSurface.withOpacity(0.6)),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true,
        fillColor: context.c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.m),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.m),
          borderSide: BorderSide(color: AppColors.divider),
        ),
      ),
    );
  }
}

class _UploadCard extends StatelessWidget {
  final String docId;
  final String name;
  final String fileName;
  final String url;
  final dynamic createdAt; // Timestamp or DateTime
  final int sizeBytes;
  final String remarks;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback? onDelete;

  const _UploadCard({
    required this.docId,
    required this.name,
    required this.fileName,
    required this.url,
    required this.createdAt,
    required this.sizeBytes,
    required this.remarks,
    required this.onView,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ext = _ext(fileName);
    final icon = _fileIcon(ext);
    final date = _fmtDate(createdAt);
    final size = _fmtSize(sizeBytes);

    return Card(
      elevation: 0,
      color: context.c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.neuBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 20, color: context.c.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: AppText.tileTitle.copyWith(color: context.c.onSurface)),
                      const SizedBox(height: 2),
                      Text(fileName, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 14, color: AppColors.onSurfaceMuted),
                          const SizedBox(width: 6),
                          Text(date, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
                          const SizedBox(width: 14),
                          Text(size, style: AppText.tileSubtitle.copyWith(color: AppColors.onSurfaceMuted)),
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
                  color: AppColors.neuBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Remarks: ',
                        style: TextStyle(fontWeight: FontWeight.w600, color: context.c.onSurface)),
                    Expanded(
                      child: Text(remarks,
                          style: TextStyle(color: context.c.onSurface, height: 1.2)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            // Actions
            Row(
              children: [
                TextButton.icon(
                  onPressed: onView,
                  icon: Icon(Icons.visibility_outlined, size: 18, color: context.c.primary),
                  label: Text('View', style: TextStyle(color: context.c.primary)),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDownload,
                  icon: Icon(Icons.download_rounded, size: 18, color: context.c.onSurface),
                  label: Text('Download', style: TextStyle(color: context.c.onSurface)),
                ),
                const Spacer(),
                if (onDelete != null)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                    label: Text('Delete', style: TextStyle(color: AppColors.danger)),
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
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 48, color: AppColors.onSurfaceFaint),
            const SizedBox(height: 8),
            Text('No uploads yet', style: AppText.hintSmall.copyWith(color: AppColors.onSurfaceMuted)),
          ],
        ),
      ),
    );
  }
}

/// ───────────────────────── Helpers ─────────────────────────

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return 'IN';
  if (parts.length == 1) {
    final s = parts.first;
    return (s.length >= 2 ? s.substring(0, 2) : s).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
}
