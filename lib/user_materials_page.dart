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

  /// Build a Firestore query that avoids composite-index requirements:
  /// - If category is "All": do server-side ordering (fast, no where).
  /// - If a specific category is selected: only use `where` and sort on the client.
  Query _buildQuery() {
    final col = FirebaseFirestore.instance.collection('materials');

    if (_selectedCategory == 'All') {
      switch (_sortBy) {
        case 'Oldest':
          return col.orderBy('created_at', descending: false);
        case 'Downloads':
          return col.orderBy('downloads', descending: true).orderBy('created_at', descending: true);
        case 'Title A–Z':
          return col.orderBy('title', descending: false);
        case 'Newest':
        default:
          return col.orderBy('created_at', descending: true);
      }
    } else {
      // Category selected: only filter; sort client-side to avoid composite index
      return col.where('category', isEqualTo: _selectedCategory);
    }
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
      appBar: AppBar(
        title: const Text("Study Materials"),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Sort',
            initialValue: _sortBy,
            onSelected: (v) => setState(() => _sortBy = v),
            itemBuilder: (_) =>
                _sortOptions.map((s) => PopupMenuItem<String>(value: s, child: Text(s))).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () => setState(() {}));
              },
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

          // Category chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
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

          const Divider(height: 1),

          // List (rows)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              key: _streamKey,
              stream: query.snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  // Show a helpful message; log full error to console.
                  // If you see an index link in the error, you can tap it in logs.
                  // ignore: avoid_print
                  print('Materials stream error: ${snap.error}');
                  return _ErrorView(
                    message: 'Could not load materials.',
                    detail: snap.error.toString(),
                  );
                }

                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(child: Text("No materials available"));
                }

                // Map documents
                final rawDocs = snap.data!.docs.map((d) {
                  final m = (d.data() as Map<String, dynamic>);
                  return _MaterialRowModel(
                    id: d.id,
                    title: (m['title'] ?? '').toString(),
                    description: (m['description'] ?? '').toString(),
                    category: (m['category'] ?? '').toString(),
                    fileUrl: (m['file_url'] ?? '').toString(),
                    kind: (m['detected_type'] ?? 'other').toString(),
                    downloads: (m['downloads'] is num) ? (m['downloads'] as num).toInt() : 0,
                    createdAt: (m['created_at'] is Timestamp)
                        ? (m['created_at'] as Timestamp).toDate()
                        : null,
                    titleLower: (m['title'] ?? '').toString().toLowerCase(),
                    descLower: (m['description'] ?? '').toString().toLowerCase(),
                  );
                }).toList();

                // Client-side search filter
                final search = _searchCtrl.text.trim().toLowerCase();
                var docs = rawDocs.where((r) {
                  if (search.isEmpty) return true;
                  return r.titleLower.contains(search) || r.descLower.contains(search);
                }).toList();

                // Client-side sort when category filtered; otherwise keep server order
                if (_selectedCategory != 'All') {
                  docs.sort((a, b) {
                    switch (_sortBy) {
                      case 'Oldest':
                        final at = a.createdAt?.millisecondsSinceEpoch ?? -1;
                        final bt = b.createdAt?.millisecondsSinceEpoch ?? -1;
                        return at.compareTo(bt);
                      case 'Downloads':
                        final c = b.downloads.compareTo(a.downloads);
                        if (c != 0) return c;
                        // tie-breaker: newest first
                        final at2 = a.createdAt?.millisecondsSinceEpoch ?? -1;
                        final bt2 = b.createdAt?.millisecondsSinceEpoch ?? -1;
                        return bt2.compareTo(at2);
                      case 'Title A–Z':
                        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
                      case 'Newest':
                      default:
                        final at3 = a.createdAt?.millisecondsSinceEpoch ?? -1;
                        final bt3 = b.createdAt?.millisecondsSinceEpoch ?? -1;
                        return bt3.compareTo(at3);
                    }
                  });
                }

                if (docs.isEmpty) {
                  return const Center(child: Text("No results found"));
                }

                return ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = docs[i];
                    final icon = _typeIcon(r.kind);
                    final color = _typeColor(r.kind);

                    final subtitle = StringBuffer();
                    if (r.description.isNotEmpty) {
                      subtitle.write(r.description);
                      subtitle.write('\n');
                    }
                    subtitle.write('${r.downloads} downloads');

                    return ListTile(
                      dense: false,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      leading: Icon(icon, color: color),
                      title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        subtitle.toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.open_in_new, color: Colors.deepPurple),
                        onPressed: () => _openAndCount(r.id, r.fileUrl),
                      ),
                      onTap: () => _openAndCount(r.id, r.fileUrl),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
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
}

/// Row model for easier client-side sort/filter
class _MaterialRowModel {
  final String id;
  final String title;
  final String description;
  final String category;
  final String fileUrl;
  final String kind;
  final int downloads;
  final DateTime? createdAt;
  final String titleLower;
  final String descLower;

  _MaterialRowModel({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.fileUrl,
    required this.kind,
    required this.downloads,
    required this.createdAt,
    required this.titleLower,
    required this.descLower,
  });
}

/// Nice inline error view with details (helps spot index errors)
class _ErrorView extends StatelessWidget {
  final String message;
  final String? detail;

  const _ErrorView({required this.message, this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (detail != null) ...[
            const SizedBox(height: 8),
            Text(
              detail!,
              style: TextStyle(color: Colors.grey[700]),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
