class LogEntry {
  final String id;
  final String sectionId;
  final String machineId;
  final String date;
  final String shift;
  final String workDescription;
  final int totalTime;
  final String? lineId;
  final String? notes;
  final String? engineers;
  final String? partsUsed;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus; // 'pending' or 'synced'

  LogEntry({
    required this.id,
    required this.sectionId,
    required this.machineId,
    required this.date,
    required this.shift,
    required this.workDescription,
    required this.totalTime,
    this.lineId,
    this.notes,
    this.engineers,
    this.partsUsed,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'pending',
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'section_id': sectionId,
      'machine_id': machineId,
      'date': date,
      'shift': shift,
      'work_description': workDescription,
      'total_time': totalTime,
      'line_id': lineId,
      'notes': notes,
      'engineers': engineers,
      'parts_used': partsUsed,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    return LogEntry(
      id: map['id'] ?? '',
      sectionId: map['section_id'] ?? '',
      machineId: map['machine_id'] ?? '',
      date: map['date'] ?? '',
      shift: map['shift'] ?? '',
      workDescription: map['work_description'] ?? '',
      totalTime: map['total_time'] is int
          ? map['total_time']
          : int.tryParse(map['total_time']?.toString() ?? '0') ?? 0,
      lineId: map['line_id'],
      notes: map['notes'],
      engineers: map['engineers'],
      partsUsed: map['parts_used'],
      createdAt: parseDate(map['created_at']),
      updatedAt: parseDate(map['updated_at']),
      syncStatus: map['sync_status'] ?? 'pending',
    );
  }
}
