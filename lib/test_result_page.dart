// test_result_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'attend_test_page.dart';

const kBrand = Color(0xFF4c63d2);

enum QuestionTypeResult { mcq, paragraph }

class ResultItem {
  final String question;
  final QuestionTypeResult type;
  final List<String> options; // mcq
  final int? selectedIndex; // mcq
  final int? correctIndex; // mcq
  final String? typedAnswer; // paragraph
  final String? expectedAnswer; // paragraph
  final String explanation;
  final String? imageUrl;

  ResultItem({
    required this.question,
    required this.type,
    required this.options,
    required this.selectedIndex,
    required this.correctIndex,
    required this.typedAnswer,
    required this.expectedAnswer,
    required this.explanation,
    required this.imageUrl,
  });

  bool get isCorrect {
    if (type == QuestionTypeResult.mcq) {
      return selectedIndex != null &&
          correctIndex != null &&
          selectedIndex == correctIndex;
    }
    final t = (typedAnswer ?? '').trim().toLowerCase();
    final e = (expectedAnswer ?? '').trim().toLowerCase();
    return t.isNotEmpty && t == e;
  }
}

class TestResultPage extends StatelessWidget {
  final String poolTitle;
  final int passingPct;
  final int total;
  final int correct;
  final double scorePct;
  final bool pass;
  final List<ResultItem> items;

  /// Recommended: pass the poolId so "Go again" is instant.
  final String? poolId;

  /// Used to delete this exact attempt before retaking.
  final String? attemptId;

  const TestResultPage({
    super.key,
    required this.poolTitle,
    required this.passingPct,
    required this.total,
    required this.correct,
    required this.scorePct,
    required this.pass,
    required this.items,
    this.poolId,
    this.attemptId,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.of(context).size.width < 420;
    final attempted = items.where((i) =>
        (i.type == QuestionTypeResult.mcq && i.selectedIndex != null) ||
        (i.type == QuestionTypeResult.paragraph &&
            (i.typedAnswer ?? '').trim().isNotEmpty)).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBrand,
        title: const Text('Test Results'),
      ),
      body: SafeArea(
        child: ListView(
          padding:
              EdgeInsets.fromLTRB(isCompact ? 12 : 16, 12, isCompact ? 12 : 16, 18),
          children: [
            _SummaryCard(
              poolTitle: poolTitle,
              scorePct: scorePct,
              pass: pass,
              passingPct: passingPct,
              total: total,
              attempted: attempted,
              correct: correct,
            ),
            const SizedBox(height: 12),

            const Text('Review',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 8),

            ...items.asMap().entries.map((e) {
              final i = e.key;
              final item = e.value;
              return _ResultItemCard(index: i + 1, item: item);
            }),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: LayoutBuilder(
            builder: (context, cons) {
              final narrow = cons.maxWidth < 420;
              final goAgainBtn = Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _goAgainDeletingAttempt(context),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Go again'),
                ),
              );
              final finishBtn = Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: kBrand,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Finish'),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    goAgainBtn,
                    const SizedBox(height: 8),
                    finishBtn,
                  ],
                );
              }
              return Row(children: [
                goAgainBtn,
                const SizedBox(width: 10),
                finishBtn,
              ]);
            },
          ),
        ),
      ),
    );
  }

  Future<void> _goAgainDeletingAttempt(BuildContext context) async {
    // Light blocking loader while we delete + route
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    String? pid = poolId;

    try {
      // If we don't have poolId yet, read it from the attempt doc
      if ((pid == null || pid.isEmpty) &&
          attemptId != null &&
          attemptId!.trim().isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('test_attempts')
            .doc(attemptId)
            .get();
        pid = (snap.data()?['pool_id'] as String?) ?? '';
      }

      // Delete current attempt first (if we know it)
      if (attemptId != null && attemptId!.trim().isNotEmpty) {
        try {
          await FirebaseFirestore.instance
              .collection('test_attempts')
              .doc(attemptId)
              .delete();
        } catch (e) {
          // Non-fatal: we still allow retake, but let the user know.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Couldn\'t delete previous attempt: $e')),
          );
        }
      }

      // Need a poolId to retake
      if (pid == null || pid.isEmpty) {
        Navigator.of(context, rootNavigator: true).pop(); // close loader
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't resolve the test to retake."),
        ));
        return;
      }

      // Close loader and retake
      Navigator.of(context, rootNavigator: true).pop();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AttendTestPage(poolId: pid!)),
      );
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop(); // close loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Something went wrong: $e')),
      );
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String poolTitle;
  final double scorePct;
  final bool pass;
  final int passingPct;
  final int total;
  final int attempted;
  final int correct;

  const _SummaryCard({
    required this.poolTitle,
    required this.scorePct,
    required this.pass,
    required this.passingPct,
    required this.total,
    required this.attempted,
    required this.correct,
  });

  @override
  Widget build(BuildContext context) {
    final score = scorePct.round();
    final wrong = attempted - correct;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12.withOpacity(.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(poolTitle,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 10),
          Row(
            children: [
              _ScoreDonut(score: score, pass: pass),
              const SizedBox(width: 14),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Meta('Result', pass ? 'PASS' : 'FAIL',
                        color: pass ? Colors.green : Colors.red),
                    _Meta('Passing', '$passingPct%'),
                    _Meta('Total', '$total'),
                    _Meta('Attempted', '$attempted'),
                    _Meta('Correct', '$correct'),
                    _Meta('Wrong', '$wrong'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreDonut extends StatelessWidget {
  final int score;
  final bool pass;
  const _ScoreDonut({required this.score, required this.pass});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100.0,
            strokeWidth: 10,
            color: pass ? Colors.green : Colors.red,
            backgroundColor: const Color(0xFFE9ECEF),
          ),
          Text('$score%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: pass ? Colors.green.shade800 : Colors.red.shade800,
              )),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _Meta(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) {
    final valStyle = TextStyle(
      fontWeight: FontWeight.w800,
      color: color ?? Colors.black87,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade700,
                letterSpacing: .5,
              )),
          const SizedBox(height: 2),
          Text(value, style: valStyle),
        ],
      ),
    );
  }
}

class _ResultItemCard extends StatelessWidget {
  final int index;
  final ResultItem item;

  const _ResultItemCard({required this.index, required this.item});

  @override
  Widget build(BuildContext context) {
    final good = item.isCorrect;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: good
              ? Colors.green.withOpacity(.35)
              : Colors.red.withOpacity(.35),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (good ? Colors.green : Colors.red).withOpacity(.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: (good ? Colors.green : Colors.red)
                            .withOpacity(.35)),
                  ),
                  child: Row(
                    children: [
                      Icon(good ? Icons.check_circle : Icons.cancel,
                          size: 16,
                          color: good ? Colors.green : Colors.red),
                      const SizedBox(width: 6),
                      Text(
                        good ? 'CORRECT' : 'WRONG',
                        style: TextStyle(
                          color: good ? Colors.green : Colors.red,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Question $index',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
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
                    item.type == QuestionTypeResult.mcq
                        ? 'MCQ'
                        : 'PARAGRAPH',
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.question,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, height: 1.2)),
            if ((item.imageUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(item.imageUrl!, fit: BoxFit.cover),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (item.type == QuestionTypeResult.mcq)
              Column(
                children: List.generate(item.options.length, (i) {
                  final option = item.options[i];
                  final isCorrect = item.correctIndex == i;
                  final isSelected = item.selectedIndex == i;

                  Color? textColor;
                  IconData? icon;

                  if (isCorrect) {
                    textColor = Colors.green.shade800;
                    icon = Icons.check_circle;
                  } else if (isSelected && !isCorrect) {
                    textColor = Colors.red.shade800;
                    icon = Icons.cancel;
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: isCorrect
                          ? Colors.green.withOpacity(.06)
                          : isSelected && !isCorrect
                              ? Colors.red.withOpacity(.06)
                              : Colors.grey.shade50,
                      border: Border.all(
                        color: isCorrect
                            ? Colors.green.withOpacity(.35)
                            : isSelected && !isCorrect
                                ? Colors.red.withOpacity(.35)
                                : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: textColor),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            '${String.fromCharCode(65 + i)}) $option',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: textColor ?? Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _KV('Your answer', item.typedAnswer ?? '-', bad: !item.isCorrect),
                  const SizedBox(height: 6),
                  _KV('Expected', item.expectedAnswer ?? '-', good: true),
                ],
              ),
            if (item.explanation.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.explanation,
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

class _KV extends StatelessWidget {
  final String k;
  final String v;
  final bool good;
  final bool bad;
  const _KV(this.k, this.v, {this.good = false, this.bad = false});
  @override
  Widget build(BuildContext context) {
    final col = good
        ? Colors.green.shade800
        : bad
            ? Colors.red.shade800
            : Colors.black87;
    final bg = good
        ? Colors.green.withOpacity(.06)
        : bad
            ? Colors.red.withOpacity(.06)
            : Colors.grey.shade50;
    final br = good
        ? Colors.green.withOpacity(.35)
        : bad
            ? Colors.red.withOpacity(.35)
            : Colors.grey.shade300;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: br),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(k.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade700,
                    letterSpacing: .5)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              v,
              style: TextStyle(fontWeight: FontWeight.w600, color: col),
            ),
          ),
        ],
      ),
    );
  }
}
