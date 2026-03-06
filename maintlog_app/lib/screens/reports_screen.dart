import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as xl;
import '../database/local_database.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedReportType = 'Daily Logbook';
  String _selectedShift = 'All Shifts';
  String _selectedMachine = 'All Machines';
  String _selectedEngineer = 'All Engineers';
  DateTimeRange? _dateRange;
  List<Map<String, dynamic>> _machines = [];
  List<Map<String, dynamic>> _lines = [];
  List<Map<String, dynamic>> _engineers = [];
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadMachines();
    _loadEngineers();
    _dateRange = DateTimeRange(start: DateTime.now(), end: DateTime.now());
  }

  Future<void> _loadMachines() async {
    final machines = await LocalDatabase.instance.getMachines();
    final lines = await LocalDatabase.instance.getLines();
    if (mounted) {
      setState(() {
        _machines = machines;
        _lines = lines;
      });
    }
  }

  String _getLineName(String? lineId) {
    if (lineId == null) return 'Unassigned';
    final line = _lines.where((l) => l['id'] == lineId).firstOrNull;
    return line?['name']?.toString() ?? 'Unknown Line';
  }

  Future<void> _loadEngineers() async {
    final engineers = await LocalDatabase.instance.getEngineers();
    if (mounted) {
      setState(() => _engineers = engineers);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange,
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
    }
  }

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, dynamic>>> _fetchFilteredEntries() async {
    final db = await LocalDatabase.instance.database;
    String where = '1=1';
    List<dynamic> args = [];

    if (_dateRange != null) {
      where += ' AND date >= ? AND date <= ?';
      args.add(_formatDate(_dateRange!.start));
      args.add(_formatDate(_dateRange!.end));
    }
    if (_selectedShift != 'All Shifts') {
      where += ' AND shift = ?';
      args.add(_selectedShift);
    }
    if (_selectedMachine != 'All Machines') {
      where += ' AND machine_id = ?';
      args.add(_selectedMachine);
    }
    if (_selectedEngineer != 'All Engineers') {
      where += ' AND engineers LIKE ?';
      args.add('%$_selectedEngineer%');
    }

    return await db.query(
      'log_entries',
      where: where,
      whereArgs: args,
      orderBy: 'date DESC, created_at DESC',
    );
  }

  Future<void> _exportPDF() async {
    setState(() => _isExporting = true);
    try {
      final entries = await _fetchFilteredEntries();
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'MaintLog Pro – $_selectedReportType',
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Period: ${_formatDate(_dateRange!.start)} to ${_formatDate(_dateRange!.end)}',
              ),
              pw.Text('Shift: $_selectedShift | Machine: $_selectedMachine'),
              pw.Divider(),
            ],
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              context: context,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey300,
              ),
              cellAlignment: pw.Alignment.centerLeft,
              headers: [
                'Date',
                'Shift',
                'Machine',
                'Work Description',
                'Time (min)',
                'Parts Used',
                'Notes',
              ],
              data: entries
                  .map(
                    (e) => [
                      e['date'] ?? '',
                      e['shift'] ?? '',
                      e['machine_id'] ?? '',
                      e['work_description'] ?? '',
                      (e['total_time'] ?? 0).toString(),
                      e['parts_used'] ?? '',
                      e['notes'] ?? '',
                    ],
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Total Entries: ${entries.length}',
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ],
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Generated: ${DateTime.now().toString().substring(0, 19)}',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('PDF Error: $e')));
      }
    }
    if (mounted) setState(() => _isExporting = false);
  }

  Future<void> _exportCSV() async {
    setState(() => _isExporting = true);
    try {
      final entries = await _fetchFilteredEntries();
      final buffer = StringBuffer();
      buffer.writeln(
        'Date,Shift,Machine,Work Description,Time (min),Parts Used,Notes',
      );

      for (var e in entries) {
        final desc = (e['work_description'] ?? '').toString().replaceAll(
          ',',
          ';',
        );
        final notes = (e['notes'] ?? '').toString().replaceAll(',', ';');
        final parts = (e['parts_used'] ?? '').toString().replaceAll(',', ';');
        buffer.writeln(
          "${e['date'] ?? ''},${e['shift'] ?? ''},${e['machine_id'] ?? ''},$desc,${e['total_time'] ?? 0},$parts,$notes",
        );
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/maintlog_report.csv');
      await file.writeAsString(buffer.toString());

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], title: 'MaintLog Report'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('CSV Error: $e')));
      }
    }
    if (mounted) setState(() => _isExporting = false);
  }

  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    try {
      final entries = await _fetchFilteredEntries();
      final excel = xl.Excel.createExcel();
      final sheet = excel['MaintLog Report'];

      // Header row
      sheet.appendRow([
        xl.TextCellValue('Date'),
        xl.TextCellValue('Shift'),
        xl.TextCellValue('Machine'),
        xl.TextCellValue('Engineers'),
        xl.TextCellValue('Work Description'),
        xl.TextCellValue('Total Time (min)'),
        xl.TextCellValue('Spare Parts'),
        xl.TextCellValue('Notes'),
      ]);

      for (var e in entries) {
        sheet.appendRow([
          xl.TextCellValue((e['date'] ?? '').toString()),
          xl.TextCellValue((e['shift'] ?? '').toString()),
          xl.TextCellValue((e['machine_id'] ?? '').toString()),
          xl.TextCellValue((e['engineers'] ?? '').toString()),
          xl.TextCellValue((e['work_description'] ?? '').toString()),
          xl.IntCellValue(e['total_time'] as int? ?? 0),
          xl.TextCellValue((e['parts_used'] ?? '').toString()),
          xl.TextCellValue((e['notes'] ?? '').toString()),
        ]);
      }

      // Remove the default Sheet1 if it exists
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/maintlog_report.xlsx';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path)], title: 'MaintLog Report'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Excel Error: $e')));
      }
    }
    if (mounted) setState(() => _isExporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateRange != null
        ? '${_formatDate(_dateRange!.start)} → ${_formatDate(_dateRange!.end)}'
        : 'Select dates';

    final machineItems = ['All Machines'];
    for (var m in _machines) {
      machineItems.add(
        '${m['name']} (${_getLineName(m['line_id']?.toString())})',
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Reporting System')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Generate Report',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Report Type',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedReportType,
              items: [
                'Daily Logbook',
                'Downtime Analysis',
                'Spare Parts Usage',
              ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedReportType = val);
              },
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDateRange,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date Range',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.date_range),
                ),
                child: Text(dateLabel),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Filter by Machine',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedMachine,
              items: machineItems
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedMachine = val);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Filter by Shift',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedShift,
              items: [
                'All Shifts',
                'Night Shift',
                'Morning Shift',
                'Evening Shift',
              ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedShift = val);
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Filter by Engineer',
                border: OutlineInputBorder(),
              ),
              initialValue: _selectedEngineer,
              items: [
                const DropdownMenuItem(
                  value: 'All Engineers',
                  child: Text('All Engineers'),
                ),
                ..._engineers.map(
                  (e) => DropdownMenuItem(
                    value: e['full_name'] as String,
                    child: Text(e['full_name'] as String),
                  ),
                ),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedEngineer = val);
              },
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isExporting ? null : _exportPDF,
              icon: _isExporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.picture_as_pdf),
              label: const Text('Export to PDF (A4 Landscape)'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportCSV,
              icon: const Icon(Icons.table_view),
              label: const Text('Export to CSV'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isExporting ? null : _exportExcel,
              icon: const Icon(Icons.grid_on),
              label: const Text('Export to Excel (.xlsx)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
