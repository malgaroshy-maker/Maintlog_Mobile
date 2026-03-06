import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../services/sync_service.dart';

class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  List<Map<String, dynamic>> _tasks = [];
  List<Map<String, dynamic>> _engineers = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  StreamSubscription? _syncSubscription;

  /// Returns a set of identifiers for the current user (email + full_name)
  Set<String> _getCurrentUserIdentifiers() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return {};
    final ids = <String>{};
    if (user.email != null) ids.add(user.email!);
    final fullName = user.userMetadata?['full_name'];
    if (fullName != null) ids.add(fullName.toString());
    return ids;
  }

  bool _isCreator(Map<String, dynamic> task) {
    final userIds = _getCurrentUserIdentifiers();
    final createdBy = (task['created_by'] ?? '').toString();
    return userIds.contains(createdBy);
  }

  Future<void> _manualSync() async {
    setState(() => _isSyncing = true);
    await SyncService().syncAll();
    await _loadTasks();
    if (mounted) setState(() => _isSyncing = false);
  }

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _loadEngineers();
    // Listen for realtime sync events so tasks update immediately
    _syncSubscription = SyncService().onSyncEvent.listen((_) {
      _loadTasks();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadEngineers() async {
    final data = await LocalDatabase.instance.getEngineers();
    if (mounted) setState(() => _engineers = data);
  }

  Future<void> _loadTasks() async {
    final tasks = await LocalDatabase.instance.getTasks();
    if (mounted)
      setState(() {
        _tasks = tasks;
        _isLoading = false;
      });
  }

  void _showAddTaskDialog() {
    final descController = TextEditingController();
    String priority = 'Medium';
    String? assignedTo;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Add Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Task Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: priority,
                    items: ['Low', 'Medium', 'High']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => priority = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Assign To (optional)',
                      border: OutlineInputBorder(),
                    ),
                    value: assignedTo,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Unassigned'),
                      ),
                      ..._engineers.map(
                        (e) => DropdownMenuItem<String>(
                          value: e['full_name'] as String,
                          child: Text(e['full_name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => assignedTo = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (descController.text.trim().isEmpty) return;
                    final user = Supabase.instance.client.auth.currentUser;
                    final creatorName =
                        user?.userMetadata?['full_name'] ??
                        user?.email ??
                        'Unknown';
                    final task = {
                      'id':
                          'task_' +
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      'description': descController.text.trim(),
                      'priority': priority,
                      'created_by': creatorName,
                      'status': 'pending',
                      'created_at': DateTime.now().toIso8601String(),
                      'assigned_to': assignedTo,
                    };
                    await LocalDatabase.instance.insertTask(task);
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadTasks();
                    SyncService().syncAll();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editTaskDialog(Map<String, dynamic> task) {
    final descController = TextEditingController(
      text: task['description'] ?? '',
    );
    String priority = task['priority'] ?? 'Medium';
    String? assignedTo = (task['assigned_to'] ?? '').toString().isEmpty
        ? null
        : task['assigned_to'].toString();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Task'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Task Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Priority',
                      border: OutlineInputBorder(),
                    ),
                    value: priority,
                    items: ['Low', 'Medium', 'High']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => priority = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Assign To (optional)',
                      border: OutlineInputBorder(),
                    ),
                    value: assignedTo,
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Unassigned'),
                      ),
                      ..._engineers.map(
                        (e) => DropdownMenuItem<String>(
                          value: e['full_name'] as String,
                          child: Text(e['full_name'] as String),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => assignedTo = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (descController.text.trim().isEmpty) return;
                    final db = await LocalDatabase.instance.database;
                    await db.update(
                      'todo_tasks',
                      {
                        'description': descController.text.trim(),
                        'priority': priority,
                        'assigned_to': assignedTo,
                      },
                      where: 'id = ?',
                      whereArgs: [task['id']],
                    );
                    if (ctx.mounted) Navigator.pop(ctx);
                    _loadTasks();
                    SyncService().syncAll();
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _deleteTask(Map<String, dynamic> task) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task?'),
        content: const Text('This will permanently remove this task.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await LocalDatabase.instance.deleteTask(task['id']);
      _loadTasks();
      SyncService().syncAll();
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.redAccent;
      case 'Medium':
        return Colors.orangeAccent;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Section Checklist'),
        actions: [
          IconButton(
            icon: _isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sync Now',
            onPressed: _isSyncing ? null : _manualSync,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tasks.isEmpty
          ? const Center(child: Text('No tasks yet. Tap + to add one!'))
          : ListView.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                final isDone = task['status'] == 'done';
                final pColor = _priorityColor(task['priority'] ?? 'Medium');

                final isCreator = _isCreator(task);

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: Checkbox(
                      value: isDone,
                      onChanged: (val) async {
                        final userIds = _getCurrentUserIdentifiers();
                        final newStatus = val == true ? 'done' : 'pending';

                        // --- Permission: checking (completing) ---
                        if (newStatus == 'done') {
                          final assignedTo = (task['assigned_to'] ?? '')
                              .toString();
                          if (assignedTo.isNotEmpty &&
                              !userIds.contains(assignedTo)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Only $assignedTo can complete this task.',
                                ),
                              ),
                            );
                            return;
                          }
                        }

                        // --- Permission: unchecking ---
                        if (newStatus == 'pending' && isDone) {
                          final completedBy = (task['completed_by'] ?? '')
                              .toString();
                          final createdBy = (task['created_by'] ?? '')
                              .toString();
                          final canUncheck =
                              userIds.contains(completedBy) ||
                              userIds.contains(createdBy);
                          if (!canUncheck) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Only the person who completed or created this task can uncheck it.',
                                ),
                              ),
                            );
                            return;
                          }
                        }

                        String? completedBy;
                        String? completedAt;
                        if (newStatus == 'done') {
                          final user =
                              Supabase.instance.client.auth.currentUser;
                          completedBy =
                              user?.userMetadata?['full_name'] ??
                              user?.email ??
                              'Unknown User';
                          completedAt = DateTime.now().toIso8601String();
                        }

                        await LocalDatabase.instance.updateTaskStatus(
                          task['id'],
                          newStatus,
                          completedBy: completedBy,
                          completedAt: completedAt,
                        );
                        _loadTasks();
                        SyncService().syncAll();
                      },
                    ),
                    title: Text(
                      task['description'] ?? '',
                      style: TextStyle(
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? Colors.grey : null,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Created by: ' + (task['created_by'] ?? 'Unknown'),
                        ),
                        if (task['assigned_to'] != null &&
                            task['assigned_to'].toString().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              'Assigned to: ' + task['assigned_to'].toString(),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        if (isDone && task['completed_by'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              'Completed by: ' +
                                  task['completed_by'].toString(),
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(
                            task['priority'] ?? 'Medium',
                            style: const TextStyle(fontSize: 11),
                          ),
                          backgroundColor: pColor.withValues(alpha: 0.2),
                          side: BorderSide(color: pColor),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                        ),
                        if (isCreator) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            tooltip: 'Edit',
                            onPressed: () => _editTaskDialog(task),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            tooltip: 'Delete',
                            onPressed: () => _deleteTask(task),
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskDialog,
        child: const Icon(Icons.add_task),
      ),
    );
  }
}
