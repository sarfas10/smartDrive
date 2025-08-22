import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';

class UsersBlock extends StatefulWidget {
  const UsersBlock({super.key});
  @override
  State<UsersBlock> createState() => _UsersBlockState();
}

class _UsersBlockState extends State<UsersBlock> {
  String roleFilter = 'all';     // all | student | instructor
  String statusFilter = 'all';   // all | pending | active | blocked
  final searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 700;

    // ---- Build query (no composite index needed) ----
    final hasRole   = roleFilter != 'all';
    final hasStatus = statusFilter != 'all';

    Query base = FirebaseFirestore.instance.collection('users');
    if (hasRole)   base = base.where('role',   isEqualTo: roleFilter);
    if (hasStatus) base = base.where('status', isEqualTo: statusFilter);
    if (!hasRole && !hasStatus) {
      // Only order on server when no filters to avoid composite index
      base = base.orderBy('name');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Filters row (title removed) ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterPill(label: 'All',         selected: roleFilter == 'all',        onTap: () => setState(() => roleFilter = 'all')),
              FilterPill(label: 'Students',    selected: roleFilter == 'student',    onTap: () => setState(() => roleFilter = 'student')),
              FilterPill(label: 'Instructors', selected: roleFilter == 'instructor', onTap: () => setState(() => roleFilter = 'instructor')),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: statusFilter,
                items: const [
                  DropdownMenuItem(value: 'all',     child: Text('All Status')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'active',  child: Text('Active')),
                  DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                ],
                onChanged: (v) => setState(() => statusFilter = v ?? 'all'),
              ),
            ],
          ),
        ),
        // ---- Search row (moved below filters) ----
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: SizedBox(
            width: double.infinity,
            child: TextField(
              controller: searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search name / email / phone',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: StreamBuilder<QuerySnapshot>(
              stream: base.snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      'Error loading users:\n${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // ---- Client-side search ----
                final q = searchCtrl.text.trim().toLowerCase();
                final docs = snap.data!.docs.where((d) {
                  final m = (d.data() as Map<String, dynamic>);
                  final hay = '${m['name'] ?? ''} ${m['email'] ?? ''} ${m['phone'] ?? ''}'.toLowerCase();
                  return q.isEmpty || hay.contains(q);
                }).toList();

                // ---- Client-side sort when filters are applied ----
                if (hasRole || hasStatus) {
                  docs.sort((a, b) {
                    final ma = a.data() as Map<String, dynamic>;
                    final mb = b.data() as Map<String, dynamic>;
                    final an = (ma['name'] ?? '').toString().toLowerCase();
                    final bn = (mb['name'] ?? '').toString().toLowerCase();
                    return an.compareTo(bn);
                  });
                }

                if (docs.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }

                // Collect UIDs for profile join
                final uids = docs
                    .map((d) => (d.data() as Map)['uid']?.toString())
                    .whereType<String>()
                    .toList();

                return FutureBuilder<Map<String, Map<String, dynamic>>>(
                  future: _loadProfilesByUid(uids),
                  builder: (context, profSnap) {
                    final profiles = profSnap.data ?? const {};

                    if (isSmall) {
                      // ---- MOBILE: card list ----
                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final d = docs[i];
                          final m = d.data() as Map<String, dynamic>;
                          final uid = (m['uid'] ?? '').toString();
                          final p = profiles[uid] ?? const {};
                          return _UserCard(
                            userId: d.id,
                            user: m,
                            profile: p,
                            onBlockToggle: () => _toggleBlock(d.id, m),
                            onDelete: () => _deleteUser(d.id),
                            onPaySalary: m['role'] == 'instructor' ? () => _paySalary(context, d.id, m) : null,
                            onViewProfile: () => _openProfile(context, m, p),
                          );
                        },
                      );
                    }

                    // ---- DESKTOP/TABLET: table ----
                    final rows = <List<Widget>>[];
                    for (final d in docs) {
                      final m = d.data() as Map<String, dynamic>;
                      final uid = (m['uid'] ?? '').toString();
                      final p = profiles[uid] ?? const {};
                      final status = (m['status'] ?? 'active').toString();

                      rows.add([
                        _userCellWithAvatar(m, p),
                        Text(m['email']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                        Text(m['phone']?.toString() ?? '-', overflow: TextOverflow.ellipsis),
                        RoleBadge(role: (m['role'] ?? '').toString()),
                        // Show pending/active/blocked properly
                        StatusBadge(
                          text: status[0].toUpperCase() + status.substring(1),
                          type: status == 'blocked'
                              ? 'rejected'
                              : status == 'pending'
                                  ? 'pending'
                                  : 'approved',
                        ),
                        Text((p['zipcode'] ?? '-').toString()),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            ElevatedButton(onPressed: () => _openProfile(context, m, p), child: const Text('View')),
                            if ((m['role'] ?? '') == 'instructor')
                              ElevatedButton(onPressed: () => _paySalary(context, d.id, m), child: const Text('Pay Salary')),
                            // Button shows Unblock only when currently blocked, else Block
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: status == 'blocked' ? Colors.green : Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _toggleBlock(d.id, m),
                              child: Text(status == 'blocked' ? 'Unblock' : 'Block'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: () => _deleteUser(d.id),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      ]);
                    }

                    return DataTableWrap(
                      columns: const ['User', 'Email', 'Phone', 'Role', 'Status', 'Zip', 'Actions'],
                      rows: rows,
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ------- Helpers -------

  // Batch-load user_profiles by uid (whereIn chunked by 10)
  Future<Map<String, Map<String, dynamic>>> _loadProfilesByUid(List<String> uids) async {
    if (uids.isEmpty) return {};
    final chunks = <List<String>>[];
    for (var i = 0; i < uids.length; i += 10) {
      chunks.add(uids.sublist(i, i + 10 > uids.length ? uids.length : i + 10));
    }
    final Map<String, Map<String, dynamic>> out = {};
    for (final c in chunks) {
      final snap = await FirebaseFirestore.instance
          .collection('user_profiles')
          .where('uid', whereIn: c)
          .get();
      for (final d in snap.docs) {
        final m = d.data();
        final uid = (m['uid'] ?? '').toString();
        if (uid.isNotEmpty) out[uid] = m;
      }
    }
    return out;
  }

  // Block/Unblock: pending->Block => blocked; blocked->Unblock => active
  Future<void> _toggleBlock(String userDocId, Map<String, dynamic> user) async {
    final current = (user['status'] ?? 'active').toString();
    final next = current == 'blocked' ? 'active' : 'blocked';
    await FirebaseFirestore.instance.collection('users').doc(userDocId).update({
      'status': next,
      'updated_at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _deleteUser(String userDocId) async {
    final ok = await confirmDialog(context: context, message: 'Delete user permanently?');
    if (ok) {
      await FirebaseFirestore.instance.collection('users').doc(userDocId).delete();
    }
  }

  Future<void> _paySalary(BuildContext context, String instructorId, Map<String, dynamic> instructor) async {
    final amtCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Pay Salary — ${(instructor['name'] ?? 'Instructor')}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            field('Amount (₹)', amtCtrl, number: true),
            const SizedBox(height: 8),
            area('Note (optional)', noteCtrl),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amtCtrl.text.trim()) ?? 0;
              await FirebaseFirestore.instance.collection('payouts').add({
                'instructor_id': instructorId,
                'instructor_name': instructor['name'],
                'amount': amount,
                'note': noteCtrl.text.trim(),
                'created_at': FieldValue.serverTimestamp(),
                'status': 'paid',
              });
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfile(BuildContext context, Map<String, dynamic> user, Map<String, dynamic> profile) async {
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(user['name']?.toString() ?? 'User Profile'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if ((profile['photo_url'] ?? '').toString().isNotEmpty)
                CircleAvatar(radius: 34, backgroundImage: NetworkImage(profile['photo_url'])),
              const SizedBox(height: 12),
              _profileRow('UID', user['uid']),
              _profileRow('Email', user['email']),
              _profileRow('Phone', user['phone']),
              _profileRow('Role', user['role']),
              _profileRow('Status', user['status']),
              const Divider(),
              _profileRow('DOB', profile['dob']),
              _profileRow('Address 1', profile['address_line1']),
              _profileRow('Address 2', profile['address_line2']),
              _profileRow('Zipcode', profile['zipcode']),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Widget _profileRow(String k, dynamic v) {
    final val = (v == null || (v is String && v.trim().isEmpty)) ? '-' : v.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(child: Text(val)),
        ],
      ),
    );
  }

  Widget _userCellWithAvatar(Map<String, dynamic> m, Map<String, dynamic> p) {
    final name = (m['name'] ?? '-').toString();
    final photo = (p['photo_url'] ?? '').toString();
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: const Color(0xFFE9ECEF),
          backgroundImage: photo.isNotEmpty ? NetworkImage(photo) : null,
          child: photo.isEmpty ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?') : null,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            if ((m['uid'] ?? '').toString().isNotEmpty)
              Text((m['uid'] as String), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ],
    );
  }
}

// ---- Mobile card for a user ----
class _UserCard extends StatelessWidget {
  final String userId;
  final Map<String, dynamic> user;
  final Map<String, dynamic> profile;
  final VoidCallback onBlockToggle;
  final VoidCallback onDelete;
  final VoidCallback? onPaySalary;
  final VoidCallback onViewProfile;

  const _UserCard({
    required this.userId,
    required this.user,
    required this.profile,
    required this.onBlockToggle,
    required this.onDelete,
    required this.onViewProfile,
    this.onPaySalary,
  });

  @override
  Widget build(BuildContext context) {
    final status = (user['status'] ?? 'active').toString();
    final isBlocked = status == 'blocked';
    final isInstructor = (user['role'] ?? '') == 'instructor';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFE9ECEF),
                backgroundImage: (profile['photo_url'] ?? '').toString().isNotEmpty
                    ? NetworkImage(profile['photo_url'])
                    : null,
                child: (profile['photo_url'] ?? '').toString().isEmpty
                    ? Text((user['name'] ?? 'U').toString().substring(0, 1).toUpperCase())
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((user['name'] ?? '-').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text((user['email'] ?? '-').toString(), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              RoleBadge(role: (user['role'] ?? '').toString()),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusBadge(
                text: status[0].toUpperCase() + status.substring(1),
                type: isBlocked ? 'rejected' : (status == 'pending' ? 'pending' : 'approved'),
              ),
              Text('Phone: ${user['phone'] ?? '-'}'),
              if ((profile['zipcode'] ?? '').toString().isNotEmpty) Text('Zip: ${profile['zipcode']}'),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton(onPressed: onViewProfile, child: const Text('View')),
              if (isInstructor && onPaySalary != null) ElevatedButton(onPressed: onPaySalary, child: const Text('Pay Salary')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: isBlocked ? Colors.green : Colors.orange, foregroundColor: Colors.white),
                onPressed: onBlockToggle,
                child: Text(isBlocked ? 'Unblock' : 'Block'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                onPressed: onDelete,
                child: const Text('Delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
