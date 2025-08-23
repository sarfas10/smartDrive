import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';

class UsersBlock extends StatefulWidget {
  const UsersBlock({super.key});
  
  @override
  State<UsersBlock> createState() => _UsersBlockState();
}

class _UsersBlockState extends State<UsersBlock> {
  String _roleFilter = 'all';
  String _statusFilter = 'all';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildFiltersSection(),
        const Divider(height: 1),
        Expanded(child: _buildUsersList()),
      ],
    );
  }

  Widget _buildFiltersSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search users...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),
          
          // Filters Row
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              // Role Filters
              _buildFilterChip('All', _roleFilter == 'all', () => _setRoleFilter('all')),
              _buildFilterChip('Students', _roleFilter == 'student', () => _setRoleFilter('student')),
              _buildFilterChip('Instructors', _roleFilter == 'instructor', () => _setRoleFilter('instructor')),
              
              const SizedBox(width: 8),
              
              // Status Filter Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _statusFilter,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Status')),
                      DropdownMenuItem(value: 'pending', child: Text('Pending')),
                      DropdownMenuItem(value: 'active', child: Text('Active')),
                      DropdownMenuItem(value: 'blocked', child: Text('Blocked')),
                    ],
                    onChanged: (value) => _setStatusFilter(value ?? 'all'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onTap) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
      checkmarkColor: Theme.of(context).primaryColor,
    );
  }

  Widget _buildUsersList() {
    final query = _buildFirestoreQuery();
    
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorWidget(snapshot.error.toString());
        }
        
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final filteredUsers = _filterUsers(snapshot.data!.docs);
        
        if (filteredUsers.isEmpty) {
          return _buildEmptyWidget();
        }

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _loadUserProfiles(filteredUsers),
          builder: (context, profileSnapshot) {
            final profiles = profileSnapshot.data ?? {};
            
            return LayoutBuilder(
              builder: (context, constraints) {
                final isSmallScreen = constraints.maxWidth < 700;
                
                return isSmallScreen 
                  ? _buildMobileView(filteredUsers, profiles)
                  : _buildDesktopView(filteredUsers, profiles);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildMobileView(List<QueryDocumentSnapshot> users, Map<String, Map<String, dynamic>> profiles) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, index) => _UserCard(
        user: users[index],
        profile: profiles[(users[index].data() as Map)['uid']] ?? {},
        onAction: (action) => _handleUserAction(action, users[index]),
      ),
    );
  }

  Widget _buildDesktopView(List<QueryDocumentSnapshot> users, Map<String, Map<String, dynamic>> profiles) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('User')),
          DataColumn(label: Text('Contact')),
          DataColumn(label: Text('Role')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Actions')),
        ],
        rows: users.map((doc) {
          final userData = doc.data() as Map<String, dynamic>;
          final profile = profiles[userData['uid']] ?? {};
          
          return DataRow(cells: [
            DataCell(_buildUserCell(userData, profile)),
            DataCell(_buildContactCell(userData)),
            DataCell(RoleBadge(role: userData['role'] ?? '')),
            DataCell(_buildStatusBadge(userData['status'] ?? 'active')),
            DataCell(Text(profile['zipcode']?.toString() ?? '-')),
            DataCell(_buildActionButtons(doc)),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildUserCell(Map<String, dynamic> userData, Map<String, dynamic> profile) {
    final name = userData['name']?.toString() ?? 'Unknown';
    final photoUrl = profile['photo_url']?.toString() ?? '';
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 16,
          backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: photoUrl.isEmpty ? Text(name.substring(0, 1).toUpperCase()) : null,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (userData['uid']?.toString().isNotEmpty ?? false)
                Text(
                  userData['uid'].toString(),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactCell(Map<String, dynamic> userData) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(userData['email']?.toString() ?? '-', 
             style: const TextStyle(fontSize: 12)),
        Text(userData['phone']?.toString() ?? '-', 
             style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    String displayText = status.substring(0, 1).toUpperCase() + status.substring(1);
    
    switch (status.toLowerCase()) {
      case 'active':
        color = Colors.green;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      case 'blocked':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        displayText,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildActionButtons(QueryDocumentSnapshot doc) {
    final userData = doc.data() as Map<String, dynamic>;
    final status = userData['status']?.toString() ?? 'active';
    final isInstructor = userData['role'] == 'instructor';
    
    return Wrap(
      spacing: 4,
      children: [
        _buildActionButton('View', Icons.visibility, 
                          () => _handleUserAction('view', doc)),
        if (isInstructor)
          _buildActionButton('Pay', Icons.payment, 
                            () => _handleUserAction('pay', doc)),
        _buildActionButton(
          status == 'blocked' ? 'Unblock' : 'Block',
          status == 'blocked' ? Icons.lock_open : Icons.lock,
          () => _handleUserAction('toggle_block', doc),
          color: status == 'blocked' ? Colors.green : Colors.orange,
        ),
        _buildActionButton('Delete', Icons.delete, 
                          () => _handleUserAction('delete', doc), 
                          color: Colors.red),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, VoidCallback onPressed, {Color? color}) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color != null ? Colors.white : null,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error loading users', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(error, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No users found', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('Try adjusting your search or filters'),
        ],
      ),
    );
  }

  // Helper Methods
  Query _buildFirestoreQuery() {
    Query query = FirebaseFirestore.instance.collection('users');
    
    if (_roleFilter != 'all') {
      query = query.where('role', isEqualTo: _roleFilter);
    }
    
    if (_statusFilter != 'all') {
      query = query.where('status', isEqualTo: _statusFilter);
    }
    
    // Only add orderBy when no filters to avoid composite index issues
    if (_roleFilter == 'all' && _statusFilter == 'all') {
      query = query.orderBy('name');
    }
    
    return query;
  }

  List<QueryDocumentSnapshot> _filterUsers(List<QueryDocumentSnapshot> docs) {
    final searchQuery = _searchController.text.trim().toLowerCase();
    
    var filtered = docs.where((doc) {
      if (searchQuery.isEmpty) return true;
      
      final data = doc.data() as Map<String, dynamic>;
      final searchableText = [
        data['name'],
        data['email'], 
        data['phone']
      ].where((field) => field != null).join(' ').toLowerCase();
      
      return searchableText.contains(searchQuery);
    }).toList();

    // Sort client-side when filters are applied
    if (_roleFilter != 'all' || _statusFilter != 'all') {
      filtered.sort((a, b) {
        final aData = a.data() as Map<String, dynamic>;
        final bData = b.data() as Map<String, dynamic>;
        final aName = aData['name']?.toString().toLowerCase() ?? '';
        final bName = bData['name']?.toString().toLowerCase() ?? '';
        return aName.compareTo(bName);
      });
    }

    return filtered;
  }

  Future<Map<String, Map<String, dynamic>>> _loadUserProfiles(List<QueryDocumentSnapshot> users) async {
    final uids = users
        .map((doc) => (doc.data() as Map)['uid']?.toString())
        .where((uid) => uid != null && uid.isNotEmpty)
        .cast<String>()
        .toList();

    if (uids.isEmpty) return {};

    final Map<String, Map<String, dynamic>> profiles = {};
    
    // Process in chunks of 10 (Firestore whereIn limit)
    for (int i = 0; i < uids.length; i += 10) {
      final chunk = uids.sublist(i, (i + 10).clamp(0, uids.length));
      
      final snapshot = await FirebaseFirestore.instance
          .collection('user_profiles')
          .where('uid', whereIn: chunk)
          .get();
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid']?.toString();
        if (uid != null && uid.isNotEmpty) {
          profiles[uid] = data;
        }
      }
    }
    
    return profiles;
  }

  void _setRoleFilter(String role) {
    setState(() => _roleFilter = role);
  }

  void _setStatusFilter(String status) {
    setState(() => _statusFilter = status);
  }

  Future<void> _handleUserAction(String action, QueryDocumentSnapshot doc) async {
    final userData = doc.data() as Map<String, dynamic>;
    
    switch (action) {
      case 'view':
        await _showUserProfile(userData);
        break;
      case 'pay':
        await _showPaySalaryDialog(doc.id, userData);
        break;
      case 'toggle_block':
        await _toggleUserStatus(doc.id, userData);
        break;
      case 'delete':
        await _deleteUser(doc.id);
        break;
    }
  }

  Future<void> _showUserProfile(Map<String, dynamic> userData) async {
    // Load user profile
    final uid = userData['uid']?.toString();
    Map<String, dynamic> profile = {};
    
    if (uid != null && uid.isNotEmpty) {
      final profileDoc = await FirebaseFirestore.instance
          .collection('user_profiles')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();
      
      if (profileDoc.docs.isNotEmpty) {
        profile = profileDoc.docs.first.data();
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(userData['name']?.toString() ?? 'User Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile['photo_url']?.toString().isNotEmpty ?? false)
                CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage(profile['photo_url']),
                ),
              const SizedBox(height: 16),
              _buildProfileField('Name', userData['name']),
              _buildProfileField('Email', userData['email']),
              _buildProfileField('Phone', userData['phone']),
              _buildProfileField('Role', userData['role']),
              _buildProfileField('Status', userData['status']),
              const Divider(),
              _buildProfileField('Date of Birth', profile['dob']),
              _buildProfileField('Address', profile['address_line1']),
              _buildProfileField('Address 2', profile['address_line2']),
              _buildProfileField('Zipcode', profile['zipcode']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileField(String label, dynamic value) {
    final displayValue = value?.toString().isNotEmpty == true ? value.toString() : '-';
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(displayValue)),
        ],
      ),
    );
  }

  Future<void> _showPaySalaryDialog(String instructorId, Map<String, dynamic> instructor) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay Salary - ${instructor['name'] ?? 'Instructor'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountController.text.trim()) ?? 0;
              
              if (amount <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid amount')),
                );
                return;
              }

              await FirebaseFirestore.instance.collection('payouts').add({
                'instructor_id': instructorId,
                'instructor_name': instructor['name'],
                'amount': amount,
                'note': noteController.text.trim(),
                'created_at': FieldValue.serverTimestamp(),
                'status': 'paid',
              });

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Salary payment recorded successfully')),
                );
              }
            },
            child: const Text('Pay'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleUserStatus(String userId, Map<String, dynamic> userData) async {
    final currentStatus = userData['status']?.toString() ?? 'active';
    final newStatus = currentStatus == 'blocked' ? 'active' : 'blocked';
    
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'status': newStatus,
        'updated_at': FieldValue.serverTimestamp(),
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User ${newStatus == 'blocked' ? 'blocked' : 'unblocked'} successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating user status: $e')),
        );
      }
    }
  }

  Future<void> _deleteUser(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: const Text('Are you sure you want to permanently delete this user? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(userId).delete();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting user: $e')),
          );
        }
      }
    }
  }
}

// Simplified User Card for Mobile View
class _UserCard extends StatelessWidget {
  final QueryDocumentSnapshot user;
  final Map<String, dynamic> profile;
  final Function(String) onAction;

  const _UserCard({
    required this.user,
    required this.profile,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final userData = user.data() as Map<String, dynamic>;
    final status = userData['status']?.toString() ?? 'active';
    final isInstructor = userData['role'] == 'instructor';
    final photoUrl = profile['photo_url']?.toString() ?? '';
    final name = userData['name']?.toString() ?? 'Unknown';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                  child: photoUrl.isEmpty ? Text(name.substring(0, 1).toUpperCase()) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        userData['email']?.toString() ?? '-',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                      if (userData['phone']?.toString().isNotEmpty ?? false)
                        Text(
                          userData['phone'].toString(),
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RoleBadge(role: userData['role'] ?? ''),
                    const SizedBox(height: 4),
                    _buildStatusBadge(status),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionButton('View', () => onAction('view')),
                if (isInstructor)
                  _buildActionButton('Pay Salary', () => onAction('pay')),
                _buildActionButton(
                  status == 'blocked' ? 'Unblock' : 'Block',
                  () => onAction('toggle_block'),
                  color: status == 'blocked' ? Colors.green : Colors.orange,
                ),
                _buildActionButton(
                  'Delete',
                  () => onAction('delete'),
                  color: Colors.red,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'active':
        color = Colors.green;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      case 'blocked':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status.substring(0, 1).toUpperCase() + status.substring(1),
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildActionButton(String label, VoidCallback onPressed, {Color? color}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color != null ? Colors.white : null,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}