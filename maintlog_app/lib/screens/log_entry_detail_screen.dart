import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/log_entry.dart';
import '../database/local_database.dart';
import '../widgets/new_log_entry_dialog.dart';

class LogEntryDetailScreen extends StatelessWidget {
  final LogEntry entry;
  final VoidCallback? onUpdated;

  const LogEntryDetailScreen({super.key, required this.entry, this.onUpdated});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entry Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () => _editEntry(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.redAccent),
            tooltip: 'Delete',
            onPressed: () => _deleteEntry(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: cs.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.precision_manufacturing, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            entry.machineId,
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: entry.syncStatus == 'synced'
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            entry.syncStatus == 'synced' ? 'Synced' : 'Pending',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: entry.syncStatus == 'synced'
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${entry.date}  •  ${entry.shift}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Details
            _buildDetailTile(
              context,
              icon: Icons.description,
              label: 'Work Description',
              value: entry.workDescription,
            ),
            _buildDetailTile(
              context,
              icon: Icons.timer,
              label: 'Total Downtime',
              value: '${entry.totalTime} minutes',
            ),
            if (entry.lineId != null && entry.lineId!.isNotEmpty)
              _buildDetailTile(
                context,
                icon: Icons.linear_scale,
                label: 'Line',
                value: entry.lineId!,
              ),
            if (entry.engineers != null && entry.engineers!.isNotEmpty)
              _buildDetailTile(
                context,
                icon: Icons.engineering,
                label: 'Engineers',
                value: entry.engineers!,
              ),

            // Spare Parts Section
            if (entry.partsUsed != null && entry.partsUsed!.isNotEmpty)
              _buildPartsSection(context),

            if (entry.notes != null && entry.notes!.isNotEmpty)
              _buildDetailTile(
                context,
                icon: Icons.notes,
                label: 'Notes',
                value: entry.notes!,
              ),

            const Divider(height: 32),
            // Timestamps
            Row(
              children: [
                Expanded(
                  child: _buildTimestamp(
                    context,
                    label: 'Created',
                    time: entry.createdAt,
                  ),
                ),
                Expanded(
                  child: _buildTimestamp(
                    context,
                    label: 'Updated',
                    time: entry.updatedAt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(value, style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }

  Widget _buildPartsSection(BuildContext context) {
    // Parts are stored as "PartA (Qty: 2), PartB (Qty: 1)"
    final parts = entry.partsUsed!
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.build, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                const Text(
                  'Spare Parts Used',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...parts.map(
              (part) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(part, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimestamp(
    BuildContext context, {
    required String label,
    required DateTime time,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          time.toIso8601String().replaceAll('T', '  ').split('.').first,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  void _editEntry(BuildContext context) async {
    final result = await showDialog<LogEntry>(
      context: context,
      builder: (context) => NewLogEntryDialog(
        activeShift: entry.shift,
        activeCrew: entry.engineers ?? '',
        initialEntry: entry,
      ),
    );
    if (result != null) {
      await LocalDatabase.instance.updateEntry(result.toMap());
      onUpdated?.call();
      if (context.mounted) Navigator.pop(context);
    }
  }

  void _deleteEntry(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry?'),
        content: const Text('This will permanently remove this log entry.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await LocalDatabase.instance.deleteEntry(entry.id);
      onUpdated?.call();
      if (context.mounted) Navigator.pop(context);
    }
  }
}
