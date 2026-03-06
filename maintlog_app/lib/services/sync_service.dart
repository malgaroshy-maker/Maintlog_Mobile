import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/local_database.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _supabase = Supabase.instance.client;
  final _localDb = LocalDatabase.instance;

  final List<RealtimeChannel> _channels = [];
  final _syncController = StreamController<void>.broadcast();

  /// Stream that fires whenever a realtime sync event occurs
  Stream<void> get onSyncEvent => _syncController.stream;

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

    await _syncTable('todo_tasks', [
      'id',
      'description',
      'priority',
      'created_by',
      'status',
      'created_at',
      'completed_by',
      'completed_at',
      'assigned_to',
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

    // 1. Push pending local entries to Supabase (with conflict check)
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

        // Conflict resolution: check if remote version is newer
        bool shouldPush = true;
        if (columns.contains('updated_at') && entry['updated_at'] != null) {
          try {
            final remoteRows = await _supabase
                .from(tableName)
                .select('updated_at')
                .eq('id', entry['id'] as String);

            if (remoteRows.isNotEmpty &&
                remoteRows.first['updated_at'] != null) {
              final remoteUpdated = DateTime.tryParse(
                remoteRows.first['updated_at'].toString(),
              );
              final localUpdated = DateTime.tryParse(
                entry['updated_at'].toString(),
              );
              if (remoteUpdated != null &&
                  localUpdated != null &&
                  remoteUpdated.isAfter(localUpdated)) {
                // Remote is newer — skip push, pull remote instead
                shouldPush = false;
                debugPrint(
                  'Conflict: remote $tableName entry ' +
                      entry['id'].toString() +
                      ' is newer, pulling.',
                );
              }
            }
          } catch (_) {
            // If we can't check, push anyway
          }
        }

        if (shouldPush) {
          await _supabase.from(tableName).upsert(payload);
        }

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
        'Pulled ' +
            remoteEntries.length.toString() +
            ' remote entries for $tableName',
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

  /// Subscribe to Supabase Realtime for key tables
  void listen() {
    final tablesToWatch = [
      'log_entries',
      'todo_tasks',
      'spare_parts',
      'machines',
      'engineers',
    ];

    for (var table in tablesToWatch) {
      final channel = _supabase
          .channel('public:$table')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: table,
            callback: (payload) {
              debugPrint(
                'Realtime event on $table: ' + payload.eventType.toString(),
              );
              // Trigger a sync for this table
              _syncTableSilently(table);
            },
          )
          .subscribe();

      _channels.add(channel);
    }
    debugPrint('Realtime listeners active for ${tablesToWatch.length} tables.');
  }

  /// Internal silent sync used by realtime — does not push, only pulls
  Future<void> _syncTableSilently(String table) async {
    try {
      final db = await _localDb.database;
      final columnsMap = {
        'log_entries': [
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
        ],
        'todo_tasks': [
          'id',
          'description',
          'priority',
          'created_by',
          'status',
          'created_at',
          'completed_by',
          'completed_at',
          'assigned_to',
        ],
        'spare_parts': ['id', 'name', 'part_number', 'stock'],
        'machines': ['id', 'name'],
        'engineers': ['id', 'full_name', 'pin', 'role'],
      };

      final columns = columnsMap[table];
      if (columns == null) return;

      final remoteEntries = await _supabase.from(table).select();
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
          table,
          localPayload,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      _syncController.add(null);
    } catch (e) {
      debugPrint('Silent sync error for $table: ' + e.toString());
    }
  }

  /// Dispose all realtime channels
  void dispose() {
    for (var channel in _channels) {
      _supabase.removeChannel(channel);
    }
    _channels.clear();
    _syncController.close();
    debugPrint('Realtime listeners disposed.');
  }
}
