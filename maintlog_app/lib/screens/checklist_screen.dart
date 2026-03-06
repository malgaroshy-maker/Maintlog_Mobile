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

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _loadEngineers();
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
      appBar: AppBar(title: const Text('Section Checklist')),
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

                return Dismissible(
                  key: Key(task['id']),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.red,
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) async {
                    await LocalDatabase.instance.deleteTask(task['id']);
                    _loadTasks();
                    SyncService().syncAll();
                  },
                  child: Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: Checkbox(
                        value: isDone,
                        onChanged: (val) async {
                          final newStatus = val == true ? 'done' : 'pending';
                          String? completedBy;
                          String? completedAt;

                          if (newStatus == 'done') {
                            final user =
                                Supabase.instance.client.auth.currentUser;
                            completedBy =
                                user?.email ??
                                user?.userMetadata?['full_name'] ??
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
                          decoration: isDone
                              ? TextDecoration.lineThrough
                              : null,
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
                                'Assigned to: ' +
                                    task['assigned_to'].toString(),
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
                      trailing: Chip(
                        label: Text(
                          task['priority'] ?? 'Medium',
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: pColor.withValues(alpha: 0.2),
                        side: BorderSide(color: pColor),
                      ),
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
