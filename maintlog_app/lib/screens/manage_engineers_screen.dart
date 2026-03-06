import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../services/sync_service.dart';

class ManageEngineersScreen extends StatefulWidget {
  const ManageEngineersScreen({super.key});

  @override
  State<ManageEngineersScreen> createState() => _ManageEngineersScreenState();
}

class _ManageEngineersScreenState extends State<ManageEngineersScreen> {
  List<Map<String, dynamic>> _engineers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await LocalDatabase.instance.getEngineers();
    if (mounted) {
      setState(() {
        _engineers = data;
        _isLoading = false;
      });
    }
  }

  void _showDialog({Map<String, dynamic>? existing}) {
    final nameController = TextEditingController(
      text: existing?['full_name'] ?? '',
    );
    String role = existing?['role'] ?? 'Junior';
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Engineer' : 'Add Engineer'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    initialValue: role,
                    items: ['Lead', 'Senior', 'Junior']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) setDialogState(() => role = val);
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
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    if (isEdit) {
                      await LocalDatabase.instance.updateEngineer(
                        existing['id'],
                        name,
                        role,
                      );
                    } else {
                      await LocalDatabase.instance.insertEngineer({
                        'id':
                            'eng_${DateTime.now().millisecondsSinceEpoch}',
                        'full_name': name,
                        'role': role,
                      });
                    }
                    if (ctx.mounted) Navigator.pop(ctx);
                    await SyncService().syncAll();
                    _load();
                  },
                  child: Text(isEdit ? 'Save' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _roleColor(String? role) {
    switch (role) {
      case 'Lead':
        return Colors.amber;
      case 'Senior':
        return Colors.blueAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Engineers')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _engineers.isEmpty
          ? const Center(child: Text('No engineers. Tap + to add.'))
          : ListView.builder(
              itemCount: _engineers.length,
              itemBuilder: (context, index) {
                final e = _engineers[index];
                return ListTile(
                  leading: const Icon(Icons.engineering),
                  title: Text(e['full_name'] ?? ''),
                  subtitle: Text(e['role'] ?? 'Unknown'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Chip(
                        label: Text(
                          e['role'] ?? '',
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: _roleColor(
                          e['role'],
                        ).withValues(alpha: 0.2),
                        side: BorderSide(color: _roleColor(e['role'])),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showDialog(existing: e),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        onPressed: () async {
                          bool? confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Engineer'),
                              content: Text(
                                'Are you sure you want to delete ${e['full_name']}?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            try {
                              await Supabase.instance.client
                                  .from('engineers')
                                  .delete()
                                  .eq('id', e['id']);
                            } catch (_) {}
                            await LocalDatabase.instance.deleteEngineer(
                              e['id'],
                            );
                            await SyncService().syncAll();
                            _load();
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
