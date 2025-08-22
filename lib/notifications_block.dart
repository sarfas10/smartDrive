import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';

class NotificationsBlock extends StatefulWidget {
  const NotificationsBlock({super.key});
  @override
  State<NotificationsBlock> createState() => _NotificationsBlockState();
}

class _NotificationsBlockState extends State<NotificationsBlock> {
  final titleCtrl = TextEditingController();
  final msgCtrl = TextEditingController();
  final urlCtrl = TextEditingController();
  String schedule = 'Send Now';
  DateTime? when;
  final segments = <String>{};

  @override
  Widget build(BuildContext context) {
    final history = FirebaseFirestore.instance.collection('notifications').orderBy('created_at', descending: true);
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: AppCard(
            title: 'Send Push Notification (record)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _seg('all'),
                    _seg('students'),
                    _seg('instructors'),
                    _seg('pending'),
                    _seg('active'),
                  ],
                ),
                const SizedBox(height: 12),
                field('Notification Title', titleCtrl),
                const SizedBox(height: 8),
                area('Message', msgCtrl),
                const SizedBox(height: 8),
                field('Action URL (optional)', urlCtrl),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: schedule,
                  items: const [
                    DropdownMenuItem(value: 'Send Now', child: Text('Send Now')),
                    DropdownMenuItem(value: 'Schedule for Later', child: Text('Schedule for Later')),
                  ],
                  onChanged: (v) => setState(() => schedule = v ?? 'Send Now'),
                  decoration: const InputDecoration(labelText: 'Schedule', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                if (schedule == 'Schedule for Later')
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        initialDate: DateTime.now().add(const Duration(days: 1)),
                      );
                      if (picked != null) {
                        final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                        if (t != null) {
                          setState(() => when = DateTime(picked.year, picked.month, picked.day, t.hour, t.minute));
                        }
                      }
                    },
                    child: Text(when == null ? 'Pick Date & Time' : when.toString()),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'title': titleCtrl.text.trim(),
                            'message': msgCtrl.text.trim(),
                            'segments': segments.toList(),
                            'action_url': urlCtrl.text.trim(),
                            'schedule': schedule,
                            'scheduled_at': when,
                            'status': schedule == 'Send Now' ? 'sent' : 'scheduled',
                            'created_at': FieldValue.serverTimestamp(),
                          });
                          titleCtrl.clear();
                          msgCtrl.clear();
                          urlCtrl.clear();
                          setState(() {
                            schedule = 'Send Now';
                            when = null;
                            segments.clear();
                          });
                        },
                        child: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                        onPressed: () async {
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'title': titleCtrl.text.trim(),
                            'message': msgCtrl.text.trim(),
                            'segments': segments.toList(),
                            'action_url': urlCtrl.text.trim(),
                            'schedule': schedule,
                            'scheduled_at': when,
                            'status': 'draft',
                            'created_at': FieldValue.serverTimestamp(),
                          });
                          titleCtrl.clear();
                          msgCtrl.clear();
                          urlCtrl.clear();
                          setState(() {
                            schedule = 'Send Now';
                            when = null;
                            segments.clear();
                          });
                        },
                        child: const Text('Save as Draft'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SectionHeader(title: 'Notification History'),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: StreamBuilder<QuerySnapshot>(
            stream: history.snapshots(),
            builder: (context, snap) {
              final rows = <List<Widget>>[];
              if (snap.hasData) {
                for (final d in snap.data!.docs) {
                  final m = d.data() as Map;
                  rows.add([
                    Text(m['title']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                    Text((m['segments'] as List?)?.join(', ') ?? 'all', overflow: TextOverflow.ellipsis),
                    Text((m['created_at'] as Timestamp?)?.toDate().toString().split(' ').first ?? '-'),
                    Text(m['status']?.toString() ?? '-'),
                    ElevatedButton(onPressed: () {}, child: const Text('View')),
                  ]);
                }
              }
              return DataTableWrap(columns: const ['Title', 'Target', 'Created', 'Status', 'Actions'], rows: rows);
            },
          ),
        ),
      ],
    );
  }

  Widget _seg(String s) {
    final selected = segments.contains(s);
    return InkWell(
      onTap: () => setState(() => selected ? segments.remove(s) : segments.add(s)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF4c63d2), width: 2),
          color: selected ? const Color(0xFF4c63d2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(s, style: TextStyle(color: selected ? Colors.white : const Color(0xFF4c63d2), fontWeight: FontWeight.w600)),
      ),
    );
  }
}
