import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('maintlog.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 9,
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 6) {
          await db.execute('DROP TABLE IF EXISTS log_entries');
          await db.execute('DROP TABLE IF EXISTS spare_parts');
          await db.execute('DROP TABLE IF EXISTS machines');
          await db.execute('DROP TABLE IF EXISTS engineers');
          await db.execute('DROP TABLE IF EXISTS shift_engineers');
          await db.execute('DROP TABLE IF EXISTS todo_tasks');
          await db.execute('DROP TABLE IF EXISTS line_numbers');
          await _createDB(db, newVersion);
        }
        if (oldVersion < 7) {
          try {
            await db.execute(
              'ALTER TABLE todo_tasks ADD COLUMN completed_by TEXT',
            );
            await db.execute(
              'ALTER TABLE todo_tasks ADD COLUMN completed_at TEXT',
            );
          } catch (_) {}
        }
        if (oldVersion < 8) {
          try {
            await db.execute(
              "ALTER TABLE todo_tasks ADD COLUMN sync_status TEXT DEFAULT 'pending'",
            );
          } catch (_) {}
        }
        if (oldVersion < 9) {
          try {
            await db.execute(
              'ALTER TABLE todo_tasks ADD COLUMN assigned_to TEXT',
            );
          } catch (_) {}
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
    CREATE TABLE log_entries (
      id TEXT PRIMARY KEY,
      section_id TEXT,
      machine_id TEXT,
      date TEXT NOT NULL,
      shift TEXT NOT NULL,
      work_description TEXT NOT NULL,
      total_time INTEGER,
      line_id TEXT,
      notes TEXT,
      engineers TEXT,
      parts_used TEXT,
      created_at TEXT,
      updated_at TEXT,
      sync_status TEXT DEFAULT 'pending'
    )
    ''');

    await db.execute('''
    CREATE TABLE spare_parts (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      part_number TEXT NOT NULL,
      stock INTEGER DEFAULT 0,
      sync_status TEXT DEFAULT 'synced'
    )
    ''');

    await db.execute('''
    CREATE TABLE machines (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sync_status TEXT DEFAULT 'synced'
    )
    ''');

    await db.execute('''
    CREATE TABLE engineers (
      id TEXT PRIMARY KEY,
      full_name TEXT NOT NULL,
      pin TEXT,
      role TEXT,
      sync_status TEXT DEFAULT 'synced'
    )
    ''');

    await db.execute('''
    CREATE TABLE shift_engineers (
      id TEXT PRIMARY KEY,
      shift TEXT NOT NULL,
      date TEXT NOT NULL,
      engineer_names TEXT,
      sync_status TEXT DEFAULT 'pending'
    )
    ''');

    await db.execute('''
    CREATE TABLE todo_tasks (
      id TEXT PRIMARY KEY,
      description TEXT NOT NULL,
      priority TEXT NOT NULL DEFAULT 'Medium',
      created_by TEXT NOT NULL DEFAULT 'Unknown',
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT,
      completed_by TEXT,
      completed_at TEXT,
      assigned_to TEXT,
      sync_status TEXT DEFAULT 'pending'
    )
    ''');

    await db.execute('''
    CREATE TABLE line_numbers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      sync_status TEXT DEFAULT 'synced'
    )
    ''');

    // Removed initial seed data for empty initialization
  }

  // ─── Log Entries ───

  Future<void> _adjustStock(String? partsUsedString, bool isUndo) async {
    if (partsUsedString == null || partsUsedString.isEmpty) return;
    // Format is "PartName (Qty: 2)"
    final match = RegExp(
      r'^(.*?) \(Qty: (\d+)\)$',
    ).firstMatch(partsUsedString.trim());
    if (match != null) {
      final partName = match.group(1)?.trim();
      final qtyStr = match.group(2);
      if (partName != null && qtyStr != null) {
        final qty = int.tryParse(qtyStr) ?? 0;
        if (qty > 0) {
          final db = await instance.database;
          final parts = await db.query(
            'spare_parts',
            where: 'name = ?',
            whereArgs: [partName],
          );
          if (parts.isNotEmpty) {
            final part = parts.first;
            final currentStock = part['stock'] as int;
            final newStock = isUndo
                ? currentStock + qty
                : (currentStock - qty >= 0 ? currentStock - qty : 0);
            await updateSparePartStock(part['id'] as String, newStock);
          }
        }
      }
    }
  }

  Future<void> insertEntry(Map<String, dynamic> entry) async {
    final db = await instance.database;
    await db.insert(
      'log_entries',
      entry,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Only deduct stock on local inserts, not cloud syncs
    final syncStatus = entry['sync_status'] as String? ?? 'pending';
    if (syncStatus == 'pending') {
      await _adjustStock(entry['parts_used'] as String?, false);
    }
  }

  Future<List<Map<String, dynamic>>> getEntries(
    String date,
    String shift,
  ) async {
    final db = await instance.database;
    return await db.query(
      'log_entries',
      where: 'date = ? AND shift = ?',
      whereArgs: [date, shift],
      orderBy: 'created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> searchEntries(
    String date,
    String shift,
    String query,
  ) async {
    final db = await instance.database;
    final wildcard = '%$query%';
    return await db.query(
      'log_entries',
      where:
          'date = ? AND shift = ? AND (machine_id LIKE ? OR engineers LIKE ? OR work_description LIKE ?)',
      whereArgs: [date, shift, wildcard, wildcard, wildcard],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deleteEntry(String id) async {
    final db = await instance.database;

    // Fetch first to refund parts
    final entries = await db.query(
      'log_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (entries.isNotEmpty) {
      final oldEntry = entries.first;
      await _adjustStock(oldEntry['parts_used'] as String?, true);
    }

    await db.delete('log_entries', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateEntry(Map<String, dynamic> entry) async {
    final db = await instance.database;

    // Refund old parts before updating
    final entries = await db.query(
      'log_entries',
      where: 'id = ?',
      whereArgs: [entry['id']],
    );
    if (entries.isNotEmpty) {
      final oldEntry = entries.first;
      await _adjustStock(oldEntry['parts_used'] as String?, true);
    }

    await db.update(
      'log_entries',
      entry,
      where: 'id = ?',
      whereArgs: [entry['id']],
    );

    // Deduct new parts
    await _adjustStock(entry['parts_used'] as String?, false);
  }

  // ─── Spare Parts ───

  Future<List<Map<String, dynamic>>> getSpareParts() async {
    final db = await instance.database;
    return await db.query('spare_parts', orderBy: 'name ASC');
  }

  Future<List<Map<String, dynamic>>> getLowStockParts(int threshold) async {
    final db = await instance.database;
    return await db.query(
      'spare_parts',
      where: 'stock < ?',
      whereArgs: [threshold],
      orderBy: 'stock ASC',
    );
  }

  Future<void> updateSparePartStock(String id, int newStock) async {
    final db = await instance.database;
    await db.update(
      'spare_parts',
      {'stock': newStock, 'sync_status': 'pending'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertSparePart(Map<String, dynamic> part) async {
    final db = await instance.database;
    await db.insert(
      'spare_parts',
      part,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSparePart(
    String id,
    String name,
    String partNumber,
    int stock,
  ) async {
    final db = await instance.database;
    await db.update(
      'spare_parts',
      {
        'name': name,
        'part_number': partNumber,
        'stock': stock,
        'sync_status': 'pending',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSparePart(String id) async {
    final db = await instance.database;
    await db.delete('spare_parts', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Machines CRUD ───

  Future<List<Map<String, dynamic>>> getMachines() async {
    final db = await instance.database;
    return await db.query('machines', orderBy: 'name ASC');
  }

  Future<void> insertMachine(Map<String, dynamic> machine) async {
    final db = await instance.database;
    await db.insert(
      'machines',
      machine,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMachine(String id, String name) async {
    final db = await instance.database;
    await db.update(
      'machines',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteMachine(String id) async {
    final db = await instance.database;
    await db.delete('machines', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Engineers CRUD ───

  Future<List<Map<String, dynamic>>> getEngineers() async {
    final db = await instance.database;
    return await db.query('engineers', orderBy: 'full_name ASC');
  }

  Future<void> insertEngineer(Map<String, dynamic> engineer) async {
    final db = await instance.database;
    await db.insert(
      'engineers',
      engineer,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateEngineer(String id, String name, String role) async {
    final db = await instance.database;
    await db.update(
      'engineers',
      {'full_name': name, 'role': role},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteEngineer(String id) async {
    final db = await instance.database;
    await db.delete('engineers', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Lines CRUD ───

  Future<List<Map<String, dynamic>>> getLines() async {
    final db = await instance.database;
    return await db.query('line_numbers', orderBy: 'name ASC');
  }

  Future<void> insertLine(Map<String, dynamic> line) async {
    final db = await instance.database;
    await db.insert(
      'line_numbers',
      line,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateLine(String id, String name) async {
    final db = await instance.database;
    await db.update(
      'line_numbers',
      {'name': name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteLine(String id) async {
    final db = await instance.database;
    await db.delete('line_numbers', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Shift Engineers ───

  Future<void> saveShiftEngineers(Map<String, dynamic> data) async {
    final db = await instance.database;
    await db.insert(
      'shift_engineers',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getShiftEngineers(
    String date,
    String shift,
  ) async {
    final db = await instance.database;
    final results = await db.query(
      'shift_engineers',
      where: 'date = ? AND shift = ?',
      whereArgs: [date, shift],
    );
    return results.isNotEmpty ? results.first : null;
  }

  // ─── Todo Tasks CRUD ───

  Future<List<Map<String, dynamic>>> getTasks() async {
    final db = await instance.database;
    return await db.query('todo_tasks', orderBy: 'created_at DESC');
  }

  Future<void> insertTask(Map<String, dynamic> task) async {
    final db = await instance.database;
    final Map<String, dynamic> insertData = Map<String, dynamic>.from(task);
    insertData['sync_status'] = 'pending';
    await db.insert(
      'todo_tasks',
      insertData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTaskStatus(
    String id,
    String status, {
    String? completedBy,
    String? completedAt,
  }) async {
    final db = await instance.database;
    final Map<String, Object?> updates = {
      'status': status,
      'sync_status': 'pending',
    };

    if (status == 'done') {
      if (completedBy != null) updates['completed_by'] = completedBy;
      if (completedAt != null) updates['completed_at'] = completedAt;
    } else {
      updates['completed_by'] = null;
      updates['completed_at'] = null;
    }

    await db.update('todo_tasks', updates, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTask(String id) async {
    final db = await instance.database;
    await db.delete('todo_tasks', where: 'id = ?', whereArgs: [id]);
  }

  // ─── Dashboard Queries ───

  Future<List<Map<String, dynamic>>> getTodayEntries() async {
    final db = await instance.database;
    final today = DateTime.now().toIso8601String().split('T')[0];
    return await db.query('log_entries', where: 'date = ?', whereArgs: [today]);
  }

  Future<List<Map<String, dynamic>>> getEntriesByDateRange(
    String startDate,
    String endDate,
  ) async {
    final db = await instance.database;
    return await db.query(
      'log_entries',
      where: 'date >= ? AND date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'date DESC, created_at DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getEntriesByDateRangeAndEngineer(
    String startDate,
    String endDate,
    String engineer,
  ) async {
    final db = await instance.database;
    final wildcard = '%$engineer%';
    return await db.query(
      'log_entries',
      where: 'date >= ? AND date <= ? AND engineers LIKE ?',
      whereArgs: [startDate, endDate, wildcard],
      orderBy: 'date DESC, created_at DESC',
    );
  }

  Future<int> getPendingTaskCount() async {
    final db = await instance.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as cnt FROM todo_tasks WHERE status = 'pending'",
    );
    return result.first['cnt'] as int;
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
