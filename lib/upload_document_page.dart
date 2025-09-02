// upload_document_page.dart
// A unified Upload Document page for both Instructor and Student.
// - Uses your existing Cloudinary SIGNED upload pattern (signature.php).
// - Saves metadata to Firestore collection: `user_uploads` (NOT `documents`).
// - Reads role from Firestore: `users/{uid}.role`.
// - Accepts: PDF, DOC, DOCX, JPG, PNG (<= 10MB).

import 'dart:convert';
import 'dart:io' show File;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ⤵️ NEW: imports your uploads listing page

import 'package:smart_drive/my_uploads.dart'; // assumes MyUploadsPage()

class UploadDocumentPage extends StatefulWidget {
  const UploadDocumentPage({super.key});

  @override
  State<UploadDocumentPage> createState() => _UploadDocumentPageState();
}

class _UploadDocumentPageState extends State<UploadDocumentPage> {
  // ===== Cloudinary config: keep consistent with your onboarding_form.dart =====
  static const String _cloudName = 'dxeunc4vd';
  static const String _baseFolder = 'smartDrive';
  static const String _hostingerBase =
      'https://tajdrivingschool.in/smartDrive/cloudinary';

  // ===== Form/UI state =====
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  PlatformFile? _picked;
  bool _uploading = false;

  final _allowed = const ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png'];
  static const int _maxBytes = 10 * 1024 * 1024; // 10MB

  @override
  void dispose() {
    _nameCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // ===== Helpers (same contract as onboarding_form.dart) =====
  String _clean(String s) => s.replaceAll(RegExp(r'\s+'), '');

  Future<Map<String, dynamic>> _getSignature({
    required String publicId,
    required String folder,
    String overwrite = 'true',
  }) async {
    final uri = Uri.parse('$_hostingerBase/signature.php');
    final body = {
      'public_id': _clean(publicId),
      'folder': _clean(folder),
      'overwrite': overwrite,
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

  Future<String> _uploadToCloudinarySigned({
    required Uint8List bytes,
    required String filename,
    required String publicId,
    required String folder,
    String overwrite = 'true',
  }) async {
    final signed =
        await _getSignature(publicId: publicId, folder: folder, overwrite: overwrite);

    final uri =
        Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/auto/upload');

    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = signed['api_key'].toString()
      ..fields['timestamp'] = signed['timestamp'].toString()
      ..fields['signature'] = signed['signature'].toString()
      ..fields['public_id'] = _clean(publicId)
      ..fields['folder'] = _clean(folder)
      ..fields['overwrite'] = overwrite;

    // generic content-type to support any file (pdf/doc/image)
    final mediaType = MediaType('application', 'octet-stream');
    req.files.add(http.MultipartFile.fromBytes('file', bytes,
        filename: filename, contentType: mediaType));

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${streamed.statusCode} $body');
    }
    final json = jsonDecode(body) as Map<String, dynamic>;
    return (json['secure_url'] as String?) ?? (json['url'] as String);
  }

  // ===== Pick file =====
  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: _allowed,
    );
    if (res == null || res.files.isEmpty) return;

    final f = res.files.single;
    final ext = (f.extension ?? '').toLowerCase();

    if (!_allowed.contains(ext)) {
      _snack('Unsupported file type. Use PDF, DOC, DOCX, JPG, or PNG.');
      return;
    }
    if (f.size > _maxBytes) {
      _snack('Maximum file size is 10MB.');
      return;
    }
    setState(() => _picked = f);
  }

  // ===== Submit (upload + Firestore save) =====
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_picked == null) {
      _snack('Please choose a file to upload.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('You must be signed in.');
      return;
    }

    setState(() => _uploading = true);
    try {
      // Get role from `users/{uid}.role`
      String role = 'unknown';
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        final r = userDoc.data()?['role'];
        if (r is String && r.trim().isNotEmpty) role = r.toLowerCase();
      }

      // Prepare Cloudinary path
      final now = DateTime.now();
      final datePart = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      final folder = _clean('$_baseFolder/users/${user.uid}/uploads/$datePart');

      final fileName = _picked!.name;
      final publicIdSafe = _clean(fileName.split('.').first);

      // Read bytes (web/native)
      late Uint8List bytes;
      if (kIsWeb) {
        bytes = _picked!.bytes!;
      } else {
        bytes = await File(_picked!.path!).readAsBytes();
      }

      // Cloudinary upload
      final fileUrl = await _uploadToCloudinarySigned(
        bytes: bytes,
        filename: fileName,
        publicId: publicIdSafe,
        folder: folder,
      );

      // Save metadata (NOT in `documents`)
      await FirebaseFirestore.instance.collection('user_uploads').add({
        'uid': user.uid,
        'role': role, // student | instructor | unknown
        'document_name': _nameCtrl.text.trim(),
        'remarks': _remarksCtrl.text.trim().isEmpty ? null : _remarksCtrl.text.trim(),
        'file_name': fileName,
        'file_ext': (_picked!.extension ?? '').toLowerCase(),
        'file_size': _picked!.size,
        'cloudinary_url': fileUrl,
        'cloudinary_folder': folder,
        'cloudinary_public_id': publicIdSafe,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      _snack('Document uploaded successfully.');
      if (mounted) {
        setState(() {
          _picked = null;
          _nameCtrl.clear();
          _remarksCtrl.clear();
        });
      }
    } catch (e) {
      _snack('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text('Upload Document'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        // ⤵️ NEW: "My Uploads" button at the top
        actions: [
          TextButton.icon(
            onPressed: _uploading
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const MyUploadsPage()),
                    );
                  },
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('My Uploads'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2D5BFF),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _formKey,
                child: ListView(
                  children: [
                    _FileBox(
                      picked: _picked,
                      onPick: _uploading ? null : _pickFile,
                      helpText: 'PDF, DOC, DOCX, JPG, PNG up to 10MB',
                    ),
                    const SizedBox(height: 16),
                    const _Label('Document Name *'),
                    TextFormField(
                      controller: _nameCtrl,
                      enabled: !_uploading,
                      decoration: _input('e.g., Aadhaar Card, Passport, Academic Certificate'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    const _Label('Remarks (Optional)'),
                    TextFormField(
                      controller: _remarksCtrl,
                      enabled: !_uploading,
                      maxLines: 4,
                      decoration: _input('Add any additional information about this document...'),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _uploading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: const Color(0xFF2D5BFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(_uploading ? 'Uploading...' : 'Upload Document'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _Guidelines(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _input(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// ===== UI widgets that resemble your screenshot =====

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14));
}

class _FileBox extends StatelessWidget {
  final PlatformFile? picked;
  final VoidCallback? onPick;
  final String helpText;
  const _FileBox({required this.picked, required this.onPick, required this.helpText});

  @override
  Widget build(BuildContext context) {
    final hasFile = picked != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Label('Select Document *'),
        const SizedBox(height: 8),
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 150,
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.blue.shade200,
                width: 1.2,
              ),
            ),
            child: Center(
              child: hasFile
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.insert_drive_file_rounded,
                            size: 36, color: Colors.blueGrey),
                        const SizedBox(height: 8),
                        Text(picked!.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          '${(picked!.size / (1024 * 1024)).toStringAsFixed(2)} MB',
                          style: const TextStyle(color: Colors.black54),
                        ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.upload_rounded,
                            size: 36, color: Colors.black54),
                        const SizedBox(height: 8),
                        const Text('Choose a file to upload',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(helpText,
                            style: const TextStyle(color: Colors.black54, fontSize: 12)),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Guidelines extends StatelessWidget {
  const _Guidelines();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3EAFF)),
      ),
      padding: const EdgeInsets.all(12),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Upload Guidelines:', style: TextStyle(fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text('• Supported formats: PDF, DOC, DOCX, JPG, PNG'),
          Text('• Maximum file size: 10MB'),
          Text('• Ensure document is clear and readable'),
          Text('• Use descriptive names for easy identification'),
        ],
      ),
    );
  }
}
