// attend_test_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'test_result_page.dart';

const kBrand = Color(0xFF4c63d2);

enum _QType { mcq, paragraph }

class _Question {
  final String id;
  final _QType type;
  final String text;
  final List<String> options; // for mcq
  final int? answerIndex; // for mcq
  final String? expectedAnswer; // for paragraph
  final String explanation;
  final String? imageUrl;

  _Question({
    required this.id,
    required this.type,
    required this.text,
    required this.options,
    required this.answerIndex,
    required this.expectedAnswer,
    required this.explanation,
    required this.imageUrl,
  });

  factory _Question.fromDoc(QueryDocumentSnapshot d) {
    final m = d.data() as Map<String, dynamic>;
    final t = (m['type'] ?? 'mcq').toString().toLowerCase();
    return _Question(
      id: d.id,
      type: t == 'paragraph' ? _QType.paragraph : _QType.mcq,
      text: (m['question'] ?? '').toString(),
      options: List<String>.from(
        (m['options'] as List?)?.map((e) => e.toString()) ?? const [],
      ),
      answerIndex:
          (m['answer_index'] is num) ? (m['answer_index'] as num).toInt() : null,
      expectedAnswer: (m['expected_answer']?.toString()),
      explanation: (m['explanation'] ?? '').toString(),
      imageUrl: (m['image_url']?.toString()),
    );
  }
}

class AttendTestPage extends StatefulWidget {
  final String poolId;
  final String? studentId; // optional override
  const AttendTestPage({super.key, required this.poolId, this.studentId});

  @override
  State<AttendTestPage> createState() => _AttendTestPageState();
}

class _AttendTestPageState extends State<AttendTestPage> {
  bool _loading = true;
  String _title = '';
  int _durationMin = 0;
  int _passingPct = 0;
  DateTime? _startedAt;
  List<_Question> _questions = [];

  // resolved student identifiers
  String? _resolvedStudentId; // from users collection / fallback
  String? _resolvedStudentUid; // from FirebaseAuth

  // answers: for MCQ store int (selected index); for paragraph store String
  final Map<String, dynamic> _answers = {};
  int _index = 0;

  Timer? _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _resolveStudentId();
    final sentToResult = await _checkExistingAttemptAndRedirect();
    if (sentToResult) return; // already navigated to result page
    await _load();            // otherwise proceed to take the test
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Resolve student id from users collection; fallbacks to widget prop / uid / anonymous.
  Future<void> _resolveStudentId() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      _resolvedStudentUid = user?.uid;

      // Prefer explicit studentId if provided
      if (widget.studentId != null && widget.studentId!.trim().isNotEmpty) {
        _resolvedStudentId = widget.studentId!.trim();
        return;
      }

      if (user == null) {
        _resolvedStudentId = 'anonymous';
        return;
      }

      final usersCol = FirebaseFirestore.instance.collection('users');

      // 1) users/{uid}
      final docByUid = await usersCol.doc(user.uid).get();
      if (docByUid.exists) {
        final m = docByUid.data() ?? {};
        final sid = ((m['student_id'] ?? m['studentId'])?.toString() ?? '').trim();
        _resolvedStudentId = sid.isNotEmpty ? sid : user.uid;
        return;
      }

      // 2) where uid == uid
      final q1 = await usersCol.where('uid', isEqualTo: user.uid).limit(1).get();
      if (q1.docs.isNotEmpty) {
        final m = q1.docs.first.data() as Map<String, dynamic>;
        final sid = ((m['student_id'] ?? m['studentId'])?.toString() ?? '').trim();
        _resolvedStudentId = sid.isNotEmpty ? sid : user.uid;
        return;
      }

      // 3) where email == email
      final email = user.email;
      if (email != null && email.isNotEmpty) {
        final q2 = await usersCol.where('email', isEqualTo: email).limit(1).get();
        if (q2.docs.isNotEmpty) {
          final m = q2.docs.first.data() as Map<String, dynamic>;
          final sid = ((m['student_id'] ?? m['studentId'])?.toString() ?? '').trim();
          _resolvedStudentId = sid.isNotEmpty ? sid : user.uid;
          return;
        }
      }

      _resolvedStudentId = user.uid;
    } catch (_) {
      _resolvedStudentId = widget.studentId?.trim().isNotEmpty == true
          ? widget.studentId!.trim()
          : 'anonymous';
    }
  }

  /// If this user already completed the test, rebuild results and navigate immediately.
  Future<bool> _checkExistingAttemptAndRedirect() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final sid = _resolvedStudentId ?? widget.studentId ?? uid ?? 'anonymous';

      // Fetch any completed attempt for this user & pool.
      final col = FirebaseFirestore.instance.collection('test_attempts');

      // Query by uid when available (more robust); otherwise fall back to student_id.
      Query q = col.where('pool_id', isEqualTo: widget.poolId).where('status', isEqualTo: 'completed');
      q = (uid != null) ? q.where('student_uid', isEqualTo: uid) : q.where('student_id', isEqualTo: sid);

      final snap = await q.limit(1).get();
      if (snap.docs.isEmpty) return false;

      final attemptDoc = snap.docs.first;
      final attempt = attemptDoc.data() as Map<String, dynamic>;

      // Load pool info for title / pass %
      final poolDoc = await FirebaseFirestore.instance.collection('test_pool').doc(widget.poolId).get();
      final pool = poolDoc.data() ?? {};
      final poolTitle = (pool['title'] ?? '').toString();
      final passingPct = (pool['passing_score_pct'] ?? 0) is num
          ? (pool['passing_score_pct'] as num).toInt()
          : 0;

      // Load all questions for this pool to construct rich result items
      final qs = await FirebaseFirestore.instance
          .collection('test_pool')
          .doc(widget.poolId)
          .collection('questions')
          .get();

      final byId = <String, _Question>{
        for (final d in qs.docs) d.id: _Question.fromDoc(d),
      };

      final details = List<Map<String, dynamic>>.from(
        (attempt['details'] as List?) ?? const [],
      );

      // compute score if needed
      final total = (attempt['total'] as num?)?.toInt() ?? details.length;
      final correct = (attempt['correct'] as num?)?.toInt() ??
          details.where((e) => (e['is_correct'] == true)).length;
      final scorePct = total == 0 ? 0.0 : (correct / total) * 100.0;
      final pass = scorePct.round() >= passingPct;

      // Build ResultItem list
      final items = <ResultItem>[];
      for (final d in details) {
        final qid = (d['question_id'] ?? '').toString();
        final q = byId[qid];
        if (q == null) continue;

        items.add(
          ResultItem(
            question: q.text,
            type: q.type == _QType.mcq ? QuestionTypeResult.mcq : QuestionTypeResult.paragraph,
            options: q.options,
            selectedIndex: (d['selected_index'] is num) ? (d['selected_index'] as num).toInt() : null,
            typedAnswer: (d['typed_answer']?.toString()),
            correctIndex: q.answerIndex,
            expectedAnswer: q.expectedAnswer,
            explanation: q.explanation,
            imageUrl: q.imageUrl,
          ),
        );
      }

      if (!mounted) return true;
      // Go straight to results
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TestResultPage(
            poolTitle: poolTitle,
            passingPct: passingPct,
            total: total,
            correct: correct,
            scorePct: scorePct,
            pass: pass,
            items: items,
            attemptId: attemptDoc.id,
            poolId: widget.poolId, // pass along for Go again convenience
          ),
        ),
      );
      return true;
    } catch (e) {
      // If anything fails, just let them take the test
      return false;
    }
  }

  Future<void> _load() async {
    try {
      final poolRef =
          FirebaseFirestore.instance.collection('test_pool').doc(widget.poolId);
      final poolSnap = await poolRef.get();
      if (!poolSnap.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test not found')),
        );
        Navigator.pop(context);
        return;
      }
      final pm = poolSnap.data() as Map<String, dynamic>;
      _title = (pm['title'] ?? '').toString();
      _durationMin = (pm['duration_minutes'] ?? 0) as int;
      _passingPct = (pm['passing_score_pct'] ?? 0) as int;

      final qs = await poolRef
          .collection('questions')
          .orderBy('created_at', descending: false)
          .get();

      _questions = qs.docs.map((d) => _Question.fromDoc(d)).toList();

      _startedAt = DateTime.now();
      if (_durationMin > 0) {
        _remaining = Duration(minutes: _durationMin);
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          final spent = DateTime.now().difference(_startedAt!);
          final left = Duration(minutes: _durationMin) - spent;
          setState(() {
            _remaining = left.isNegative ? Duration.zero : left;
          });
          if (left.isNegative || left.inSeconds == 0) {
            _timer?.cancel();
            _submit(auto: true); // auto-submit when time runs out
          }
        });
      }

      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load: $e')),
      );
      Navigator.pop(context);
    }
  }

  // ── Submit & evaluate ──────────────────────────────────────────────────────
  Future<void> _submit({bool auto = false}) async {
    if (_questions.isEmpty) return;

    final total = _questions.length;
    int correct = 0;
    final details = <Map<String, dynamic>>[];

    for (final q in _questions) {
      bool isCorrect = false;
      int? selectedIndex;
      String? typedAnswer;

      if (q.type == _QType.mcq) {
        selectedIndex = _answers[q.id] as int?;
        isCorrect = (selectedIndex != null &&
            q.answerIndex != null &&
            selectedIndex == q.answerIndex);
      } else {
        typedAnswer = (_answers[q.id] ?? '').toString();
        final exp = (q.expectedAnswer ?? '').toString();
        isCorrect = _norm(typedAnswer) == _norm(exp);
      }

      if (isCorrect) correct++;

      details.add({
        'question_id': q.id,
        'type': q.type == _QType.mcq ? 'mcq' : 'paragraph',
        'selected_index': selectedIndex,
        'typed_answer': typedAnswer,
        'correct_index': q.answerIndex,
        'expected_answer': q.expectedAnswer,
        'is_correct': isCorrect,
      });
    }

    final pct = total == 0 ? 0.0 : (correct / total) * 100.0;
    final pass = pct.round() >= _passingPct;

    final studentIdToSave =
        _resolvedStudentId ?? widget.studentId ?? _resolvedStudentUid ?? 'anonymous';

    final attemptData = {
      'pool_id': widget.poolId,
      'student_id': studentIdToSave,
      'student_uid': _resolvedStudentUid,
      'started_at': Timestamp.fromDate(_startedAt ?? DateTime.now()),
      'completed_at': Timestamp.now(),
      'score': pct.round(),
      'correct': correct,
      'total': total,
      'status': 'completed',
      'details': details,
    };

    String attemptId = '';
    try {
      final add =
          await FirebaseFirestore.instance.collection('test_attempts').add(attemptData);
      attemptId = add.id;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved locally. Upload error: $e')),
        );
      }
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TestResultPage(
          poolTitle: _title,
          passingPct: _passingPct,
          total: total,
          correct: correct,
          scorePct: pct,
          pass: pass,
          items: _buildResultItems(),
          attemptId: attemptId.isEmpty ? null : attemptId,
          poolId: widget.poolId,
        ),
      ),
    );
  }

  List<ResultItem> _buildResultItems() {
    return _questions.map((q) {
      final sel = _answers[q.id];
      return ResultItem(
        question: q.text,
        type: q.type == _QType.mcq ? QuestionTypeResult.mcq : QuestionTypeResult.paragraph,
        options: q.options,
        selectedIndex: sel is int ? sel : null,
        typedAnswer: sel is String ? sel : null,
        correctIndex: q.answerIndex,
        expectedAnswer: q.expectedAnswer,
        explanation: q.explanation,
        imageUrl: q.imageUrl,
      );
    }).toList();
  }

  String _norm(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // ── Back handling ──────────────────────────────────────────────────────────
  Future<bool> _onWillPop() async {
    if (_loading) return true; // allow leaving while loading
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Exit test?'),
        content: const Text(
          "If you leave now, your answers won't be saved.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(
          elevation: 0,
          backgroundColor: kBrand,
          title: Text(_loading ? 'Loading…' : _title),
          leading: BackButton(
            onPressed: () async {
              if (await _onWillPop()) {
                if (mounted) Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            if (!_loading && _durationMin > 0)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(child: _TimerPill(remaining: _remaining)),
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : (_questions.isEmpty
                ? const _CenteredEmpty(
                    title: 'No questions in this test',
                    caption: 'Contact your instructor.',
                  )
                : SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                              isCompact ? 12 : 16, 12, isCompact ? 12 : 16, 6),
                          child: _ProgressHeader(
                            index: _index,
                            total: _questions.length,
                            onJump: (i) => setState(() => _index = i),
                            answered: _answers,
                            questions: _questions,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                                isCompact ? 12 : 16, 6, isCompact ? 12 : 16, 100),
                            child: _QuestionCard(
                              q: _questions[_index],
                              value: _answers[_questions[_index].id],
                              onChanged: (v) {
                                setState(() {
                                  _answers[_questions[_index].id] = v;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
        bottomNavigationBar: _loading
            ? null
            : SafeArea(
                top: false,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      isCompact ? 12 : 16, 10, isCompact ? 12 : 16, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border:
                        Border(top: BorderSide(color: Colors.black12.withOpacity(.06))),
                  ),
                  child: Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _index == 0 ? null : () => setState(() => _index--),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Previous'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _index >= _questions.length - 1
                            ? null
                            : () => setState(() => _index++),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Next'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kBrand,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        onPressed: () => _confirmSubmit(context),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Submit Test'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Future<void> _confirmSubmit(BuildContext context) async {
    final unattempted = _questions.where((q) =>
        !_answers.containsKey(q.id) ||
        (_answers[q.id] is String &&
            (_answers[q.id] as String).trim().isNotEmpty == false)).length;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Submit test?'),
        content: Text(unattempted == 0
            ? 'You have answered all questions.'
            : 'You have $unattempted unanswered question(s). Submit anyway?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Review')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Submit')),
        ],
      ),
    );
    if (proceed == true) _submit();
  }
}

// ── Widgets ─────────────────────────────────────────────────────────────────
class _TimerPill extends StatelessWidget {
  final Duration remaining;
  const _TimerPill({required this.remaining});
  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final mm = two(remaining.inMinutes.remainder(60));
    final ss = two(remaining.inSeconds.remainder(60));
    final hh = remaining.inHours;
    final text = hh > 0 ? '$hh:$mm:$ss' : '$mm:$ss';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(text,
              style:
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int index;
  final int total;
  final void Function(int) onJump;
  final Map<String, dynamic> answered;
  final List<_Question> questions;

  const _ProgressHeader({
    required this.index,
    required this.total,
    required this.onJump,
    required this.answered,
    required this.questions,
  });

  @override
  Widget build(BuildContext context) {
    final done = answered.length;
    final value = total == 0 ? 0.0 : done / total;

    return Card(
      elevation: 0,
      color: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Question ${index + 1} of $total',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('$done/$total answered',
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: value,
              color: kBrand,
              backgroundColor: const Color(0xFFE9ECEF),
              minHeight: 6,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: total,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final isCurrent = i == index;
                  final isAnswered = answered.containsKey(questions[i].id) &&
                      (!(answered[questions[i].id] is String) ||
                          (answered[questions[i].id] as String)
                              .trim()
                              .isNotEmpty);
                  return InkWell(
                    onTap: () => onJump(i),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? kBrand
                            : isAnswered
                                ? Colors.green.shade50
                                : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isCurrent
                              ? kBrand
                              : isAnswered
                                  ? Colors.green
                                  : Colors.grey.shade400,
                        ),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isCurrent
                              ? Colors.white
                              : isAnswered
                                  ? Colors.green.shade800
                                  : Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  final _Question q;
  final dynamic value; // int (mcq) or String (paragraph)
  final ValueChanged<dynamic> onChanged;

  const _QuestionCard({
    required this.q,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    q.text,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.2,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.deepPurple.withOpacity(.25)),
                  ),
                  child: Text(
                    q.type == _QType.mcq ? 'MCQ' : 'PARAGRAPH',
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            if ((q.imageUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    q.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: const Color(0xFFF1F3F5),
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image_outlined),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (q.type == _QType.mcq)
              Column(
                children: List.generate(q.options.length, (i) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE9ECEF)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: RadioListTile<int>(
                      dense: isCompact,
                      value: i,
                      groupValue: value is int ? value as int? : null,
                      onChanged: (v) => onChanged(v),
                      activeColor: kBrand,
                      title: Text(
                        q.options[i],
                        style: const TextStyle(color: Colors.black),
                      ),
                    ),
                  );
                }),
              )
            else
              TextField(
                controller:
                    TextEditingController(text: value?.toString() ?? ''),
                onChanged: (v) => onChanged(v),
                maxLines: 4,
                style: const TextStyle(color: Colors.black),
                decoration: InputDecoration(
                  hintText: 'Type your answer here…',
                  hintStyle: const TextStyle(color: Colors.black45),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            if (q.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      q.explanation,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CenteredEmpty extends StatelessWidget {
  final String title;
  final String caption;
  const _CenteredEmpty({required this.title, required this.caption});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            children: [
              Icon(Icons.quiz_outlined,
                  size: 64, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Text(caption,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
}
