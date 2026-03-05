import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../database/local_database.dart';
import '../models/log_entry.dart';
import '../services/sync_service.dart';
import '../widgets/new_log_entry_dialog.dart';
import '../l10n/app_localizations.dart';

class LogbookScreen extends StatefulWidget {
  const LogbookScreen({super.key});

  @override
  State<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends State<LogbookScreen> {
  String _activeShift = 'Morning Shift';
  DateTime _selectedDate = DateTime.now();
  final List<String> _shifts = [
    'Night Shift',
    'Morning Shift',
    'Evening Shift',
  ];

  List<LogEntry> _entries = [];
  String _activeCrew = 'No crew assigned';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  String get _dateString {
    return _selectedDate.year.toString() +
        '-' +
        _selectedDate.month.toString().padLeft(2, '0') +
        '-' +
        _selectedDate.day.toString().padLeft(2, '0');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadEntries();
    }
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);

    final results = await Future.wait([
      LocalDatabase.instance.getEntries(_dateString, _activeShift),
      LocalDatabase.instance.getShiftEngineers(_dateString, _activeShift),
    ]);

    final entryMaps = results[0] as List<Map<String, dynamic>>;
    final shiftCrew = results[1] as Map<String, dynamic>?;

    setState(() {
      _entries = entryMaps.map((e) => LogEntry.fromMap(e)).toList();
      _activeCrew = shiftCrew?['engineer_names'] ?? 'No crew assigned';
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.logbook),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Pick date',
            onPressed: _pickDate,
          ),
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: () async {
              setState(() => _isLoading = true);
              await SyncService().syncAll();
              await _loadEntries();
            },
          ),
          IconButton(icon: const Icon(Icons.add), onPressed: _addNewRow),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildShiftSelector(),
          _buildCrewHeader(),
          Expanded(child: _buildSpreadsheet()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewRow,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildShiftSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          const Text(
            'Active Shift: ',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 16),
          DropdownButton<String>(
            value: _activeShift,
            underline: const SizedBox(),
            items: _shifts
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _activeShift = val);
                _loadEntries();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCrewHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const Icon(Icons.engineering, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Assigned Crew: ' + _activeCrew,
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: _editCrew,
            tooltip: 'Manage Shift Crew',
          ),
          const SizedBox(width: 8),
          Text(
            _entries.length.toString() + ' entries | ' + _dateString,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _editCrew() async {
    final allEngineers = await LocalDatabase.instance.getEngineers();
    final List<String> currentCrew = _activeCrew == 'No crew assigned'
        ? []
        : _activeCrew.split(', ');

    if (!mounted) return;

    final selectedEngineers = await showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        List<String> selected = List.from(currentCrew);
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text('Assign Crew - ' + _activeShift),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: allEngineers.map((eng) {
                    final name = eng['full_name'] as String;
                    final isSelected = selected.contains(name);
                    return CheckboxListTile(
                      title: Text(name),
                      value: isSelected,
                      onChanged: (val) {
                        setModalState(() {
                          if (val == true) {
                            selected.add(name);
                          } else {
                            selected.remove(name);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedEngineers != null) {
      await LocalDatabase.instance.saveShiftEngineers({
        'id': _dateString + '_' + _activeShift,
        'shift': _activeShift,
        'date': _dateString,
        'engineer_names': selectedEngineers.join(', '),
      });
      _loadEntries();
    }
  }

  Widget _buildSpreadsheet() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.surfaceContainerHigh,
          ),
          columns: const [
            DataColumn(label: Text('Machine')),
            DataColumn(label: Text('Line(s)')),
            DataColumn(label: Text('Engineers')),
            DataColumn(label: Text('Work Description')),
            DataColumn(label: Text('Total Time')),
            DataColumn(label: Text('Spare Parts/Qty')),
            DataColumn(label: Text('Notes')),
            DataColumn(label: Text('Actions')),
          ],
          rows: _entries.map((entry) {
            return DataRow(
              cells: [
                DataCell(Text(entry.machineId)),
                DataCell(Text(entry.lineId ?? '-')),
                DataCell(Text(entry.engineers ?? '-')),
                DataCell(
                  SizedBox(
                    width: 250,
                    child: Text(
                      entry.workDescription,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(entry.totalTime.toString() + 'm')),
                DataCell(Text(entry.partsUsed ?? '-')),
                DataCell(Text(entry.notes ?? '')),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        tooltip: 'Edit',
                        onPressed: () => _editRow(entry),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Duplicate',
                        onPressed: () => _duplicateRow(entry),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          size: 18,
                          color: Colors.redAccent,
                        ),
                        tooltip: 'Delete',
                        onPressed: () => _deleteRow(entry),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _addNewRow() async {
    final result = await showDialog<LogEntry>(
      context: context,
      builder: (context) =>
          NewLogEntryDialog(activeShift: _activeShift, activeCrew: _activeCrew),
    );

    if (result != null) {
      setState(() => _isLoading = true);
      await LocalDatabase.instance.insertEntry(result.toMap());
      await _loadEntries();
      // Passively attempt sync in background
      SyncService().syncAll();
    }
  }

  void _editRow(LogEntry entry) async {
    final result = await showDialog<LogEntry>(
      context: context,
      builder: (context) => NewLogEntryDialog(
        activeShift: _activeShift,
        activeCrew: _activeCrew,
        initialEntry: entry,
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);
      await LocalDatabase.instance.updateEntry(result.toMap());
      await _loadEntries();
      // Passively attempt sync in background
      SyncService().syncAll();
    }
  }

  void _duplicateRow(LogEntry entry) async {
    final result = await showDialog<LogEntry>(
      context: context,
      builder: (context) => NewLogEntryDialog(
        activeShift: _activeShift,
        activeCrew: _activeCrew,
        initialEntry: entry,
        isDuplicate: true,
      ),
    );

    if (result != null) {
      setState(() => _isLoading = true);
      await LocalDatabase.instance.insertEntry(result.toMap());
      await _loadEntries();
      SyncService().syncAll();
    }
  }

  void _deleteRow(LogEntry entry) async {
    // Optimistic UI update
    setState(() {
      _entries.removeWhere((e) => e.id == entry.id);
    });

    await LocalDatabase.instance.deleteEntry(entry.id);
    SyncService().syncAll();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Entry deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            setState(() => _isLoading = true);
            // Re-insert the entry. The DB layer will handle re-deducting stock automatically.
            await LocalDatabase.instance.insertEntry(entry.toMap());
            await _loadEntries();
            SyncService().syncAll();
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
