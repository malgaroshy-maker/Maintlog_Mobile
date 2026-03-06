import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/log_entry.dart';
import '../database/local_database.dart';

class NewLogEntryDialog extends StatefulWidget {
  final String activeShift;
  final String activeCrew;
  final LogEntry? initialEntry;
  final bool isDuplicate;
  const NewLogEntryDialog({
    super.key,
    required this.activeShift,
    required this.activeCrew,
    this.initialEntry,
    this.isDuplicate = false,
  });

  @override
  State<NewLogEntryDialog> createState() => _NewLogEntryDialogState();
}

class _SelectedPart {
  String? partId;
  Map<String, dynamic>? partData;
  final TextEditingController qtyController = TextEditingController(text: '1');
}

class _NewLogEntryDialogState extends State<NewLogEntryDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedMachine;
  List<String> _machines = [];

  final List<String> _availableLines = ['Line 1', 'Line 2', 'Line 3', 'Line 4'];
  final List<String> _selectedLines = [];

  List<String> _availableEngineers = [];
  final List<String> _selectedEngineers = [];

  final TextEditingController _workDescController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  final List<TextEditingController> _timeControllers = [
    TextEditingController(),
  ];
  final List<_SelectedPart> _selectedParts = [_SelectedPart()];

  List<Map<String, dynamic>> _availableParts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.initialEntry != null) {
      _selectedMachine = widget.initialEntry!.machineId;
      if (widget.initialEntry!.lineId != null) {
        _selectedLines.addAll(
          widget.initialEntry!.lineId!.split(', ').where((s) => s.isNotEmpty),
        );
      }
      if (widget.initialEntry!.engineers != null) {
        _selectedEngineers.addAll(
          widget.initialEntry!.engineers!
              .split(', ')
              .where((s) => s.isNotEmpty),
        );
      }
      _workDescController.text = widget.initialEntry!.workDescription;
      _timeControllers[0].text = widget.initialEntry!.totalTime.toString();
      _notesController.text = widget.initialEntry!.notes ?? '';
    }
  }

  void _loadData() async {
    final parts = await LocalDatabase.instance.getSpareParts();
    final machinesData = await LocalDatabase.instance.getMachines();
    final engineersData = await LocalDatabase.instance.getEngineers();

    final activeCrewList = widget.activeCrew == 'No crew assigned'
        ? <String>[]
        : widget.activeCrew.split(', ').map((e) => e.trim()).toList();

    setState(() {
      _availableParts = parts;
      _machines = machinesData.map((e) => e['name'] as String).toList();
      _availableEngineers = engineersData
          .map((e) => e['full_name'] as String)
          .where(
            (name) => activeCrewList.contains(name),
          ) // Only show assigned shift crew
          .toList();

      // Ensure any already selected engineers (e.g. from an old entry) are still visible
      for (var selected in _selectedEngineers) {
        if (!_availableEngineers.contains(selected)) {
          _availableEngineers.add(selected);
        }
      }
    });
  }

  int _parseTime(String input) {
    if (input.isEmpty) return 0;

    // Check if it's a simple number
    if (int.tryParse(input) != null) {
      return int.parse(input);
    }

    // Try parsing intervals like "09:00-10:30 + 12:00-12:45"
    int totalMinutes = 0;
    try {
      final parts = input.split('+');
      for (var p in parts) {
        final times = p.trim().split('-');
        if (times.length == 2) {
          final start = times[0].trim().split(':');
          final end = times[1].trim().split(':');

          final startMinutes = int.parse(start[0]) * 60 + int.parse(start[1]);
          final endMinutes = int.parse(end[0]) * 60 + int.parse(end[1]);

          totalMinutes += (endMinutes - startMinutes);
        }
      }
      return totalMinutes > 0 ? totalMinutes : 0;
    } catch (e) {
      return 0; // Fallback
    }
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedLines.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one line')),
        );
        return;
      }
      if (_selectedEngineers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please assign at least one engineer')),
        );
        return;
      }

      int parsedTime = 0;
      for (var ctrl in _timeControllers) {
        if (ctrl.text.isNotEmpty) {
          parsedTime += _parseTime(ctrl.text);
        }
      }

      List<String> partsUsedList = [];
      for (var sp in _selectedParts) {
        if (sp.partData != null) {
          final int qty = int.tryParse(sp.qtyController.text) ?? 1;
          partsUsedList.add(
            sp.partData!['name'].toString() + ' (Qty: ' + qty.toString() + ')',
          );
        }
      }
      String? partsUsedString = partsUsedList.isNotEmpty
          ? partsUsedList.join(', ')
          : null;

      final entry = LogEntry(
        id: (widget.initialEntry != null && !widget.isDuplicate)
            ? widget.initialEntry!.id
            : const Uuid().v4(),
        sectionId: widget.initialEntry?.sectionId ?? 'sec-1',
        machineId: _selectedMachine ?? 'Unknown',
        date:
            widget.initialEntry?.date ??
            DateTime.now().toIso8601String().split('T')[0],
        shift: widget.initialEntry?.shift ?? widget.activeShift,
        workDescription: _workDescController.text,
        totalTime: parsedTime,
        lineId: _selectedLines.join(', '),
        engineers: _selectedEngineers.join(', '),
        partsUsed: partsUsedString,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        createdAt: widget.initialEntry?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

      if (!mounted) return;
      Navigator.of(context).pop(entry);
    }
  }

  Widget _buildTimeInputs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Stoppage Intervals (mins or 09:00-10:30)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._timeControllers.asMap().entries.map((entry) {
          final index = entry.key;
          final controller = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 45 or 09:00-10:30',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    validator: (val) =>
                        (val == null || val.isEmpty) && index == 0
                        ? 'Required'
                        : null,
                  ),
                ),
                if (_timeControllers.length > 1)
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      setState(() {
                        _timeControllers.removeAt(index);
                      });
                    },
                  ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _timeControllers.add(TextEditingController());
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Interval'),
          ),
        ),
      ],
    );
  }

  Widget _buildSpareParts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Spare Parts Used',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._selectedParts.asMap().entries.map((entry) {
          final index = entry.key;
          final sp = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    isExpanded: true,
                    value: sp.partId,
                    hint: const Text('Select part'),
                    items: _availableParts.map((p) {
                      final isLow = (p['stock'] as int) < 3;
                      final isOut = (p['stock'] as int) == 0;
                      return DropdownMenuItem<String>(
                        value: p['id'] as String,
                        child: Text(
                          p['name'].toString() +
                              " (Stock: " +
                              p['stock'].toString() +
                              ")",
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isOut
                                ? Colors.grey
                                : (isLow ? Colors.orange : null),
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        sp.partId = val;
                        sp.partData = _availableParts.firstWhere(
                          (p) => p['id'] == val,
                          orElse: () => <String, dynamic>{},
                        );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: sp.qtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Qty',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                if (_selectedParts.length > 1)
                  IconButton(
                    icon: const Icon(
                      Icons.remove_circle_outline,
                      color: Colors.red,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedParts.removeAt(index);
                      });
                    },
                  ),
              ],
            ),
          );
        }),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _selectedParts.add(_SelectedPart());
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Spare Part'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.initialEntry == null || widget.isDuplicate
                    ? 'New Log Entry (Duplicate) - ' + widget.activeShift
                    : 'Edit Log Entry - ' + widget.initialEntry!.shift,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  children: [
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Machine',
                        border: OutlineInputBorder(),
                      ),
                      initialValue: _selectedMachine,
                      items: _machines
                          .map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          )
                          .toList(),
                      onChanged: (val) =>
                          setState(() => _selectedMachine = val),
                      validator: (val) =>
                          val == null ? 'Please select a machine' : null,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Lines (Multi-select)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: _availableLines.map((line) {
                        final isSelected = _selectedLines.contains(line);
                        return FilterChip(
                          label: Text(line),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedLines.add(line);
                              } else {
                                _selectedLines.remove(line);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Assigned Engineers (Multi-select)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Wrap(
                      spacing: 8,
                      children: _availableEngineers.map((eng) {
                        final isSelected = _selectedEngineers.contains(eng);
                        return FilterChip(
                          label: Text(eng),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedEngineers.add(eng);
                              } else {
                                _selectedEngineers.remove(eng);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _workDescController,
                      decoration: const InputDecoration(
                        labelText: 'Work Description',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (val) =>
                          val == null || val.isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    _buildTimeInputs(),
                    const SizedBox(height: 16),
                    _buildSpareParts(),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (Optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _submit,
                    child: const Text('Save Entry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
