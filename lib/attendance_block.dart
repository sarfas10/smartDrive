import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';

class AttendanceBlock extends StatelessWidget {
  const AttendanceBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final q = FirebaseFirestore.instance.collection('attendance').orderBy('date', descending: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TableHeader(title: 'Attendance Records'),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: q.snapshots(),
              builder: (context, snap) {
                final rows = <List<Widget>>[];
                if (snap.hasData) {
                  for (final d in snap.data!.docs) {
                    final m = d.data() as Map;
                    rows.add([
                      Text(m['slot_id']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                      Text(m['student_id']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                      Text(m['date']?.toString() ?? '-'),
                      StatusBadge(text: (m['status']?.toString() ?? 'absent'), type: (m['status'] == 'present') ? 'approved' : 'rejected'),
                      ElevatedButton(
                        onPressed: () async {
                          await d.reference.update({'status': 'present', 'marked_by': 'admin', 'updated_at': FieldValue.serverTimestamp()});
                        },
                        child: const Text('Mark Present'),
                      ),
                    ]);
                  }
                }
                return DataTableWrap(columns: const ['Slot', 'Student', 'Date', 'Status', 'Actions'], rows: rows);
              },
            ),
          ),
        ),
      ],
    );
  }
}
