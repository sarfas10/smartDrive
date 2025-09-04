// edit_test_pool.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

enum QuestionType { mcq, paragraph }

class EditTestPoolPage extends StatefulWidget {
  final String poolId;
  const EditTestPoolPage({super.key, required this.poolId});

  @override
  State<EditTestPoolPage> createState() => _EditTestPoolPageState();
}

/// Question draft model (works for both existing & new)
class _QDraft {
  String? docId; // null => new
  QuestionType type = QuestionType.mcq;
  String question = '';
  final List<String> options = ['', '', '', ''];
  int answerIndex = 0; // for MCQ
  String expectedAnswer = ''; // for Paragraph
  String explanation = '';
  String? imageUrl;
  String? imagePublicId;
  Timestamp? createdAt; // keep original timestamps if present

  _QDraft();

  _QDraft.fromMap(String id, Map<String, dynamic> m) {
    docId = id;
    final t = (m['type'] ?? 'mcq').toString().toLowerCase();
    type = t == 'paragraph' ? QuestionType.paragraph : QuestionType.mcq;
    question = (m['question'] ?? '').toString();
    final opts = (m['options'] as List?) ?? const [];
    for (int i = 0; i < 4; i++) {
      options[i] = (i < opts.length ? opts[i].toString() : '');
    }
    answerIndex = (m['answer_index'] is num) ? (m['answer_index'] as num).toInt() : 0;
    expectedAnswer = (m['expected_answer'] ?? '').toString();
    explanation = (m['explanation'] ?? '').toString();
    imageUrl = (m['image_url']?.toString());
    imagePublicId = (m['image_public_id']?.toString());
    createdAt = m['created_at'] as Timestamp?;
  }

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

  Map<String, dynamic> toJsonForSet(String poolId, {bool includeCreatedAt = false}) {
    final map = <String, dynamic>{
      'pool_id': poolId,
      'type': type == QuestionType.mcq ? 'mcq' : 'paragraph',
      'question': question.trim(),
      'options': type == QuestionType.mcq ? options.map((e) => e.trim()).toList() : [],
      'answer_index': type == QuestionType.mcq ? answerIndex : null,
      'expected_answer': type == QuestionType.paragraph ? expectedAnswer.trim() : null,
      'explanation': explanation.trim(),
      'image_url': imageUrl,
      'image_public_id': imagePublicId,
      'updated_at': FieldValue.serverTimestamp(),
    };
    if (includeCreatedAt) {
      map['created_at'] = createdAt ?? FieldValue.serverTimestamp();
    }
    return map;
  }
}

class _EditTestPoolPageState extends State<EditTestPoolPage> {
  // ===== Basic info (no category) =====
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _duration = TextEditingController();
  final _passing = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  // ===== Questions =====
  final List<_QDraft> _drafts = [];
  final List<String> _deletedIds = [];

  // ===== Cloudinary config (same convention as create) =====
  // Upload on edit is disabled by default — set to true if you want it.
  static const bool _allowImageReplace = false;

  static const String _cloudName = 'dxeunc4vd';
  static const String _baseFolder = 'tests'; // stored under smartDrive/tests on server
  static const String _host = 'tajdrivingschool.in';
  static const String _basePath = '/smartDrive/cloudinary';
  Uri _api(String endpoint) => Uri.https(_host, '$_basePath/$endpoint');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _passing.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Load basic
      final poolRef =
          FirebaseFirestore.instance.collection('test_pool').doc(widget.poolId);
      final p = await poolRef.get();
      final pm = p.data() ?? {};
      _title.text = (pm['title'] ?? '').toString();
      _description.text = (pm['description'] ?? '').toString();
      _duration.text = (pm['duration_minutes'] ?? 30).toString();
      _passing.text = (pm['passing_score_pct'] ?? 70).toString();

      // Load questions
      final qs = await poolRef
          .collection('questions')
          .orderBy('created_at', descending: false)
          .get();

      _drafts
        ..clear()
        ..addAll(qs.docs.map((d) => _QDraft.fromMap(d.id, d.data())));

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      _toast('Load failed: $e');
      Navigator.pop(context);
    }
  }

  // ===== Helpers =====
  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  double _progress() {
    int need = 4, got = 0; // title, duration, passing, at least one question
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
      _toast('Fill required fields and at least one complete question.');
      return false;
    }
    if (pass < 0 || pass > 100) {
      _toast('Passing score must be 0–100.');
      return false;
    }
    return true;
  }

  // ===== Save (update in place) =====
  Future<void> _handleSave() async {
    if (!_validate()) return;

    try {
      setState(() => _saving = true);

      final poolRef =
          FirebaseFirestore.instance.collection('test_pool').doc(widget.poolId);

      // 1) Update pool basics
      await poolRef.update({
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'duration_minutes': int.parse(_duration.text.trim()),
        'passing_score_pct': int.parse(_passing.text.trim()),
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2) Batch upsert questions
      final batch = FirebaseFirestore.instance.batch();
      final qCol = poolRef.collection('questions');

      // deletions
      for (final id in _deletedIds) {
        batch.delete(qCol.doc(id));
      }

      // upserts
      for (final d in _drafts.where((x) => x.isComplete)) {
        if (d.docId != null) {
          // existing => update (do not overwrite created_at)
          batch.update(qCol.doc(d.docId), d.toJsonForSet(widget.poolId));
        } else {
          // new => set with created_at
          final doc = qCol.doc();
          batch.set(doc, d.toJsonForSet(widget.poolId, includeCreatedAt: true));
        }
      }

      await batch.commit();

      if (!mounted) return;
      _toast('Test pool updated.');
      Navigator.pop(context);
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ===== Cloudinary (optional on edit) =====
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
        .post(_api('signature.php'), body: {
          'public_id': publicId.trim(),
          'folder': folder.trim(),
          'overwrite': overwrite,
          'resource_type': resourceType,
        })
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
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/$resourceType/upload');
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

  Future<void> _pickAndUploadImage(_QDraft draft) async {
    if (!_allowImageReplace) {
      _toast('Image replacement is disabled on edit.');
      return;
    }
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
      if (x == null) return;

      Uint8List bytes;
      if (kIsWeb) {
        bytes = await x.readAsBytes();
      } else {
        bytes = await File(x.path).readAsBytes();
      }

      final ts = DateTime.now().millisecondsSinceEpoch;
      final basename = _slug(draft.question).isEmpty ? 'question' : _slug(draft.question);
      final publicId = '${basename}_$ts';

      final meta = await _uploadImageToCloudinary(
        bytes: bytes,
        filename: x.name.isNotEmpty ? x.name : '$publicId.jpg',
        publicId: publicId,
        folder: _baseFolder, // "tests"
      );

      draft.imageUrl = meta['url'];
      draft.imagePublicId = meta['public_id'];
      if (mounted) setState(() {});
      _toast('Image updated.');
    } catch (e) {
      _toast('Image upload failed: $e');
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final pad = EdgeInsets.symmetric(
      horizontal: MediaQuery.of(context).size.width < 420 ? 12 : 16,
      vertical: 12,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF4c63d2),
        title: const Text('Edit Test Pool'),
      ),

      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => setState(() => _drafts.add(_QDraft())),
              backgroundColor: const Color(0xFF4c63d2),
              label: const Text('Add Question'),
              icon: const Icon(Icons.add),
            ),

      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              top: false,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                    pad.horizontal / 2, 10, pad.horizontal / 2, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.black12.withOpacity(.06))),
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
                            color: const Color(0xFF4c63d2),
                            backgroundColor: const Color(0xFFE9ECEF),
                            minHeight: 6,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_drafts.length} ${_drafts.length == 1 ? 'question' : 'questions'}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4c63d2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      icon: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_alt),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                    ),
                  ],
                ),
              ),
            ),

      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
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
                                    hint: 'e.g., Learner\'s Licence Mock Test – Set 1',
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
                                  const Text('Questions',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: Colors.black)),
                                  TextButton.icon(
                                    onPressed: () => setState(() => _drafts.add(_QDraft())),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add Question'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF4c63d2),
                                    ),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: [
                                  for (int i = 0; i < _drafts.length; i++)
                                    _QuestionEditor(
                                      index: i + 1,
                                      draft: _drafts[i],
                                      onDelete: () async {
                                        final d = _drafts[i];
                                        if (d.docId != null) _deletedIds.add(d.docId!);
                                        setState(() => _drafts.removeAt(i));
                                      },
                                      onChanged: () => setState(() {}),
                                      onPickImage: () => _pickAndUploadImage(_drafts[i]),
                                      onRemoveImage: () {
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

/// ===== UI components (same spirit as create page) =====
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
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (titleWidget != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: titleWidget!)
            else if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(title!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.black)),
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
        Text(label,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: multiline ? 3 : 1,
          style: const TextStyle(color: Colors.black),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black45),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: dense,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 12 : 14),
          ),
        ),
      ],
    );
  }
}

class _QuestionEditor extends StatelessWidget {
  final int index;
  final _QDraft draft;
  final VoidCallback onDelete;
  final VoidCallback onChanged;
  final VoidCallback onPickImage;
  final VoidCallback onRemoveImage;

  const _QuestionEditor({
    required this.index,
    required this.draft,
    required this.onDelete,
    required this.onChanged,
    required this.onPickImage,
    required this.onRemoveImage,
  });

  @override
  Widget build(BuildContext context) {
    final q = TextEditingController(text: draft.question);
    final a = TextEditingController(text: draft.options[0]);
    final b = TextEditingController(text: draft.options[1]);
    final c = TextEditingController(text: draft.options[2]);
    final d = TextEditingController(text: draft.options[3]);
    final exp = TextEditingController(text: draft.explanation);
    final expAns = TextEditingController(text: draft.expectedAnswer);

    void sync() {
      draft.question = q.text;
      draft.options[0] = a.text;
      draft.options[1] = b.text;
      draft.options[2] = c.text;
      draft.options[3] = d.text;
      draft.explanation = exp.text;
      draft.expectedAnswer = expAns.text;
      onChanged();
    }

    final dense = MediaQuery.of(context).size.width < 420;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE9ECEF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header row: title + type selector + delete
          Row(
            children: [
              Expanded(
                child: Text('Question $index',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Colors.black)),
              ),
              DropdownButton<QuestionType>(
                value: draft.type,
                onChanged: (v) {
                  if (v == null) return;
                  draft.type = v;
                  onChanged();
                },
                items: const [
                  DropdownMenuItem(
                    value: QuestionType.mcq,
                    child: Text('MCQ',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w600)),
                  ),
                  DropdownMenuItem(
                    value: QuestionType.paragraph,
                    child: Text('Paragraph',
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              IconButton(
                tooltip: draft.docId != null ? 'Delete (existing)' : 'Delete',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
              ),
            ],
          ),
          const SizedBox(height: 8),

          _LabeledTextField(
            label: 'Question *',
            controller: q,
            hint: 'e.g., What does this road sign indicate?',
            multiline: true,
          ),
          const SizedBox(height: 10),

          // image attach/preview
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (draft.imageUrl != null)
                Container(
                  width: 84,
                  height: 64,
                  margin: const EdgeInsets.only(right: 10),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    color: Colors.white,
                  ),
                  child: Image.network(draft.imageUrl!, fit: BoxFit.cover),
                ),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onPickImage,
                      icon: const Icon(Icons.image),
                      label: Text(draft.imageUrl == null
                          ? 'Add/Replace image'
                          : 'Replace image'),
                    ),
                    if (draft.imageUrl != null)
                      TextButton.icon(
                        onPressed: onRemoveImage,
                        icon: const Icon(Icons.close),
                        label: const Text('Remove'),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (draft.type == QuestionType.mcq) ...[
            const Text('Answer Options *',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black)),
            const SizedBox(height: 8),

            _OptionRow(
              label: 'Option A',
              index: 0,
              controller: a,
              groupValue: draft.answerIndex,
              onChangedText: (v) => sync(),
              onChangedRadio: (i) {
                draft.answerIndex = i;
                sync();
              },
            ),
            const SizedBox(height: 8),
            _OptionRow(
              label: 'Option B',
              index: 1,
              controller: b,
              groupValue: draft.answerIndex,
              onChangedText: (v) => sync(),
              onChangedRadio: (i) {
                draft.answerIndex = i;
                sync();
              },
            ),
            const SizedBox(height: 8),
            _OptionRow(
              label: 'Option C',
              index: 2,
              controller: c,
              groupValue: draft.answerIndex,
              onChangedText: (v) => sync(),
              onChangedRadio: (i) {
                draft.answerIndex = i;
                sync();
              },
            ),
            const SizedBox(height: 8),
            _OptionRow(
              label: 'Option D',
              index: 3,
              controller: d,
              groupValue: draft.answerIndex,
              onChangedText: (v) => sync(),
              onChangedRadio: (i) {
                draft.answerIndex = i;
                sync();
              },
            ),
            const SizedBox(height: 6),
            const Text(
              'Select the radio button next to the correct answer',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 12),
          ] else ...[
            _LabeledTextField(
              label: 'Expected Answer *',
              controller: expAns,
              hint: 'e.g., Explain the right-of-way at roundabouts.',
              multiline: true,
            ),
            const SizedBox(height: 12),
          ],

          _LabeledTextField(
            label: 'Explanation (Optional)',
            controller: exp,
            hint: draft.type == QuestionType.mcq
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
  final int index;
  final TextEditingController controller;
  final int groupValue;
  final ValueChanged<String> onChangedText;
  final ValueChanged<int> onChangedRadio;

  const _OptionRow({
    required this.label,
    required this.index,
    required this.controller,
    required this.groupValue,
    required this.onChangedText,
    required this.onChangedRadio,
  });

  @override
  Widget build(BuildContext context) {
    final dense = MediaQuery.of(context).size.width < 420;
    return Row(
      children: [
        Radio<int>(
          value: index,
          groupValue: groupValue,
          onChanged: (v) {
            if (v != null) onChangedRadio(v);
          },
          activeColor: const Color(0xFF4c63d2),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChangedText,
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              hintText: label,
              hintStyle: const TextStyle(color: Colors.black45),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: dense,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 12, vertical: dense ? 12 : 14),
            ),
          ),
        ),
      ],
    );
  }
}
