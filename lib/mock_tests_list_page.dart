// lib/mock_tests_list_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'attend_test_page.dart';

// Import your design tokens & theme helpers — adjust the path if needed.
import 'theme/app_theme.dart';

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
      backgroundColor: context.c.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.brand,
        title: Text('Available Mock Tests', style: AppText.sectionTitle.copyWith(color: AppColors.onSurfaceInverse)),
        foregroundColor: AppColors.onSurfaceInverse,
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
                    color: context.c.surface,
                    borderRadius: BorderRadius.circular(AppRadii.l),
                    border: Border.all(color: AppColors.divider),
                    boxShadow: AppShadows.card,
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
                                style: context.t.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                  color: context.c.onSurface,
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.brand,
                                foregroundColor: AppColors.onSurfaceInverse,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.m)),
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
                            style: context.t.bodySmall?.copyWith(
                              color: AppColors.onSurfaceMuted,
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
        color: AppColors.neuBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.neuBg.withOpacity(0.9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.neuFg),
          const SizedBox(width: 6),
          Text(text, style: context.t.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: context.c.onSurface)),
        ],
      ),
    );
  }
}

class _CenteredLoader extends StatelessWidget {
  const _CenteredLoader();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(context.c.primary),
          ),
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
              Icon(Icons.fact_check_outlined, size: 64, color: AppColors.onSurfaceFaint),
              const SizedBox(height: 12),
              Text(title, style: context.t.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted)),
              const SizedBox(height: 6),
              Text(caption, style: context.t.bodySmall?.copyWith(color: AppColors.onSurfaceFaint)),
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
          child: Text(message, style: context.t.bodyMedium?.copyWith(color: AppColors.danger)),
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
