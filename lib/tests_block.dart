import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';

class TestsBlock extends StatelessWidget {
  final VoidCallback onCreatePool;
  const TestsBlock({super.key, required this.onCreatePool});

  @override
  Widget build(BuildContext context) {
    final pools = FirebaseFirestore.instance.collection('tests_pools').orderBy('created_at', descending: true);
    return ListView(
      children: [
        TableHeader(
          title: 'Test Pools',
          trailing: ElevatedButton.icon(onPressed: onCreatePool, icon: const Icon(Icons.add), label: const Text('Create Pool')),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: StreamBuilder<QuerySnapshot>(
            stream: pools.snapshots(),
            builder: (context, snap) {
              final rows = <List<Widget>>[];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final m = d.data() as Map;
                  rows.add([
                    Text(m['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    Text(m['category']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    Text('${m['duration_minutes'] ?? 0} min'),
                    Text('${m['passing_score_pct'] ?? 0}%'),
                    StatusBadge(text: (m['status'] ?? 'active').toString(), type: 'active'),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ElevatedButton(onPressed: () => _openQuestions(context, d.id, m['title'] ?? ''), child: const Text('Questions')),
                        ElevatedButton(onPressed: () => _openAttempts(context, d.id), child: const Text('Attempts')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                          onPressed: () async => d.reference.update({'status': 'inactive', 'updated_at': FieldValue.serverTimestamp()}),
                          child: const Text('Deactivate'),
                        ),
                      ],
                    ),
                  ]);
                }
              }
              return DataTableWrap(columns: const ['Name', 'Category', 'Duration', 'Passing', 'Status', 'Actions'], rows: rows);
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openQuestions(BuildContext context, String poolId, String poolTitle) async {
    final q = FirebaseFirestore.instance.collection('test_questions').where('pool_id', isEqualTo: poolId).orderBy('created_at', descending: true);
    final questionCtrl = TextEditingController();
    final optA = TextEditingController(), optB = TextEditingController(), optC = TextEditingController(), optD = TextEditingController();
    final answerCtrl = TextEditingController(text: '0'); // index 0..3
    final explainCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Questions — $poolTitle'),
        content: SizedBox(
          width: 700,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppCard(
                title: 'Add Question',
                child: Column(
                  children: [
                    area('Question', questionCtrl),
                    const SizedBox(height: 8),
                    field('Option A', optA),
                    const SizedBox(height: 8),
                    field('Option B', optB),
                    const SizedBox(height: 8),
                    field('Option C', optC),
                    const SizedBox(height: 8),
                    field('Option D', optD),
                    const SizedBox(height: 8),
                    field('Correct Option Index (0-3)', answerCtrl, number: true),
                    const SizedBox(height: 8),
                    area('Explanation (optional)', explainCtrl),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance.collection('test_questions').add({
                            'pool_id': poolId,
                            'question': questionCtrl.text.trim(),
                            'options': [optA.text.trim(), optB.text.trim(), optC.text.trim(), optD.text.trim()],
                            'answer_index': int.tryParse(answerCtrl.text.trim()) ?? 0,
                            'explanation': explainCtrl.text.trim(),
                            'created_at': FieldValue.serverTimestamp(),
                          });
                          questionCtrl.clear();
                          optA.clear();
                          optB.clear();
                          optC.clear();
                          optD.clear();
                          explainCtrl.clear();
                        },
                        child: const Text('Add'),
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 300,
                child: StreamBuilder<QuerySnapshot>(
                  stream: q.snapshots(),
                  builder: (context, snap) {
                    final children = <Widget>[];
                    if (snap.hasData) {
                      for (final d in snap.data!.docs) {
                        final m = d.data() as Map;
                        children.add(Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(8),
                            border: const Border(left: BorderSide(color: Color(0xFF4c63d2), width: 4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m['question']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              ...List.generate((m['options'] as List?)?.length ?? 0, (i) {
                                final isCorrect = i == (m['answer_index'] ?? -1);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text('${String.fromCharCode(65 + i)}) ${(m['options'][i] ?? '').toString()}${isCorrect ? '  ✓' : ''}'),
                                );
                              }),
                              if ((m['explanation']?.toString() ?? '').isNotEmpty) Text('Explanation: ${m['explanation']}'),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                    onPressed: () async => d.reference.delete(),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ));
                      }
                    }
                    return ListView(children: children);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _openAttempts(BuildContext context, String poolId) async {
    final q = FirebaseFirestore.instance.collection('test_attempts').where('pool_id', isEqualTo: poolId).orderBy('started_at', descending: true);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Test Attempts'),
        content: SizedBox(
          width: 700,
          height: 400,
          child: StreamBuilder<QuerySnapshot>(
            stream: q.snapshots(),
            builder: (context, snap) {
              final rows = <List<Widget>>[];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final m = d.data() as Map;
                  rows.add([
                    Text(m['student_id']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    Text('${m['score'] ?? 0}'),
                    Text(m['status']?.toString() ?? '-'),
                    Text((m['started_at'] as Timestamp?)?.toDate().toString().split('.').first ?? '-'),
                    Text((m['completed_at'] as Timestamp?)?.toDate().toString().split('.').first ?? '-'),
                  ]);
                }
              }
              return DataTableWrap(columns: const ['Student', 'Score', 'Status', 'Started', 'Completed'], rows: rows);
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}
