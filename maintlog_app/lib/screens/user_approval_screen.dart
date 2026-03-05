import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserApprovalScreen extends StatefulWidget {
  const UserApprovalScreen({super.key});

  @override
  State<UserApprovalScreen> createState() => _UserApprovalScreenState();
}

class _UserApprovalScreenState extends State<UserApprovalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pendingUsers = [];
  List<Map<String, dynamic>> _approvedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUsers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final supabase = Supabase.instance.client;
      final pending = await supabase
          .from('engineers')
          .select()
          .eq('is_approved', false)
          .order('created_at', ascending: false);
      final approved = await supabase
          .from('engineers')
          .select()
          .eq('is_approved', true)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _pendingUsers = List<Map<String, dynamic>>.from(pending);
          _approvedUsers = List<Map<String, dynamic>>.from(approved);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading users: ' + e.toString())),
        );
      }
    }
  }

  Future<void> _approveUser(String id) async {
    try {
      await Supabase.instance.client
          .from('engineers')
          .update({'is_approved': true, 'is_active': true})
          .eq('id', id);
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User approved!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
      }
    }
  }

  Future<void> _rejectUser(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject User?'),
        content: const Text(
          'This will deactivate the user account. They will not be able to log in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .from('engineers')
          .update({'is_approved': false, 'is_active': false})
          .eq('id', id);
      _loadUsers();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User rejected.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
      }
    }
  }

  Future<void> _changeRole(String id, String currentRole) async {
    final newRole = currentRole == 'admin' ? 'engineer' : 'admin';
    try {
      await Supabase.instance.client
          .from('engineers')
          .update({'role': newRole})
          .eq('id', id);
      _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ' + e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Approval'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Badge(
                isLabelVisible: _pendingUsers.isNotEmpty,
                label: Text(_pendingUsers.length.toString()),
                child: const Icon(Icons.pending_actions),
              ),
              text: 'Pending',
            ),
            const Tab(icon: Icon(Icons.verified_user), text: 'Approved'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(_pendingUsers, isPending: true),
                _buildUserList(_approvedUsers, isPending: false),
              ],
            ),
    );
  }

  Widget _buildUserList(
    List<Map<String, dynamic>> users, {
    required bool isPending,
  }) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isPending ? Icons.check_circle_outline : Icons.people,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              isPending ? 'No pending approvals' : 'No approved users',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUsers,
      child: ListView.builder(
        itemCount: users.length,
        itemBuilder: (context, index) {
          final user = users[index];
          final role = user['role'] ?? 'engineer';
          final isAdmin = role == 'admin';
          final createdAt = user['created_at'] ?? '';
          final dateStr = createdAt.length > 10
              ? createdAt.substring(0, 10)
              : createdAt;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isAdmin
                    ? Colors.amber.withValues(alpha: 0.2)
                    : Theme.of(context).colorScheme.primaryContainer,
                child: Icon(
                  isAdmin ? Icons.admin_panel_settings : Icons.person,
                  color: isAdmin
                      ? Colors.amber
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
              title: Text(user['name'] ?? 'Unknown'),
              subtitle: Text('Role: ' + role + ' | Joined: ' + dateStr),
              trailing: isPending
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 28,
                          ),
                          tooltip: 'Approve',
                          onPressed: () => _approveUser(user['id']),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.cancel,
                            color: Colors.red,
                            size: 28,
                          ),
                          tooltip: 'Reject',
                          onPressed: () => _rejectUser(user['id']),
                        ),
                      ],
                    )
                  : PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'role') {
                          _changeRole(user['id'], role);
                        } else if (value == 'deactivate') {
                          _rejectUser(user['id']);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'role',
                          child: Text(
                            isAdmin ? 'Demote to Engineer' : 'Promote to Admin',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'deactivate',
                          child: Text(
                            'Deactivate',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}
