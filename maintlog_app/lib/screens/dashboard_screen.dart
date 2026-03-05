import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import '../database/local_database.dart';
import '../services/sync_service.dart';
import '../l10n/app_localizations.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _totalDowntime = 0;
  int _openTasks = 0;
  Map<String, int> _machineDowntime = {};
  Map<String, int> _shiftCounts = {};
  int _lowStockItems = 0;
  bool _isLoading = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  bool _hasPendingSync = false;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      if (mounted) {
        setState(() {
          _startDate = picked.start;
          _endDate = picked.end;
          _isLoading = true;
        });
        _loadDashboardData();
      }
    }
  }

  Future<void> _loadDashboardData() async {
    final db = LocalDatabase.instance;
    final startStr = _startDate.toIso8601String().split('T')[0];
    final endStr = _endDate.toIso8601String().split('T')[0];
    final dateRangeEntries = await db.getEntriesByDateRange(startStr, endStr);
    final pendingTasks = await db.getPendingTaskCount();
    final parts = await db.getSpareParts();
    final lowStockCount = parts.where((p) => (p['stock'] as int) < 5).length;
    final hasPendingSync = await SyncService().hasPendingSyncs();

    // Compute total downtime and machine breakdown
    int totalDown = 0;
    final Map<String, int> machDown = {};
    final Map<String, int> shiftCount = {
      'Morning Shift': 0,
      'Evening Shift': 0,
      'Night Shift': 0,
    };

    for (var entry in dateRangeEntries) {
      final time = entry['total_time'] as int? ?? 0;
      totalDown += time;

      final machine = entry['machine_id'] as String? ?? 'Unknown';
      machDown[machine] = (machDown[machine] ?? 0) + time;

      final shift = entry['shift'] as String? ?? 'Unknown';
      if (shiftCount.containsKey(shift)) {
        shiftCount[shift] = shiftCount[shift]! + 1;
      }
    }

    if (mounted) {
      setState(() {
        _totalDowntime = totalDown;
        _openTasks = pendingTasks;
        _machineDowntime = machDown;
        _shiftCounts = shiftCount;
        _lowStockItems = lowStockCount;
        _hasPendingSync = hasPendingSync;
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isLoading = true);
    await SyncService().syncAll();
    await _loadDashboardData();
  }

  Widget _buildDateRangeBanner() {
    final startStr = _startDate.toIso8601String().split('T')[0];
    final endStr = _endDate.toIso8601String().split('T')[0];
    final displayStr = startStr == endStr ? startStr : '$startStr to $endStr';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.date_range,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            'Showing data for: $displayStr',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.dashboard),
        actions: [
          IconButton(
            icon: Icon(
              _hasPendingSync ? Icons.cloud_upload : Icons.cloud_done,
              color: _hasPendingSync ? Colors.orange : Colors.green,
            ),
            tooltip: _hasPendingSync ? 'Pending Syncs' : 'All Synced',
            onPressed: _hasPendingSync ? _triggerManualSync : null,
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: 'Select date range',
            onPressed: _pickDateRange,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildDateRangeBanner(),
                    if (_lowStockItems > 0)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '$_lowStockItems spare parts are low on stock!',
                                style: const TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    _buildSummaryCards(context),
                    const SizedBox(height: 24),
                    Text(
                      'Downtime Per Machine (Minutes)',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 250,
                      child: _buildDowntimeBarChart(context),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Interventions by Shift',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(height: 200, child: _buildShiftPieChart(context)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildCard(
            context,
            'Total Downtime',
            _totalDowntime.toString() + ' min',
            Icons.timer,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildCard(
            context,
            'Open Tasks',
            _openTasks.toString(),
            Icons.assignment_late,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            value,
            style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDowntimeBarChart(BuildContext context) {
    if (_machineDowntime.isEmpty) {
      return const Center(child: Text('No downtime data today'));
    }

    final machines = _machineDowntime.keys.toList();
    final maxY =
        _machineDowntime.values
            .fold<int>(0, (a, b) => a > b ? a : b)
            .toDouble() *
        1.2;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY < 10 ? 10 : maxY,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < machines.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      machines[value.toInt()],
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(machines.length, (i) {
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: (_machineDowntime[machines[i]] ?? 0).toDouble(),
                color: Theme.of(context).colorScheme.primary,
                width: 20,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildShiftPieChart(BuildContext context) {
    final totalInterventions = _shiftCounts.values.fold<int>(
      0,
      (a, b) => a + b,
    );
    if (totalInterventions == 0) {
      return const Center(child: Text('No interventions recorded today'));
    }

    final colors = [Colors.blue, Colors.orange, Colors.purple];
    final shifts = _shiftCounts.keys.toList();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 40,
        sections: List.generate(shifts.length, (i) {
          final count = _shiftCounts[shifts[i]] ?? 0;
          final pct = (count / totalInterventions * 100).round();
          return PieChartSectionData(
            color: colors[i % colors.length],
            value: count.toDouble(),
            title:
                shifts[i].replaceAll(' Shift', '') +
                '\n' +
                pct.toString() +
                '%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }),
      ),
    );
  }
}
