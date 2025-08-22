import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';

class MaterialsBlock extends StatelessWidget {
  const MaterialsBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance.collection('materials').orderBy('created_at', descending: true);
    final titleCtrl = TextEditingController();
    final categoryCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final versionCtrl = TextEditingController(text: '1');

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: AppCard(
            title: 'Upload Study Materials (reference record)',
            child: Column(
              children: [
                field('Material Title', titleCtrl),
                const SizedBox(height: 8),
                field('Category', categoryCtrl),
                const SizedBox(height: 8),
                field('File URL', urlCtrl),
                const SizedBox(height: 8),
                field('Version', versionCtrl, number: true),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance.collection('materials').add({
                        'title': titleCtrl.text.trim(),
                        'category': categoryCtrl.text.trim(),
                        'file_url': urlCtrl.text.trim(),
                        'version': int.tryParse(versionCtrl.text.trim()) ?? 1,
                        'downloads': 0,
                        'created_at': FieldValue.serverTimestamp(),
                      });
                      titleCtrl.clear();
                      categoryCtrl.clear();
                      urlCtrl.clear();
                    },
                    child: const Text('Save Material'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'Current Study Materials'),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: StreamBuilder<QuerySnapshot>(
            stream: q.snapshots(),
            builder: (context, snap) {
              final rows = <List<Widget>>[];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final m = d.data() as Map;
                  rows.add([
                    Text(m['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    Text(m['category']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    Text(Uri.tryParse(m['file_url']?.toString() ?? '')?.pathSegments.last.split('.').last.toUpperCase() ?? 'FILE'),
                    Text((m['created_at'] as Timestamp?)?.toDate().toString().split(' ').first ?? '-'),
                    Text((m['downloads'] ?? 0).toString()),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ElevatedButton(onPressed: () {}, child: const Text('Edit')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                          onPressed: () async => d.reference.delete(),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ]);
                }
              }
              return DataTableWrap(columns: const ['Title', 'Category', 'Type', 'Uploaded', 'Downloads', 'Actions'], rows: rows);
            },
          ),
        ),
      ],
    );
  }
}
