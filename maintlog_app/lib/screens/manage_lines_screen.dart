import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/local_database.dart';
import '../services/sync_service.dart';

class ManageLinesScreen extends StatefulWidget {
  const ManageLinesScreen({super.key});

  @override
  State<ManageLinesScreen> createState() => _ManageLinesScreenState();
}

class _ManageLinesScreenState extends State<ManageLinesScreen> {
  List<Map<String, dynamic>> _lines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await LocalDatabase.instance.getLines();
    if (mounted) {
      setState(() {
        _lines = data;
        _isLoading = false;
      });
    }
  }

  void _showDialog({Map<String, dynamic>? existing}) {
    final controller = TextEditingController(text: existing?['name'] ?? '');
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Line' : 'Add Line'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Line Name',
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
                await LocalDatabase.instance.updateLine(existing['id'], name);
              } else {
                await LocalDatabase.instance.insertLine({
                  'id': 'l_${DateTime.now().millisecondsSinceEpoch}',
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
      appBar: AppBar(title: const Text('Manage Production Lines')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _lines.isEmpty
          ? const Center(child: Text('No lines. Tap + to add.'))
          : ListView.builder(
              itemCount: _lines.length,
              itemBuilder: (context, index) {
                final l = _lines[index];
                return ListTile(
                  leading: const Icon(Icons.linear_scale),
                  title: Text(l['name'] ?? ''),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showDialog(existing: l),
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
                              title: const Text('Delete Line'),
                              content: Text(
                                'Are you sure you want to delete ${l['name']}?',
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
                                  .from('line_numbers')
                                  .delete()
                                  .eq('id', l['id']);
                            } catch (_) {}
                            await LocalDatabase.instance.deleteLine(l['id']);
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
