// lib/materials_block.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';

import 'ui_common.dart'; // AppCard, SectionHeader, DataTableWrap, field(...), area(...), confirmDialog(...)

/// MaterialsBlock (Signed Cloudinary upload for ANY file type; stored under smartDrive/materials)
class MaterialsBlock extends StatefulWidget {
  const MaterialsBlock({super.key});

  @override
  State<MaterialsBlock> createState() => _MaterialsBlockState();
}

class _MaterialsBlockState extends State<MaterialsBlock> {
  // ── Config ─────────────────────────────────────────────────────────────────
  static const String _cloudName = 'dxeunc4vd'; // <-- your Cloudinary cloud name
  static const String _baseFolder = 'smartDrive/materials';
  static const String _host = 'tajdrivingschool.in';
  static const String _basePath = '/smartDrive/cloudinary';

  Uri _api(String endpoint) => Uri.https(_host, '$_basePath/$endpoint');

  // ── Form & state ───────────────────────────────────────────────────────────
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _versionCtrl = TextEditingController(text: '1.0');

  String _category = 'Theory';
  PlatformFile? _picked;
  String? _pickedPath; // for non-web

  bool _isUploading = false;
  bool _saving = false; // double-click guard
  double _progress = 0.0; // visual only
  String? _uploadedUrl;

  DocumentReference<Map<String, dynamic>>? _editingRef;
  int _editingDownloads = 0;

  static const List<String> _categories = [
    'Theory',
    'Practical Driving',
    'Traffic Rules',
    'Road Signs',
    'Safety Guidelines',
    'Vehicle Maintenance',
    'Mock Tests',
    'Highway Code',
  ];

  // ── Utils ──────────────────────────────────────────────────────────────────
  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  String _sanitizeParam(String s) => s.trim();

  String? _validateVersion(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Version is required';
    final ok = RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(s); // 1 | 1.0 | 2.1.3
    return ok ? null : 'Use version like 1, 1.0 or 2.1.3';
  }

  String _resourceTypeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    const img = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'heic', 'svg'];
    const vid = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'];
    if (img.contains(ext)) return 'image';
    if (vid.contains(ext)) return 'video';
    // PDFs and everything else => raw
    return 'raw';
  }

  // ── Server: signature ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _getSignature({
    required String publicId,
    required String folder,
    required String resourceType, // NEW
    String overwrite = 'true',
  }) async {
    final res = await http
        .post(_api('signature.php'), body: {
          'public_id': _sanitizeParam(publicId),
          'folder': _sanitizeParam(folder),
          'overwrite': overwrite,
          'resource_type': resourceType, // ensure your PHP includes this in the signature
        })
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Signature server error: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['signature'] == null || json['api_key'] == null || json['timestamp'] == null) {
      throw Exception('Invalid signature response: $json');
    }
    return json;
  }

  // ── Server: delete Cloudinary asset ────────────────────────────────────────
  Future<void> _deleteFromCloudinary({
    required String publicId,
    required String resourceType, // image | video | raw
  }) async {
    final res = await http
        .post(_api('delete.php'), body: {
          'public_id': publicId,
          'resource_type': resourceType.isEmpty ? 'raw' : resourceType,
        })
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception('Cloudinary delete failed: ${res.statusCode} ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    final result = (json['result'] ?? '').toString();
    if (result != 'ok' && result != 'not found') {
      throw Exception('Cloudinary delete result: $result');
    }
  }

  /// Upload ANY file type to Cloudinary using the correct resource type endpoint.
  Future<Map<String, dynamic>> _uploadToCloudinarySignedAny({
    required PlatformFile file,
    required String publicId,
    required String folder,
    String overwrite = 'true',
  }) async {
    final resourceType = _resourceTypeFor(file.name); // 'image' | 'video' | 'raw'

    final signed = await _getSignature(
      publicId: publicId,
      folder: folder,
      resourceType: resourceType,
      overwrite: overwrite,
    );

    // Use matching endpoint (no /auto/)
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');

    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = signed['api_key'].toString()
      ..fields['timestamp'] = signed['timestamp'].toString()
      ..fields['signature'] = signed['signature'].toString()
      ..fields['public_id'] = _sanitizeParam(publicId)
      ..fields['folder'] = _sanitizeParam(folder)
      ..fields['overwrite'] = overwrite;

    final mediaType = MediaType('application', 'octet-stream');
    final filename = file.name.isNotEmpty ? file.name : 'upload.bin';

    if (kIsWeb) {
      final Uint8List? bytes = file.bytes;
      if (bytes == null) throw Exception('No file bytes available (web)');
      req.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: mediaType,
      ));
    } else {
      final path = file.path ?? _pickedPath;
      if (path == null || path.isEmpty) throw Exception('No file path (mobile)');
      req.files.add(await http.MultipartFile.fromPath(
        'file',
        path,
        filename: filename,
        contentType: mediaType,
      ));
    }

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${streamed.statusCode} $body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance
        .collection('materials')
        .orderBy('created_at', descending: true);

    final isWide = MediaQuery.of(context).size.width >= 980;
    final pagePad = EdgeInsets.symmetric(horizontal: isWide ? 24 : 12, vertical: 12);

    return ListView(
      padding: EdgeInsets.only(bottom: isWide ? 28 : 18),
      children: [
        Padding(
          padding: pagePad,
          child: _HeaderCard(
            title: _editingRef == null ? 'Upload Study Materials' : 'Edit Study Material',
            isEditing: _editingRef != null,
          ),
        ),

        Padding(
          padding: pagePad,
          child: AppCard(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 920;
                final gap = SizedBox(height: wide ? 14 : 10);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTitleAndDescription()),
                          const SizedBox(width: 16),
                          SizedBox(width: 360, child: _buildMetaControls()),
                        ],
                      )
                    else ...[
                      _buildTitleAndDescription(),
                      gap,
                      _buildMetaControls(),
                    ],
                    gap,
                    _buildPickerCard(),
                    if (_isUploading) ...[
                      const SizedBox(height: 12),
                      _buildProgressBar(),
                    ],
                    const SizedBox(height: 12),
                    _ActionsBar(
                      isUploading: _isUploading,
                      isEditing: _editingRef != null,
                      onSave: _saveMaterial,
                      onCancel: _cancelEdit,
                      uploadedUrl: _uploadedUrl,
                      onOpenLatest: _uploadedUrl == null
                          ? null
                          : () {
                              final uri = Uri.tryParse(_uploadedUrl!);
                              if (uri != null) launchUrl(uri, mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication);
                            },
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        const SectionHeader(title: 'Study Materials Library'),
        const Divider(height: 1),

        Padding(
          padding: pagePad,
          child: StreamBuilder<QuerySnapshot>(
            stream: q.snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to load materials: ${snap.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }

              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return _buildEmptyLibrary();
              }

              final rows = <List<Widget>>[];
              for (final d in snap.data!.docs) {
                final m = d.data() as Map<String, dynamic>;
                rows.add([
                  // Title & description
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _asText(m['title']),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_notEmpty(m['description']))
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            _asText(m['description']),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            softWrap: true,
                          ),
                        ),
                    ],
                  ),

                  _CategoryChip(category: _asText(m['category'])),
                  _DetectedTypeBadge(kind: _asText(m['detected_type'])),
                  _Badge(text: _asText(m['version'], fallback: '1.0')),

                  Text(
                    (m['created_at'] is Timestamp)
                        ? (m['created_at'] as Timestamp).toDate().toString().split(' ').first
                        : '-',
                    style: const TextStyle(fontSize: 12),
                  ),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.download, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Text('${m['downloads'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),

                  // Actions
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Tooltip(
                          message: 'Open',
                          child: IconButton(
                            onPressed: () => _openUrl(_asText(m['file_url']), docId: d.id),
                            icon: const Icon(Icons.open_in_new),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        Tooltip(
                          message: 'Edit',
                          child: IconButton(
                            onPressed: () => _editMaterial(d),
                            icon: const Icon(Icons.edit),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        Tooltip(
                          message: 'Delete',
                          child: IconButton(
                            onPressed: () => _deleteMaterial(d),
                            icon: const Icon(Icons.delete_forever),
                            color: Colors.red.shade600,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ]);
              }

              return DataTableWrap(
                columns: const [
                  'Title & Description',
                  'Category',
                  'Type',
                  'Version',
                  'Upload Date',
                  'Downloads',
                  'Actions',
                ],
                rows: rows,
              );
            },
          ),
        ),
      ],
    );
  }

  // ── UI bits ────────────────────────────────────────────────────────────────
  Widget _buildTitleAndDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Material Title'),
        const SizedBox(height: 6),
        field('Title', _titleCtrl),
        const SizedBox(height: 12),
        const _FieldLabel('Description (optional)'),
        const SizedBox(height: 6),
        area('Brief description of the material', _descriptionCtrl),
      ],
    );
  }

  Widget _buildMetaControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _FieldLabel('Category'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _category,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          items: _categories.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
          onChanged: _isUploading ? null : (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: 12),
        const _FieldLabel('Version'),
        const SizedBox(height: 6),
        field('e.g. 1.0 or 2.1.3', _versionCtrl),
        const SizedBox(height: 8),
        const _HintRow(
          icon: Icons.info_outline,
          text: 'Version is shown to students; use semantic versions like 1.0, 1.1, 2.0.',
        ),
      ],
    );
  }

  Widget _buildPickerCard() {
    final name = _picked?.name;
    final selected = name != null;
    final kind = selected ? _detectKind(name!) : _Kind.other;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: selected ? Colors.green.shade200 : Colors.grey.shade300,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? _iconForName(name!) : Icons.cloud_upload_outlined,
                size: 42,
                color: selected ? Colors.green : Colors.grey.shade600,
              ),
              const SizedBox(width: 10),
              if (selected)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.deepPurple.withOpacity(0.25)),
                  ),
                  child: Text(
                    kind.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            selected ? name! : 'Drop a file here or use the button below',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.black87 : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(selected ? 'Change file' : 'Select file'),
              ),
              if (selected)
                TextButton.icon(
                  onPressed: _isUploading
                      ? null
                      : () => setState(() {
                            _picked = null;
                            _pickedPath = null;
                          }),
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const _HintRow(
            icon: Icons.verified_user_outlined,
            text: 'Any format is accepted (image, video, PDF, audio, archives, docs) with correct resource type.',
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: _progress > 0 ? _progress / 100 : null,
          backgroundColor: Colors.grey.shade300,
        ),
        const SizedBox(height: 8),
        Text(
          _progress > 0 ? 'Uploading: ${_progress.toStringAsFixed(1)}%' : 'Uploading…',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildEmptyLibrary() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          children: [
            Icon(Icons.library_books, size: 64, color: Colors.grey.shade500),
            const SizedBox(height: 12),
            const Text(
              'No study materials uploaded yet',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Upload your first file to get started!',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────
  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: kIsWeb,
        allowMultiple: false,
        type: FileType.any,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _picked = result.files.single;
          _pickedPath = (!kIsWeb) ? _picked!.path : null;
        });
      }
    } catch (e) {
      _snack('Error picking file: $e', isError: true);
    }
  }

  Future<void> _saveMaterial() async {
    if (_saving) return; // prevent double-click spam
    _saving = true;

    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack('Title is required', isError: true);
      _saving = false; return;
    }
    final vErr = _validateVersion(_versionCtrl.text);
    if (vErr != null) {
      _snack(vErr, isError: true);
      _saving = false; return;
    }
    if (_editingRef == null && _picked == null) {
      _snack('Please select a file', isError: true);
      _saving = false; return;
    }

    setState(() {
      _isUploading = true;
      _progress = 0.0;
    });

    try {
      // Folder: smartDrive/materials/<category-slug>/<YYYY-MM>
      final month = DateTime.now().month.toString().padLeft(2, '0');
      final folder =
          '$_baseFolder/${_category.toLowerCase().replaceAll(' ', '-')}/${DateTime.now().year}-$month';
      final publicId = '${_slug(title)}_${DateTime.now().millisecondsSinceEpoch}';

      String? fileUrlToSave;
      String? publicIdToSave;
      String? resourceTypeToSave;
      String? detectedKind;

      if (_picked != null) {
        final res = await _uploadToCloudinarySignedAny(
          file: _picked!,
          publicId: publicId,
          folder: folder,
        );

        final returnedRt = (res['resource_type'] ?? '').toString(); // 'raw'|'image'|'video'
        final rawUrl = (res['secure_url'] as String?) ?? (res['url'] as String?);

        // Normalize URL to the correct /{rt}/upload/ segment
        String? finalUrl = rawUrl;
        if (rawUrl != null && returnedRt.isNotEmpty) {
          finalUrl = rawUrl
              .replaceFirst('/image/upload/', '/$returnedRt/upload/')
              .replaceFirst('/video/upload/', '/$returnedRt/upload/')
              .replaceFirst('/raw/upload/',   '/$returnedRt/upload/');
        }

        _uploadedUrl = finalUrl;
        fileUrlToSave = finalUrl;
        publicIdToSave = res['public_id'] as String?;
        resourceTypeToSave = returnedRt; // image | video | raw
        detectedKind = _detectKind(_picked!.name).name;
      }

      final baseData = <String, dynamic>{
        'title': title,
        'description': _descriptionCtrl.text.trim(),
        'category': _category,
        'version': _versionCtrl.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (_editingRef == null) {
        if (_picked == null) throw Exception('No file selected for new material');

        final createData = <String, dynamic>{
          ...baseData,
          'file_url': fileUrlToSave,
          'file_name': _picked!.name,
          'file_size': _picked!.size,
          'detected_type': detectedKind ?? 'other',
          'cloudinary_public_id': publicIdToSave,
          'cloudinary_resource_type': resourceTypeToSave,
          'storage_provider': 'cloudinary',
          'downloads': 0,
          'created_at': FieldValue.serverTimestamp(),
        };
        await FirebaseFirestore.instance.collection('materials').add(createData);
      } else {
        final updateData = <String, dynamic>{...baseData};

        if (fileUrlToSave != null && _picked != null) {
          updateData.addAll({
            'file_url': fileUrlToSave,
            'file_name': _picked!.name,
            'file_size': _picked!.size,
            'detected_type': detectedKind ?? 'other',
            'cloudinary_public_id': publicIdToSave,
            'cloudinary_resource_type': resourceTypeToSave,
            'storage_provider': 'cloudinary',
          });
        }

        updateData['downloads'] = _editingDownloads; // preserve existing
        await _editingRef!.update(updateData);
      }

      _snack('Saved successfully');
    } catch (e) {
      _snack('Error uploading: $e', isError: true);
    } finally {
      _saving = false;
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openUrl(String url, {required String docId}) async {
    try {
      await FirebaseFirestore.instance
          .collection('materials')
          .doc(docId)
          .update({'downloads': FieldValue.increment(1)});
    } catch (_) {}

    if (url.isEmpty) {
      _snack('File URL missing', isError: true);
      return;
    }
    final uri0 = Uri.tryParse(url);
    if (uri0 == null) {
      _snack('Invalid URL', isError: true);
      return;
    }

    // Try swapping to the stored resource_type if needed
    Uri candidate = uri0;
    try {
      final snap = await FirebaseFirestore.instance.collection('materials').doc(docId).get();
      final m = snap.data() as Map<String, dynamic>? ?? {};
      final rt = (m['cloudinary_resource_type'] ?? '').toString(); // 'raw' | 'image' | 'video'
      if (rt.isNotEmpty) {
        final fixed = url
            .replaceFirst('/image/upload/', '/$rt/upload/')
            .replaceFirst('/video/upload/', '/$rt/upload/')
            .replaceFirst('/raw/upload/',   '/$rt/upload/');
        final fixedUri = Uri.tryParse(fixed);
        if (fixedUri != null) candidate = fixedUri;
      }
    } catch (_) {}

    // Optional: quick HEAD probe (some CDNs block HEAD; we still attempt open).
    try {
      final head = await http.head(candidate).timeout(const Duration(seconds: 7));
      if (head.statusCode == 404) {
        _snack('File unavailable (404). It may be private or deleted.', isError: true);
        return;
      }
    } catch (_) {}

    final mode = kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication;
    final ok = await launchUrl(candidate, mode: mode);
    if (!ok) _snack('Could not open file', isError: true);
  }

  Future<void> _deleteMaterial(DocumentSnapshot doc) async {
    final data = (doc.data() ?? {}) as Map<String, dynamic>;
    final title = _asText(data['title'], fallback: 'Unknown');
    final publicId = _asText(data['cloudinary_public_id']);
    final resourceType = _asText(data['cloudinary_resource_type'], fallback: 'raw');

    final ok = await confirmDialog(
      context: context,
      message:
          'Delete "$title"?\nThis removes the Firestore record and the Cloudinary file.',
    );
    if (!ok) return;

    setState(() => _isUploading = true);
    try {
      if (publicId.isNotEmpty) {
        await _deleteFromCloudinary(publicId: publicId, resourceType: resourceType);
      }
      await doc.reference.delete();

      if (_editingRef?.id == doc.id) _resetForm();

      _snack('Material deleted');
    } catch (e) {
      _snack('Delete failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _editMaterial(DocumentSnapshot doc) {
    final data = (doc.data() ?? {}) as Map<String, dynamic>;
    _titleCtrl.text = _asText(data['title']);
    _descriptionCtrl.text = _asText(data['description']);
    _versionCtrl.text = _asText(data['version'], fallback: '1.0');
    setState(() {
      _category = _asText(data['category'], fallback: 'Theory');
      _editingRef = doc.reference as DocumentReference<Map<String, dynamic>>?;
      _editingDownloads = (data['downloads'] is num) ? (data['downloads'] as num).toInt() : 0;
      _picked = null;
      _pickedPath = null;
      _uploadedUrl = _asText(data['file_url']);
      _progress = 0.0;
    });
    _snack('Edit mode: update fields and press "Update Material"');
  }

  void _cancelEdit() {
    _resetForm();
    _snack('Edit cancelled');
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ]),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _resetForm() {
    _titleCtrl.clear();
    _descriptionCtrl.clear();
    _versionCtrl.text = '1.0';
    setState(() {
      _category = 'Theory';
      _picked = null;
      _pickedPath = null;
      _uploadedUrl = null;
      _progress = 0.0;
      _editingRef = null;
      _editingDownloads = 0;
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _iconForName(String name) {
    final kind = _detectKind(name);
    switch (kind) {
      case _Kind.image:
        return Icons.image_outlined;
      case _Kind.video:
        return Icons.video_file;
      case _Kind.pdf:
        return Icons.picture_as_pdf;
      case _Kind.audio:
        return Icons.audiotrack;
      case _Kind.archive:
        return Icons.archive_outlined;
      case _Kind.doc:
        return Icons.description_outlined;
      case _Kind.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  _Kind _detectKind(String name) {
    final ext = name.split('.').last.toLowerCase();
    const images = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'tiff', 'heic', 'svg'];
    const videos = ['mp4', 'mov', 'avi', 'mkv', 'webm', 'flv'];
    const audios = ['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg'];
    const archives = ['zip', 'rar', '7z', 'tar', 'gz'];
    const docs = ['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'txt', 'rtf'];
    if (ext == 'pdf') return _Kind.pdf;
    if (images.contains(ext)) return _Kind.image;
    if (videos.contains(ext)) return _Kind.video;
    if (audios.contains(ext)) return _Kind.audio;
    if (archives.contains(ext)) return _Kind.archive;
    if (docs.contains(ext)) return _Kind.doc;
    return _Kind.other;
  }

  String _asText(dynamic v, {String fallback = ''}) => (v == null) ? fallback : v.toString();
  bool _notEmpty(dynamic v) => _asText(v).trim().isNotEmpty;
}

// ── Decorative & micro-UI widgets ────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final String title;
  final bool isEditing;
  const _HeaderCard({required this.title, required this.isEditing});

  @override
  Widget build(BuildContext context) {
    final gradient = const LinearGradient(
      colors: [Color(0xFFEDE7F6), Color(0xFFE3F2FD)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
        boxShadow: [BoxShadow(color: Colors.black26.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Icon(isEditing ? Icons.edit_note : Icons.cloud_upload_outlined, color: Colors.deepPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Tooltip(
            message: 'Uploads go to Cloudinary with correct resource_type. Large files supported.',
            child: Icon(Icons.info_outline, color: Colors.deepPurple.shade400),
          ),
        ],
      ),
    );
  }
}

class _ActionsBar extends StatelessWidget {
  final bool isUploading;
  final bool isEditing;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final String? uploadedUrl;
  final VoidCallback? onOpenLatest;

  const _ActionsBar({
    required this.isUploading,
    required this.isEditing,
    required this.onSave,
    required this.onCancel,
    required this.uploadedUrl,
    required this.onOpenLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      runSpacing: 8,
      spacing: 8,
      children: [
        if (uploadedUrl != null && uploadedUrl!.isNotEmpty)
          OutlinedButton.icon(
            onPressed: onOpenLatest,
            icon: const Icon(Icons.link),
            label: const Text('Open latest upload'),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEditing) ...[
              OutlinedButton.icon(
                onPressed: isUploading ? null : onCancel,
                icon: const Icon(Icons.close),
                label: const Text('Cancel Edit'),
              ),
              const SizedBox(width: 8),
            ],
            FilledButton.icon(
              onPressed: isUploading ? null : onSave,
              icon: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.cloud_upload),
              label: Text(isUploading ? 'Uploading…' : (isEditing ? 'Update Material' : 'Save Study Material')),
            ),
          ],
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black87),
    );
  }
}

class _HintRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HintRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: _colorForCategory(category), borderRadius: BorderRadius.circular(12)),
      child: Text(category, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Color _colorForCategory(String c) {
    switch (c) {
      case 'Theory':
        return Colors.blue;
      case 'Practical Driving':
        return Colors.orange;
      case 'Traffic Rules':
        return Colors.red;
      case 'Road Signs':
        return Colors.amber;
      case 'Safety Guidelines':
        return Colors.green;
      case 'Vehicle Maintenance':
        return Colors.purple;
      case 'Mock Tests':
        return Colors.teal;
      case 'Highway Code':
        return Colors.indigo;
      default:
        return Colors.grey;
    }
  }
}

class _DetectedTypeBadge extends StatelessWidget {
  final String kind; // image | video | pdf | audio | archive | doc | other
  const _DetectedTypeBadge({required this.kind});

  @override
  Widget build(BuildContext context) {
    final icon = _icon(kind);
    final color = _color(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: color.withOpacity(0.3)),
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(kind.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  IconData _icon(String k) {
    switch (k) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'image':
        return Icons.image_outlined;
      case 'video':
        return Icons.video_file;
      case 'audio':
        return Icons.audiotrack;
      case 'archive':
        return Icons.archive_outlined;
      case 'doc':
        return Icons.description_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _color(String k) {
    switch (k) {
      case 'pdf':
        return Colors.red;
      case 'image':
        return Colors.blueGrey;
      case 'video':
        return Colors.blue;
      case 'audio':
        return Colors.deepPurple;
      case 'archive':
        return Colors.brown;
      case 'doc':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12)),
    );
  }
}

enum _Kind { image, video, pdf, audio, archive, doc, other }
