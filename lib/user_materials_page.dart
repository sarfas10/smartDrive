import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

class UserMaterialsPage extends StatefulWidget {
  const UserMaterialsPage({super.key});

  @override
  State<UserMaterialsPage> createState() => _UserMaterialsPageState();
}

class _UserMaterialsPageState extends State<UserMaterialsPage> {
  // ── Filters & Sort ─────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  final List<String> _categories = const [
    'All',
    'Theory',
    'Practical Driving',
    'Traffic Rules',
    'Road Signs',
    'Safety Guidelines',
    'Vehicle Maintenance',
    'Mock Tests',
    'Highway Code',
  ];
  String _selectedCategory = 'All';

  String _sortBy = 'Newest';
  final List<String> _sortOptions = const ['Newest', 'Oldest', 'Downloads', 'Title A–Z'];

  Key _streamKey = UniqueKey();

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Query _buildQuery() {
    Query q = FirebaseFirestore.instance.collection('materials');
    if (_selectedCategory != 'All') {
      q = q.where('category', isEqualTo: _selectedCategory);
    }
    switch (_sortBy) {
      case 'Oldest':
        q = q.orderBy('created_at', descending: false);
        break;
      case 'Downloads':
        q = q.orderBy('downloads', descending: true).orderBy('created_at', descending: true);
        break;
      case 'Title A–Z':
        q = q.orderBy('title', descending: false);
        break;
      case 'Newest':
      default:
        q = q.orderBy('created_at', descending: true);
    }
    return q;
  }

  Future<void> _openAndCount(String docId, String url) async {
    if (url.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('materials').doc(docId).update({
        'downloads': FieldValue.increment(1),
      });
    } catch (_) {}
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyLink(String url) {
    if (url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    _snack('Link copied');
  }

  Future<void> _refresh() async {
    setState(() => _streamKey = UniqueKey());
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() {}));
  }

  String _formatBytes(int? bytes) {
    if (bytes == null) return '-';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Color _typeColor(String k) {
    switch (k) {
      case 'pdf': return Colors.red;
      case 'image': return Colors.blueGrey;
      case 'video': return Colors.blue;
      case 'audio': return Colors.deepPurple;
      case 'archive': return Colors.brown;
      case 'doc': return Colors.green;
      default: return Colors.grey;
    }
  }

  IconData _typeIcon(String k) {
    switch (k) {
      case 'pdf': return Icons.picture_as_pdf;
      case 'image': return Icons.image_outlined;
      case 'video': return Icons.video_file;
      case 'audio': return Icons.audiotrack;
      case 'archive': return Icons.archive_outlined;
      case 'doc': return Icons.description_outlined;
      default: return Icons.insert_drive_file_outlined;
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final query = _buildQuery();

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          slivers: [
            // Top row: back + sort
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    PopupMenuButton<String>(
                      tooltip: 'Sort',
                      icon: const Icon(Icons.sort),
                      initialValue: _sortBy,
                      onSelected: (v) => setState(() => _sortBy = v),
                      itemBuilder: (_) => _sortOptions
                          .map((s) => PopupMenuItem<String>(value: s, child: Text(s)))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),

            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search by title or description',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear',
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

            // Category chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  itemBuilder: (_, i) {
                    final c = _categories[i];
                    return ChoiceChip(
                      label: Text(c),
                      selected: c == _selectedCategory,
                      onSelected: (_) => setState(() => _selectedCategory = c),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _categories.length,
                ),
              ),
            ),

            // Grid
            StreamBuilder<QuerySnapshot>(
              key: _streamKey,
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return _loadingBox();
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return _emptyBox('No materials available');
                }

                final search = _searchCtrl.text.trim().toLowerCase();
                final docs = snap.data!.docs.where((d) {
                  if (search.isEmpty) return true;
                  final m = d.data() as Map<String, dynamic>;
                  final t = (m['title'] ?? '').toString().toLowerCase();
                  final desc = (m['description'] ?? '').toString().toLowerCase();
                  return t.contains(search) || desc.contains(search);
                }).toList();

                if (docs.isEmpty) {
                  return _emptyBox('No results found');
                }

                return SliverPadding(
                  padding: const EdgeInsets.all(8),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 1.45,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) {
                        final d = docs[i];
                        final m = d.data() as Map<String, dynamic>;
                        final id = d.id;
                        final title = (m['title'] ?? '').toString();
                        final desc = (m['description'] ?? '').toString();
                        final category = (m['category'] ?? '').toString();
                        final version = (m['version'] ?? '1.0').toString();
                        final fileUrl = (m['file_url'] ?? '').toString();
                        final fileName = (m['file_name'] ?? '').toString();
                        final fileSize = (m['file_size'] is num) ? (m['file_size'] as num).toInt() : null;
                        final kind = (m['detected_type'] ?? 'other').toString();
                        final downloads = (m['downloads'] is num) ? (m['downloads'] as num).toInt() : 0;
                        final createdAt = (m['created_at'] is Timestamp)
                            ? (m['created_at'] as Timestamp).toDate()
                            : null;
                        final tc = _typeColor(kind);
                        final ti = _typeIcon(kind);
                        final dateStr = createdAt == null
                            ? '-'
                            : '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';

                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: tc.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(ti, color: tc),
                                    ),
                                    const SizedBox(width: 10),
                                    _chip(kind.toUpperCase(), tc),
                                    const Spacer(),
                                    _chip(category, Colors.deepPurple),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 16, fontWeight: FontWeight.w800)),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Text(desc,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.grey.shade700)),
                                ],
                                const SizedBox(height: 8),
                                _meta(Icons.badge_outlined, 'Version', version),
                                _meta(Icons.insert_drive_file_outlined, 'File name',
                                    fileName.isEmpty ? '-' : fileName),
                                _meta(Icons.storage, 'Size', _formatBytes(fileSize)),
                                _meta(Icons.calendar_today_outlined, 'Uploaded', dateStr),
                                const Spacer(),
                                Row(
                                  children: [
                                    const Icon(Icons.download,
                                        size: 16, color: Colors.green),
                                    const SizedBox(width: 6),
                                    Text('$downloads downloads',
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.deepPurple,
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _openAndCount(id, fileUrl),
                                      icon: const Icon(Icons.open_in_new, size: 18),
                                      label: const Text('Open'),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: docs.length,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
      );

  Widget _meta(IconData i, String l, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(i, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text('$l: ',
                style: TextStyle(
                    color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            Expanded(
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            )
          ],
        ),
      );

  SliverToBoxAdapter _loadingBox() => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );

  SliverToBoxAdapter _emptyBox(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(child: Text(text, style: TextStyle(color: Colors.grey))),
        ),
      );
}
