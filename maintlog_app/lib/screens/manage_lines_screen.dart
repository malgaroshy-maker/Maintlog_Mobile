import 'package:flutter/material.dart';
import '../database/local_database.dart';

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
    if (mounted)
      setState(() {
        _lines = data;
        _isLoading = false;
      });
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
                  'id': 'l_' + DateTime.now().millisecondsSinceEpoch.toString(),
                  'name': name,
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
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
                          await LocalDatabase.instance.deleteLine(l['id']);
                          _load();
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
