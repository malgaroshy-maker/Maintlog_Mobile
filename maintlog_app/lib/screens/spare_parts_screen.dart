import 'package:flutter/material.dart';
import '../database/local_database.dart';

class SparePartsScreen extends StatefulWidget {
  const SparePartsScreen({super.key});

  @override
  State<SparePartsScreen> createState() => _SparePartsScreenState();
}

class _SparePartsScreenState extends State<SparePartsScreen> {
  List<Map<String, dynamic>> _parts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  Future<void> _loadParts() async {
    setState(() => _isLoading = true);
    final parts = await LocalDatabase.instance.getSpareParts();
    setState(() {
      _parts = parts;
      _isLoading = false;
    });
  }

  void _showPartDialog({Map<String, dynamic>? existing}) {
    final nameController = TextEditingController(text: existing?['name'] ?? '');
    final partNumController = TextEditingController(
      text: existing?['part_number'] ?? '',
    );
    final stockController = TextEditingController(
      text: (existing?['stock'] ?? 0).toString(),
    );
    final isEdit = existing != null;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Spare Part' : 'Add Spare Part'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Part Name',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: partNumController,
                decoration: const InputDecoration(
                  labelText: 'Part Number',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: stockController,
                decoration: const InputDecoration(
                  labelText: 'Stock Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
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
              final name = nameController.text.trim();
              final partNum = partNumController.text.trim();
              final stock = int.tryParse(stockController.text.trim()) ?? 0;
              if (name.isEmpty || partNum.isEmpty) return;

              if (isEdit) {
                await LocalDatabase.instance.updateSparePart(
                  existing['id'],
                  name,
                  partNum,
                  stock,
                );
              } else {
                await LocalDatabase.instance.insertSparePart({
                  'id':
                      'sp_' + DateTime.now().millisecondsSinceEpoch.toString(),
                  'name': name,
                  'part_number': partNum,
                  'stock': stock,
                });
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _loadParts();
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
      appBar: AppBar(title: const Text('Spare Parts Inventory')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _parts.isEmpty
          ? const Center(child: Text('No spare parts. Tap + to add.'))
          : ListView.separated(
              itemCount: _parts.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final part = _parts[index];
                final int stock = part['stock'] ?? 0;
                final bool isLowStock = stock < 5 && stock > 0;
                final bool isOutOfStock = stock == 0;

                return ListTile(
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          part['name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isLowStock || isOutOfStock) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isOutOfStock
                                ? Colors.red.withOpacity(0.2)
                                : Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isOutOfStock ? 'OUT OF STOCK' : 'LOW STOCK',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isOutOfStock ? Colors.red : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text('Part #: ' + (part['part_number'] ?? '')),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Stock: ' + stock.toString(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isOutOfStock
                                  ? Colors.red
                                  : (isLowStock ? Colors.orange : null),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _showPartDialog(existing: part),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        onPressed: () async {
                          await LocalDatabase.instance.deleteSparePart(
                            part['id'],
                          );
                          _loadParts();
                        },
                      ),
                    ],
                  ),
                  onTap: () => _showPartDialog(existing: part),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showPartDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
