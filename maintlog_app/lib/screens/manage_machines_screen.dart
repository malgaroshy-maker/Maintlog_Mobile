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
  List<Map<String, dynamic>> _lines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _getLineName(String? lineId) {
    if (lineId == null) return 'Unassigned';
    final line = _lines.where((l) => l['id'] == lineId).firstOrNull;
    return line?['name']?.toString() ?? 'Unknown Line';
  }

  Future<void> _load() async {
    final machinesData = await LocalDatabase.instance.getMachines();
    final linesData = await LocalDatabase.instance.getLines();
    if (mounted)
      setState(() {
        _machines = machinesData;
        _lines = linesData;
        _isLoading = false;
      });
  }

  void _showDialog({Map<String, dynamic>? existing}) {
    final controller = TextEditingController(text: existing?['name'] ?? '');
    final isEdit = existing != null;
    String? selectedEditLineId = existing?['line_id']?.toString();
    List<String> selectedNewLines = [];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'Edit Machine' : 'Add Machine'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        labelText: 'Machine Name',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    if (_lines.isEmpty)
                      const Text(
                        'No lines available. Please create production lines first.',
                        style: TextStyle(color: Colors.red),
                      )
                    else if (isEdit)
                      DropdownButtonFormField<String>(
                        value: selectedEditLineId,
                        decoration: const InputDecoration(
                          labelText: 'Assigned Line',
                          border: OutlineInputBorder(),
                        ),
                        items: _lines.map((l) {
                          return DropdownMenuItem<String>(
                            value: l['id'].toString(),
                            child: Text(l['name'].toString()),
                          );
                        }).toList(),
                        onChanged: (val) {
                          setDialogState(() => selectedEditLineId = val);
                        },
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Assign to Lines:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          ..._lines.map((l) {
                            final lineId = l['id'].toString();
                            return CheckboxListTile(
                              title: Text(l['name'].toString()),
                              value: selectedNewLines.contains(lineId),
                              onChanged: (bool? checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    selectedNewLines.add(lineId);
                                  } else {
                                    selectedNewLines.remove(lineId);
                                  }
                                });
                              },
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                            );
                          }),
                        ],
                      ),
                  ],
                ),
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
                    if (!isEdit && selectedNewLines.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select at least one line.'),
                        ),
                      );
                      return;
                    }

                    if (isEdit) {
                      await LocalDatabase.instance.updateMachine(
                        existing['id'],
                        name,
                        selectedEditLineId,
                      );
                    } else {
                      for (final lineId in selectedNewLines) {
                        await LocalDatabase.instance.insertMachine({
                          'id':
                              'm_' +
                              DateTime.now().millisecondsSinceEpoch.toString() +
                              '_' +
                              lineId,
                          'name': name,
                          'line_id': lineId,
                        });
                        await Future.delayed(const Duration(milliseconds: 5));
                      }
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
                  title: Text('${m['name']} (${_getLineName(m['line_id'])})'),
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
