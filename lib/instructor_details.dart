// instructor_details.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InstructorDetailsPage extends StatelessWidget {
  const InstructorDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final uid = args?['uid'] as String?;
    if (uid == null || uid.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Instructor Details')),
        body: const Center(child: Text('No UID provided')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Instructor Details')),
      body: _InstructorDetailsBody(uid: uid),
    );
  }
}

class _InstructorDetailsBody extends StatelessWidget {
  final String uid;
  const _InstructorDetailsBody({required this.uid});

  Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream() async* {
    final q = await FirebaseFirestore.instance
        .collection('users')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();

    if (q.docs.isNotEmpty) {
      yield* FirebaseFirestore.instance.collection('users').doc(q.docs.first.id).snapshots();
      return;
    }
    yield* FirebaseFirestore.instance.collection('users').doc(uid).snapshots();
  }

  Stream<Map<String, dynamic>> _profileStream() {
    return FirebaseFirestore.instance
        .collection('user_profiles')
        .where('uid', isEqualTo: uid)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty ? snap.docs.first.data() : <String, dynamic>{});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDocStream(),
      builder: (context, userSnap) {
        if (userSnap.hasError) {
          return _error('Failed to load user: ${userSnap.error}');
        }
        if (!userSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = userSnap.data!.data() ?? {};

        return StreamBuilder<Map<String, dynamic>>(
          stream: _profileStream(),
          builder: (context, profSnap) {
            final profile = profSnap.data ?? {};
            final name = (user['name'] ?? 'Instructor').toString();
            final email = (user['email'] ?? '-').toString();
            final phone = (user['phone'] ?? '-').toString();
            final status = (user['status'] ?? 'active').toString();
            final role = (user['role'] ?? 'instructor').toString();

            final address1 = (profile['address_line1'] ?? '-').toString();
            final address2 = (profile['address_line2'] ?? '').toString();
            final zipcode = (profile['zipcode'] ?? '-').toString();
            final dob = (profile['dob'] ?? '-').toString();
            final photo = (profile['photo_url'] ?? '').toString();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
                        child: photo.isEmpty ? Text(name.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _chip('Role: ${role[0].toUpperCase()}${role.substring(1)}'),
                                _statusChip(status),
                                _chip('UID: $uid'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionCard('Contact', [
                    _row('Email', email),
                    _row('Phone', phone),
                  ]),
                  const SizedBox(height: 12),
                  _sectionCard('Profile', [
                    _row('DOB', dob),
                    _row('Address', address1),
                    if (address2.isNotEmpty) _row('Address 2', address2),
                    _row('Zipcode', zipcode),
                  ]),

                  // Example: payout stats placeholder (extend later)
                  const SizedBox(height: 12),
                  _sectionCard('Payouts (sample)', [
                    _row('Total Payouts', '—'),
                    _row('Last Paid', '—'),
                  ]),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _sectionCard(String title, List<Widget> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          ...rows,
        ]),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.25)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _statusChip(String status) {
    Color c;
    switch (status.toLowerCase()) {
      case 'active':
        c = Colors.green;
        break;
      case 'pending':
        c = Colors.orange;
        break;
      case 'blocked':
        c = Colors.red;
        break;
      default:
        c = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Text('Status: ${status[0].toUpperCase()}${status.substring(1)}',
          style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
    );
  }

  Widget _error(String msg) => Center(child: Text(msg));
}
