// my_uploads.dart
// Lists user's uploads from `user_uploads` with search and delete.
// Delete uses Cloudinary 'destroy' signed via your PHP (op=destroy).
// Robustness: detects resource_type from URL and falls back if "not found".

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import 'upload_document_page.dart';

class MyUploadsPage extends StatefulWidget {
  const MyUploadsPage({super.key});

  @override
  State<MyUploadsPage> createState() => _MyUploadsPageState();
}

class _MyUploadsPageState extends State<MyUploadsPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _searchCtrl = TextEditingController();
  String _q = '';
  bool _busy = false;

  // Cloudinary config
  static const String _cloudName = 'dxeunc4vd';
  static const String _hostingerBase =
      'https://tajdrivingschool.in/smartDrive/cloudinary';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // No orderBy; sort client-side to avoid composite index.
  Query<Map<String, dynamic>> _baseQuery(String uid) {
    return _db.collection('user_uploads').where('uid', isEqualTo: uid);
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('You must be signed in.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('My Uploads'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Upload new',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UploadDocumentPage()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          // search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: _SearchField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _baseQuery(user.uid).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Could not load uploads: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? const [];

                // Sort client-side by created_at desc (nulls last)
                final sorted = [...docs]..sort((a, b) {
                    final ma = a.data();
                    final mb = b.data();
                    final ta = ma['created_at'];
                    final tb = mb['created_at'];
                    final da = (ta is Timestamp)
                        ? ta.toDate()
                        : (ta is DateTime ? ta : DateTime.fromMillisecondsSinceEpoch(0));
                    final dbb = (tb is Timestamp)
                        ? tb.toDate()
                        : (tb is DateTime ? tb : DateTime.fromMillisecondsSinceEpoch(0));
                    return dbb.compareTo(da);
                  });

                // filter
                final filtered = sorted.where((d) {
                  if (_q.isEmpty) return true;
                  final m = d.data();
                  final name = (m['document_name'] ?? '').toString().toLowerCase();
                  final file = (m['file_name'] ?? '').toString().toLowerCase();
                  final remarks = (m['remarks'] ?? '').toString().toLowerCase();
                  return name.contains(_q) || file.contains(_q) || remarks.contains(_q);
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(
                        '${docs.length} document${docs.length == 1 ? '' : 's'} uploaded',
                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                    Expanded(
                      child: filtered.isEmpty
                          ? const _EmptyHint()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, i) {
                                final d = filtered[i];
                                final m = d.data();

                                final folder = (m['cloudinary_folder'] ?? '').toString();
                                final publicIdBase =
                                    (m['cloudinary_public_id'] ?? '').toString();
                                final url = (m['cloudinary_url'] ?? '').toString();

                                return _UploadCard(
                                  docId: d.id,
                                  name: (m['document_name'] ?? '-').toString(),
                                  fileName: (m['file_name'] ?? '').toString(),
                                  url: url,
                                  createdAt: m['created_at'],
                                  sizeBytes: ((m['file_size'] as num?) ?? 0).toInt(),
                                  remarks: (m['remarks'] ?? '').toString(),
                                  folder: folder,
                                  publicIdBase: publicIdBase,
                                  fileExt: (m['file_ext'] ?? '').toString(),
                                  onView: () => _openUrl(url),
                                  onDownload: () => _openUrl(url, download: true),
                                  onDelete: () => _confirmDeleteAndDestroy(
                                    docId: d.id,
                                    folder: folder,
                                    publicIdBase: publicIdBase,
                                    fileExt: (m['file_ext'] ?? '').toString(),
                                    fileUrl: url, // used to infer resource_type
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ───────────── Delete: sign, detect resource type, fallbacks ─────────────

  Future<void> _confirmDeleteAndDestroy({
    required String docId,
    required String folder,
    required String publicIdBase,
    required String fileExt,
    required String fileUrl,
  }) async {
    if (_busy) return;

    if (folder.trim().isEmpty || publicIdBase.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delete failed: missing Cloudinary folder/public_id')),
      );
      return;
    }

    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete document?'),
            content: const Text(
              'This will permanently delete the file from Cloudinary and remove the record from Firestore.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    try {
      setState(() => _busy = true);

      final fullPublicId = _composePublicId(folder, publicIdBase);

      // Detect resource_type from URL first; fallback to extension mapping.
      String detected = _resourceTypeFromUrl(fileUrl) ?? _resourceTypeFromExt(fileExt);

      await _cloudinaryDestroyWithFallback(
        fullPublicId: fullPublicId,
        primaryType: detected,
      );

      // Remove Firestore record
      await _db.collection('user_uploads').doc(docId).delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Guess from URL like:
  // https://res.cloudinary.com/<cloud>/image/upload/v.../path
  String? _resourceTypeFromUrl(String url) {
    final u = url.toLowerCase();
    if (u.contains('/image/upload/')) return 'image';
    if (u.contains('/raw/upload/')) return 'raw';
    if (u.contains('/video/upload/')) return 'video';
    return null;
  }

  // Fallback mapping by extension
  String _resourceTypeFromExt(String ext) {
    final e = ext.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'svg'].contains(e)) {
      return 'image';
    }
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(e)) return 'video';
    return 'raw'; // pdf/doc/etc.
  }

  // Try primary resource type, then fall back through others if {result: "not found"}
  Future<void> _cloudinaryDestroyWithFallback({
    required String fullPublicId,
    required String primaryType,
  }) async {
    final signed = await _getSignatureForDestroy(fullPublicId: fullPublicId);

    // Build try-order with primary first, then the others.
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
      if (result == 'ok') return; // success
      if (result != 'not found') {
        // Any other result ('error', 'already deleted', etc.) -> stop and throw
        throw Exception('Cloudinary destroy unexpected result: {$result}');
      }
      // else continue to next candidate
    }
    throw Exception('Cloudinary destroy did not find the asset under any resource_type.');
  }

  Future<String> _cloudinaryDestroyOnce({
    required String fullPublicId,
    required String resourceType, // image|raw|video
    required Map<String, dynamic> signed,
  }) async {
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/destroy');

    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key']    = signed['api_key'].toString()
      ..fields['timestamp']  = signed['timestamp'].toString()
      ..fields['signature']  = signed['signature'].toString()
      ..fields['public_id']  = _clean(fullPublicId)
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

  // ───────────── Signer for destroy (op=destroy, invalidate=true) ─────────────

  String _clean(String s) => s.replaceAll(RegExp(r'\s+'), '');

  String _composePublicId(String folder, String publicId) {
    final f = folder.replaceAll(RegExp(r'/+$'), '');
    final p = publicId.replaceAll(RegExp(r'^/+'), '');
    return f.isEmpty ? p : '$f/$p';
  }

  Future<Map<String, dynamic>> _getSignatureForDestroy({
    required String fullPublicId,
  }) async {
    final uri = Uri.parse('$_hostingerBase/signature.php');
    final body = {
      'op': 'destroy',
      'public_id': _clean(fullPublicId), // FULL id (incl. folder)
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

  // Open in external browser/app.
  Future<void> _openUrl(String url, {bool download = false}) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// ─────────────────────────── UI widgets ───────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search documents...',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

class _UploadCard extends StatelessWidget {
  final String docId;
  final String name;
  final String fileName;
  final String url;
  final dynamic createdAt; // Timestamp or DateTime
  final int sizeBytes;
  final String remarks;
  final String folder;
  final String publicIdBase;
  final String fileExt;
  final VoidCallback onView;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _UploadCard({
    required this.docId,
    required this.name,
    required this.fileName,
    required this.url,
    required this.createdAt,
    required this.sizeBytes,
    required this.remarks,
    required this.folder,
    required this.publicIdBase,
    required this.fileExt,
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
      color: Colors.white,
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
                    color: const Color(0xFFEFF3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 20, color: const Color(0xFF3559FF)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(fileName, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 14, color: Colors.black54),
                          const SizedBox(width: 6),
                          Text(date, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                          const SizedBox(width: 14),
                          Text(size, style: const TextStyle(color: Colors.black54, fontSize: 12)),
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
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Remarks: ',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black87)),
                    Expanded(
                      child: Text(remarks, style: const TextStyle(color: Colors.black87, height: 1.2)),
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
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFD32F2F)),
                  label: const Text('Delete', style: TextStyle(color: Color(0xFFD32F2F))),
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
          children: const [
            Icon(Icons.folder_open, size: 48, color: Colors.black26),
            SizedBox(height: 8),
            Text('No uploads yet', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
