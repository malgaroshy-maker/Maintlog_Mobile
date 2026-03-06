import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../services/sync_service.dart';

class ManageMachinesScreen extends StatefulWidget {
  const ManageMachinesScreen({super.key});

  @override
  State<ManageMachinesScreen> createState() => _ManageMachinesScreenState();
}

class _ManageMachinesScreenState extends State<ManageMachinesScreen> {
  List<Map<String, dynamic>> _machines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await LocalDatabase.instance.getMachines();
    if (mounted)
      setState(() {
        _machines = data;
        _isLoading = false;
      });
  }

  void _showDialog({Map<String, dynamic>? existing}) {
    final controller = TextEditingController(text: existing?['name'] ?? '');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Machine' : 'Add Machine'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Machine Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              if (isEdit) {
                await LocalDatabase.instance.updateMachine(
                  existing['id'],
                  name,
                );
              } else {
                await LocalDatabase.instance.insertMachine({
                  'id': 'm_' + DateTime.now().millisecondsSinceEpoch.toString(),
                  'name': name,
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await SyncService().syncAll();
              _load();
            },
            child: Text(isEdit ? 'Save' : 'Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Machines')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _machines.isEmpty
          ? const Center(child: Text('No machines. Tap + to add.'))
          : ListView.builder(
              itemCount: _machines.length,
              itemBuilder: (context, index) {
                final m = _machines[index];
                return ListTile(
                  leading: const Icon(Icons.precision_manufacturing),
                  title: Text(m['name'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showDialog(existing: m),
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
                              title: const Text('Delete Machine'),
                              content: Text(
                                'Are you sure you want to delete ${m['name']}?',
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
                                  .from('machines')
                                  .delete()
                                  .eq('id', m['id']);
                            } catch (_) {}
                            await LocalDatabase.instance.deleteMachine(m['id']);
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
