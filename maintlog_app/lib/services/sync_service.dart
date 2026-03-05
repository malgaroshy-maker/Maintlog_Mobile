import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/local_database.dart';

class SyncService {
  final _supabase = Supabase.instance.client;
  final _localDb = LocalDatabase.instance;

  Future<void> syncAll() async {
    await _syncTable('log_entries', [
      'id',
      'section_id',
      'machine_id',
      'date',
      'shift',
      'work_description',
      'total_time',
      'line_id',
      'notes',
      'engineers',
      'parts_used',
      'created_at',
      'updated_at',
    ]);

    // Sync other tables (todo_tasks, spare_parts, etc.)
    await _syncTable('todo_tasks', [
      'id',
      'description',
      'priority',
      'created_by',
      'status',
      'created_at',
      'completed_by',
      'completed_at',
    ]);

    await _syncTable('spare_parts', ['id', 'name', 'part_number', 'stock']);

    await _syncTable('machines', ['id', 'name']);

    await _syncTable('engineers', ['id', 'full_name', 'pin', 'role']);

    await _syncTable('shift_engineers', [
      'id',
      'shift',
      'date',
      'engineer_names',
    ]);

    await _syncTable('line_numbers', ['id', 'name']);
  }

  Future<void> _syncTable(String tableName, List<String> columns) async {
    final db = await _localDb.database;

    // 1. Push pending local entries to Supabase
    final pendingEntries = await db.query(
      tableName,
      where: 'sync_status = ?',
      whereArgs: ['pending'],
    );

    for (var entry in pendingEntries) {
      try {
        final payload = <String, dynamic>{};
        for (var key in columns) {
          if (entry[key] != null) {
            payload[key] = entry[key];
          }
        }

        await _supabase.from(tableName).upsert(payload);

        // Mark as synced locally
        await db.update(
          tableName,
          {'sync_status': 'synced'},
          where: 'id = ?',
          whereArgs: [entry['id']],
        );
        debugPrint('Synced $tableName entry: ' + entry['id'].toString());
      } catch (e) {
        debugPrint(
          'Error syncing $tableName entry ' +
              entry['id'].toString() +
              ': ' +
              e.toString(),
        );
      }
    }

    // 2. Pull remote entries into local DB
    try {
      final remoteEntries = await _supabase.from(tableName).select();

      for (var remote in remoteEntries) {
        final localPayload = <String, dynamic>{};
        for (var key in columns) {
          if (remote[key] != null) {
            localPayload[key] = remote[key] is int
                ? remote[key]
                : remote[key].toString();
          }
        }
        localPayload['sync_status'] = 'synced';

        await db.insert(
          tableName,
          localPayload,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      debugPrint(
        'Pulled \${remoteEntries.length} remote entries for $tableName',
      );
    } catch (e) {
      debugPrint('Error fetching remote $tableName entries: ' + e.toString());
    }
  }

  Future<bool> hasPendingSyncs() async {
    final db = await _localDb.database;
    final tables = [
      'log_entries',
      'todo_tasks',
      'spare_parts',
      'machines',
      'engineers',
      'shift_engineers',
      'line_numbers',
    ];

    for (var table in tables) {
      final count = Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM $table WHERE sync_status = 'pending'",
        ),
      );
      if (count != null && count > 0) return true;
    }
    return false;
  }
}
