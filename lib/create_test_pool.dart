// create_test_pool.dart
// - Saves question images to Cloudinary under folder "smartDrive/tests"
// - Uploads images ONLY when creating the pool (not during picking)
// - Category removed
// - Stable option editors (no cursor jumps), mobile-first responsive UI

import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'theme/app_theme.dart';

enum QuestionType { mcq, paragraph }

class CreateTestPoolPage extends StatefulWidget {
  const CreateTestPoolPage({super.key});
  @override
  State<CreateTestPoolPage> createState() => _CreateTestPoolPageState();
}

/// Question draft model
class _QDraft {
  QuestionType type = QuestionType.mcq;
  String question = '';
  final List<String> options = ['', '', '', ''];
  int answerIndex = 0; // for MCQ
  String expectedAnswer = ''; // for Paragraph
  String explanation = '';

  // Image placeholders (picked but NOT uploaded yet)
  Uint8List? imageBytes; // for preview + later upload
  String? imageFilename; // original filename (if available)

  // Will be filled ONLY after upload during create
  String? imageUrl;
  String? imagePublicId;

  bool get isComplete {
    if (question.trim().isEmpty) return false;
    if (type == QuestionType.mcq) {
      return options.every((e) => e.trim().isNotEmpty) &&
          answerIndex >= 0 &&
          answerIndex < 4;
    } else {
      return expectedAnswer.trim().isNotEmpty;
    }
  }

  Map<String, dynamic> toJson(String poolId) => {
    'pool_id': poolId,
    'type': type == QuestionType.mcq ? 'mcq' : 'paragraph',
    'question': question.trim(),
    'options': type == QuestionType.mcq
        ? options.map((e) => e.trim()).toList()
        : [],
    'answer_index': type == QuestionType.mcq ? answerIndex : null,
    'expected_answer': type == QuestionType.paragraph
        ? expectedAnswer.trim()
        : null,
    'explanation': explanation.trim(),
    'image_url': imageUrl,
    'image_public_id': imagePublicId,
    'created_at': FieldValue.serverTimestamp(),
  };
}

class _CreateTestPoolPageState extends State<CreateTestPoolPage> {
  // ===== Basic info (Driving School) =====
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _duration = TextEditingController(text: '30'); // typical mock test
  final _passing = TextEditingController(text: '70');

  // ===== Questions =====
  final List<_QDraft> _drafts = [_QDraft()];
  bool _saving = false;

  // ===== Cloudinary config (use the same server you already have) =====
  static const String _cloudName = 'dnxj5r6rc';
  // Save under smartDrive/tests (Cloudinary auto-creates if missing)
  static const String _baseFolder = 'smartDrive/tests';
  static const String _host = 'tajdrivingschool.in';
  static const String _basePath = '/smartDrive/cloudinary';
  Uri _api(String endpoint) => Uri.https(_host, '$_basePath/$endpoint');

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _passing.dispose();
    super.dispose();
  }

  double _progress() {
    int need = 4, got = 0;
    if (_title.text.trim().isNotEmpty) got++;
    if (int.tryParse(_duration.text.trim()) != null) got++;
    if (int.tryParse(_passing.text.trim()) != null) got++;
    if (_drafts.any((q) => q.isComplete)) got++;
    return got / need;
  }

  bool _validate() {
    final dur = int.tryParse(_duration.text.trim());
    final pass = int.tryParse(_passing.text.trim());
    final hasQ = _drafts.any((d) => d.isComplete);

    if (_title.text.trim().isEmpty || dur == null || pass == null || !hasQ) {
      _toast('Fill all required fields and at least one complete question.');
      return false;
    }
    if (pass < 0 || pass > 100) {
      _toast('Passing score must be 0–100.');
      return false;
    }
    return true;
  }

  Future<void> _handleCreate() async {
    if (!_validate()) return;
    setState(() => _saving = true);

    DocumentReference<Map<String, dynamic>>? poolRef;
    final uploadedPublicIds = <String>[];

    try {
      // 1) Create pool first
      poolRef = await FirebaseFirestore.instance.collection('test_pool').add({
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'duration_minutes': int.parse(_duration.text.trim()),
        'passing_score_pct': int.parse(_passing.text.trim()),
        'status': 'active',
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2) Upload images (if any) NOW (during creation), not during picking
      final tsBase = DateTime.now().millisecondsSinceEpoch;
      for (int i = 0; i < _drafts.length; i++) {
        final d = _drafts[i];
        if (d.imageBytes != null && d.imageBytes!.isNotEmpty) {
          final publicId =
              '${_slug(_title.text.isEmpty ? "test_pool" : _title.text)}_q${i + 1}_$tsBase';
          final res = await _uploadImageToCloudinary(
            bytes: d.imageBytes!,
            filename: (d.imageFilename?.isNotEmpty ?? false)
                ? d.imageFilename!
                : '$publicId.jpg',
            publicId: publicId,
            folder: _baseFolder, // "smartDrive/tests"
          );
          d.imageUrl = res['url'];
          d.imagePublicId = res['public_id'];
          if (d.imagePublicId != null) uploadedPublicIds.add(d.imagePublicId!);
        }
      }

      // 3) Save questions with finalized image URLs/IDs
      final batch = FirebaseFirestore.instance.batch();
      final qCol = poolRef.collection('questions');
      for (final d in _drafts.where((x) => x.isComplete)) {
        batch.set(qCol.doc(), d.toJson(poolRef.id));
      }
      await batch.commit();

      if (mounted) {
        _toast('Test pool created.');
        Navigator.pop(context);
      }
    } catch (e) {
      // Optional cleanup: if pool created but failure later, you may remove it
      try {
        if (poolRef != null) {
          await poolRef.delete();
        }
      } catch (_) {}
      _toast('Failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  // ===== Cloudinary (signed) helpers ========================================
  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  Future<Map<String, dynamic>> _getSignature({
    required String publicId,
    required String folder,
    required String resourceType, // 'image'
    String overwrite = 'true',
  }) async {
    final res = await http
        .post(
          _api('signature.php'),
          body: {
            'public_id': publicId.trim(),
            'folder': folder.trim(),
            'overwrite': overwrite,
            'resource_type': resourceType,
          },
        )
        .timeout(const Duration(seconds: 20));
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

  Future<Map<String, String>> _uploadImageToCloudinary({
    required Uint8List bytes,
    required String filename,
    required String publicId,
    required String folder,
  }) async {
    const resourceType = 'image';
    final signed = await _getSignature(
      publicId: publicId,
      folder: folder,
      resourceType: resourceType,
      overwrite: 'true',
    );

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload',
    );
    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key'] = signed['api_key'].toString()
      ..fields['timestamp'] = signed['timestamp'].toString()
      ..fields['signature'] = signed['signature'].toString()
      ..fields['public_id'] = publicId
      ..fields['folder'] = folder
      ..fields['overwrite'] = 'true';

    final file = http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: MediaType('application', 'octet-stream'),
    );
    req.files.add(file);

    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw Exception('Cloudinary upload failed: ${streamed.statusCode} $body');
    }
    final m = jsonDecode(body) as Map<String, dynamic>;
    final url = (m['secure_url'] ?? m['url'])?.toString() ?? '';
    final public = (m['public_id'] ?? '').toString();
    return {'url': url, 'public_id': public};
  }

  // ===== Pick image (NO UPLOAD here) ========================================
  Future<void> _pickImage(_QDraft draft) async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (x == null) return;

      Uint8List bytes;
      if (kIsWeb) {
        bytes = await x.readAsBytes();
      } else {
        bytes = await File(x.path).readAsBytes();
      }

      draft.imageBytes = bytes;
      draft.imageFilename = x.name;
      setState(() {});
      _toast('Image added (will upload on Create).');
    } catch (e) {
      _toast('Pick image failed: $e');
    }
  }

  // ===== UI =================================================================
  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width < 420 ? 12 : 16,
      vertical: 12,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onSurfaceInverse,
        title: Text(
          'Create Test Pool',
          style: AppText.sectionTitle.copyWith(
            color: AppColors.onSurfaceInverse,
          ),
        ),
      ),

      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => setState(() => _drafts.add(_QDraft())),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.onSurfaceInverse,
        label: const Text('Add Question'),
        icon: const Icon(Icons.add),
      ),

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            pad.horizontal / 2,
            10,
            pad.horizontal / 2,
            10,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: _progress(),
                      color: AppColors.brand,
                      backgroundColor: AppColors.neuBg,
                      minHeight: 6,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _drafts.length == 1
                          ? '1 question'
                          : '${_drafts.length} questions',
                      style: AppText.hintSmall.copyWith(
                        color: AppColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _saving ? null : _handleCreate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: AppColors.onSurfaceInverse,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                icon: _saving
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onSurfaceInverse,
                        ),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(
                  _saving ? 'Saving...' : 'Create',
                  style: AppText.tileTitle.copyWith(
                    color: AppColors.onSurfaceInverse,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, cons) {
            final maxW = cons.maxWidth.clamp(320, 900);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxW.toDouble()),
                child: SingleChildScrollView(
                  padding: pad.copyWith(bottom: 90),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionCard(
                        title: 'Basic Information',
                        child: Column(
                          children: [
                            _LabeledTextField(
                              label: 'Test Title *',
                              controller: _title,
                              hint:
                                  'e.g., Learner\'s Licence Mock Test – Set 1',
                            ),
                            const SizedBox(height: 10),
                            _LabeledTextField(
                              label: 'Description',
                              controller: _description,
                              hint:
                                  'Brief description (e.g., Signs: Mandatory/Warning, Speed limits, Night driving).',
                              multiline: true,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _LabeledTextField(
                                    label: 'Duration (minutes) *',
                                    controller: _duration,
                                    keyboardType: TextInputType.number,
                                    hint: 'e.g., 30',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _LabeledTextField(
                                    label: 'Passing Score (%) *',
                                    controller: _passing,
                                    keyboardType: TextInputType.number,
                                    hint: 'e.g., 70',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      _SectionCard(
                        titleWidget: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Questions',
                              style: AppText.sectionTitle.copyWith(
                                fontSize: 16,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  setState(() => _drafts.add(_QDraft())),
                              icon: const Icon(Icons.add),
                              label: const Text('Add Question'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.brand,
                              ),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < _drafts.length; i++)
                              _QuestionEditor(
                                key: ValueKey(_drafts[i]), // stabilize
                                index: i + 1,
                                draft: _drafts[i],
                                onDelete: () =>
                                    setState(() => _drafts.removeAt(i)),
                                onChanged: () => setState(() {}),
                                onPickImage: () => _pickImage(_drafts[i]),
                                onRemoveImage: () {
                                  _drafts[i].imageBytes = null;
                                  _drafts[i].imageFilename = null;
                                  _drafts[i].imageUrl = null;
                                  _drafts[i].imagePublicId = null;
                                  setState(() {});
                                },
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// ===== UI components =====
class _SectionCard extends StatelessWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget child;
  const _SectionCard({this.title, this.titleWidget, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.l),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titleWidget != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: titleWidget!,
              )
            else if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title!, style: AppText.sectionTitle),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class _LabeledTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool multiline;
  final TextInputType? keyboardType;
  const _LabeledTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.multiline = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final dense = MediaQuery.of(context).size.width < 420;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.tileTitle.copyWith(fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: multiline ? 3 : 1,
          style: AppText.tileTitle.copyWith(color: AppColors.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppText.hintSmall.copyWith(
              color: AppColors.onSurfaceFaint,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.m),
            ),
            isDense: dense,
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: dense ? 12 : 14,
            ),
            filled: true,
            fillColor: AppColors.surface,
          ),
        ),
      ],
    );
  }
}

/// -------- Question Editor (stateful, persistent controllers) --------
class _QuestionEditor extends StatefulWidget {
  final int index;
  final _QDraft draft;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  const _QuestionEditor({
    super.key,
    required this.index,
    required this.draft,
    required this.onDelete,
    required this.onChanged,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  @override
  State<_QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends State<_QuestionEditor> {
  late final TextEditingController qCtrl;
  late final List<TextEditingController> optCtrl;
  late final TextEditingController expCtrl;
  late final TextEditingController expAnsCtrl;

  @override
  void initState() {
    super.initState();
    qCtrl = TextEditingController(text: widget.draft.question);
    optCtrl = List.generate(
      4,
      (i) => TextEditingController(text: widget.draft.options[i]),
    );
    expCtrl = TextEditingController(text: widget.draft.explanation);
    expAnsCtrl = TextEditingController(text: widget.draft.expectedAnswer);

    qCtrl.addListener(_sync);
    for (final c in optCtrl) {
      c.addListener(_sync);
    }
    expCtrl.addListener(_sync);
    expAnsCtrl.addListener(_sync);
  }

  void _sync() {
    widget.draft.question = qCtrl.text;
    for (int i = 0; i < 4; i++) {
      widget.draft.options[i] = optCtrl[i].text;
    }
    widget.draft.explanation = expCtrl.text;
    widget.draft.expectedAnswer = expAnsCtrl.text;
    widget.onChanged();
  }

  @override
  void dispose() {
    qCtrl.dispose();
    for (final c in optCtrl) {
      c.dispose();
    }
    expCtrl.dispose();
    expAnsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dense = MediaQuery.of(context).size.width < 420;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.neuBg,
        borderRadius: BorderRadius.circular(AppRadii.m),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header row: title + type selector + delete
          Row(
            children: [
              Expanded(
                child: Text(
                  'Question ${widget.index}',
                  style: AppText.sectionTitle.copyWith(fontSize: 16),
                ),
              ),
              DropdownButton<QuestionType>(
                value: widget.draft.type,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => widget.draft.type = v);
                  widget.onChanged();
                },
                items: [
                  DropdownMenuItem(
                    value: QuestionType.mcq,
                    child: Text(
                      'MCQ',
                      style: AppText.tileTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  DropdownMenuItem(
                    value: QuestionType.paragraph,
                    child: Text(
                      'Paragraph',
                      style: AppText.tileTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: widget.onDelete,
                icon: Icon(Icons.delete_outline, color: AppColors.danger),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _LabeledTextField(
            label: 'Question *',
            controller: qCtrl,
            hint: 'e.g., What does this road sign indicate?',
            multiline: true,
          ),
          const SizedBox(height: 10),

          // image (preview from memory only; upload happens on Create)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (widget.draft.imageBytes != null)
                Container(
                  width: 84,
                  height: 64,
                  margin: const EdgeInsets.only(right: 10),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.m),
                    border: Border.all(color: AppColors.divider),
                    color: AppColors.surface,
                  ),
                  child: Image.memory(
                    widget.draft.imageBytes!,
                    fit: BoxFit.cover,
                  ),
                ),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: widget.onPickImage,
                      icon: const Icon(Icons.image),
                      label: Text(
                        widget.draft.imageBytes == null
                            ? 'Add image (optional)'
                            : 'Replace image',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        side: BorderSide(color: AppColors.divider),
                      ),
                    ),
                    if (widget.draft.imageBytes != null)
                      TextButton.icon(
                        onPressed: widget.onRemoveImage,
                        icon: Icon(Icons.close, color: AppColors.danger),
                        label: Text(
                          'Remove',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (widget.draft.type == QuestionType.mcq) ...[
            Text(
              'Answer Options *',
              style: AppText.tileTitle.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            for (int i = 0; i < 4; i++) ...[
              _OptionRow(
                label: 'Option ${String.fromCharCode(65 + i)}',
                controller: optCtrl[i],
                value: i,
                groupValue: widget.draft.answerIndex,
                onSelect: (v) {
                  setState(() => widget.draft.answerIndex = v ?? 0);
                  widget.onChanged();
                },
              ),
              if (i != 3) const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            Text(
              'Select the radio button next to the correct answer',
              style: AppText.hintSmall.copyWith(
                color: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 12),
          ] else ...[
            _LabeledTextField(
              label: 'Expected Answer *',
              controller: expAnsCtrl,
              hint: 'e.g., Explain the right-of-way at roundabouts.',
              multiline: true,
            ),
            const SizedBox(height: 12),
          ],

          _LabeledTextField(
            label: 'Explanation (Optional)',
            controller: expCtrl,
            hint: widget.draft.type == QuestionType.mcq
                ? 'Why is this option correct? Add rule reference if needed.'
                : 'Key points to look for in a good answer.',
            multiline: true,
          ),

          if (!dense) const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int value;
  final int groupValue;
  final ValueChanged<int?> onSelect;

  const _OptionRow({
    required this.label,
    required this.controller,
    required this.value,
    required this.groupValue,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final dense = MediaQuery.of(context).size.width < 420;
    return Row(
      children: [
        Radio<int>(
          value: value,
          groupValue: groupValue,
          onChanged: onSelect,
          activeColor: AppColors.brand,
        ),
        Expanded(
          child: TextField(
            controller: controller,
            style: AppText.tileTitle.copyWith(color: AppColors.onSurface),
            decoration: InputDecoration(
              hintText: label,
              hintStyle: AppText.hintSmall.copyWith(
                color: AppColors.onSurfaceFaint,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.m),
              ),
              isDense: dense,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: dense ? 12 : 14,
              ),
              filled: true,
              fillColor: AppColors.surface,
            ),
          ),
        ),
      ],
    );
  }
}
