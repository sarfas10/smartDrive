// mock_tests_list_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'attend_test_page.dart';

const kBrand = Color(0xFF4c63d2);

class MockTestsListPage extends StatelessWidget {
  /// Optionally pass the currently-logged in user/student id (to forward to Attend page)
  final String? studentId;
  const MockTestsListPage({super.key, this.studentId});

  @override
  Widget build(BuildContext context) {
    // NOTE: No .where('status'...) here to avoid composite index requirement.
    final stream = FirebaseFirestore.instance
        .collection('test_pool')
        .orderBy('created_at', descending: true)
        .snapshots();

    final isCompact = MediaQuery.of(context).size.width < 420;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: kBrand,
        title: const Text('Available Mock Tests'),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: stream,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _CenteredLoader();
            }
            if (snap.hasError) {
              return _CenteredError('Failed to load tests: ${snap.error}');
            }

            // Client-side filter: only "active"
            final all = snap.data?.docs ?? [];
            final activeDocs = all.where((d) {
              final m = d.data() as Map<String, dynamic>;
              return (m['status'] ?? 'inactive').toString().toLowerCase() == 'active';
            }).toList();

            if (activeDocs.isEmpty) {
              return const _CenteredEmpty(
                title: 'No mock tests yet',
                caption: 'Please check back later.',
              );
            }

            return ListView.separated(
              padding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 16,
                vertical: 14,
              ),
              itemCount: activeDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final d = activeDocs[i];
                final m = d.data() as Map<String, dynamic>;
                final title = (m['title'] ?? '').toString();
                final desc = (m['description'] ?? '').toString();
                final duration = (m['duration_minutes'] ?? 0) as int;
                final passing = (m['passing_score_pct'] ?? 0) as int;
                final createdAt = (m['created_at'] as Timestamp?)?.toDate();

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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title.isEmpty ? '-' : title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: kBrand,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => AttendTestPage(
                                      poolId: d.id,
                                      studentId: studentId,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: const Text('Start'),
                            ),
                          ],
                        ),

                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.35,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],

                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MetaChip(icon: Icons.timer_outlined, text: '$duration min'),
                            _MetaChip(icon: Icons.verified_outlined, text: 'Pass $passing%'),
                            if (createdAt != null)
                              _MetaChip(
                                icon: Icons.calendar_today_outlined,
                                text: _fmtDate(createdAt),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _MetaChip({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: CircularProgressIndicator(),
        ),
      );
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
              Icon(Icons.fact_check_outlined, size: 64, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Text(caption, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
}

class _CenteredError extends StatelessWidget {
  final String message;
  const _CenteredError(this.message);
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(message, style: const TextStyle(color: Colors.red)),
        ),
      );
}

String _fmtDate(DateTime dt) {
  final d = dt.toLocal();
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}
