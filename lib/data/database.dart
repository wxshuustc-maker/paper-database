import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../models.dart';

/// 一条存储在本地数据库里的记录。
class StoredRecord {
  final RecordType type;
  final String id;
  final String json;
  final int updatedAt;
  final bool deleted;
  final bool dirty;
  const StoredRecord(this.type, this.id, this.json, this.updatedAt, this.deleted, this.dirty);
}

/// 本地 SQLite 存储。
///
/// 所有类型的数据都放在同一张 records 表里，正文是 JSON。
/// 这样同步逻辑可以对所有类型通用处理；个人论文库的数据量（几千篇）
/// 完全可以整体加载进内存再筛选。
class LocalDatabase {
  final Database db;
  LocalDatabase(this.db);

  static Future<LocalDatabase> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE records(
              type TEXT NOT NULL,
              id TEXT NOT NULL,
              json TEXT NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0,
              dirty INTEGER NOT NULL DEFAULT 1,
              parent TEXT,
              PRIMARY KEY(type, id)
            )''');
          await db.execute('CREATE INDEX idx_records_parent ON records(type, parent)');
          await db.execute('CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT)');
        },
      ),
    );
    return LocalDatabase(db);
  }

  static String? _parentOf(SyncRecord r) => switch (r) {
        Annotation a => a.paperId,
        InkPage p => p.paperId,
        _ => null,
      };

  /// 保存本地修改，标记为待同步。
  Future<void> put(RecordType type, SyncRecord r, {bool dirty = true}) async {
    await db.insert(
      'records',
      {
        'type': type.name,
        'id': r.id,
        'json': jsonEncode(r.toJson()),
        'updated_at': r.updatedAt,
        'deleted': r.deleted ? 1 : 0,
        'dirty': dirty ? 1 : 0,
        'parent': _parentOf(r),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 仅在记录不存在时插入（用于写入内置分类）。
  Future<void> putIfAbsent(RecordType type, SyncRecord r) async {
    await db.insert(
      'records',
      {
        'type': type.name,
        'id': r.id,
        'json': jsonEncode(r.toJson()),
        'updated_at': r.updatedAt,
        'deleted': r.deleted ? 1 : 0,
        'dirty': 0,
        'parent': _parentOf(r),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<T>> all<T extends SyncRecord>(RecordType type, {bool includeDeleted = false}) async {
    final rows = await db.query('records',
        columns: ['json'],
        where: includeDeleted ? 'type = ?' : 'type = ? AND deleted = 0',
        whereArgs: [type.name]);
    return rows.map((r) => recordFromString(type, r['json'] as String) as T).toList();
  }

  Future<List<T>> byParent<T extends SyncRecord>(RecordType type, String parent) async {
    final rows = await db.query('records',
        columns: ['json'], where: 'type = ? AND parent = ? AND deleted = 0', whereArgs: [type.name, parent]);
    return rows.map((r) => recordFromString(type, r['json'] as String) as T).toList();
  }

  Future<StoredRecord?> getStored(RecordType type, String id) async {
    final rows = await db.query('records', where: 'type = ? AND id = ?', whereArgs: [type.name, id]);
    if (rows.isEmpty) return null;
    return _stored(rows.first);
  }

  Future<T?> get<T extends SyncRecord>(RecordType type, String id) async {
    final s = await getStored(type, id);
    return s == null ? null : recordFromString(type, s.json) as T;
  }

  Future<List<StoredRecord>> dirty(RecordType type) async {
    final rows = await db.query('records', where: 'type = ? AND dirty = 1', whereArgs: [type.name]);
    return rows.map(_stored).toList();
  }

  /// 上传成功后清除待同步标记。只有在上传期间没有被再次修改时才清除。
  Future<void> markClean(RecordType type, String id, int updatedAt) async {
    await db.update('records', {'dirty': 0},
        where: 'type = ? AND id = ? AND updated_at = ?', whereArgs: [type.name, id, updatedAt]);
  }

  /// 把所有记录标记为待上传（切换加密模式后需要把数据完整上传一遍）。
  Future<void> markAllDirty() async {
    // 内置分类（updatedAt=0）各设备本来就一致，不需要上传。
    await db.update('records', {'dirty': 1}, where: 'updated_at > 0');
  }

  StoredRecord _stored(Map<String, Object?> r) => StoredRecord(
        RecordType.values.byName(r['type'] as String),
        r['id'] as String,
        r['json'] as String,
        r['updated_at'] as int,
        (r['deleted'] as int) == 1,
        (r['dirty'] as int) == 1,
      );

  Future<String?> getKv(String key) async {
    final rows = await db.query('kv', where: 'key = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setKv(String key, String? value) async {
    if (value == null) {
      await db.delete('kv', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<Map<String, String>> kvWithPrefix(String prefix) async {
    final rows = await db.query('kv', where: 'key LIKE ?', whereArgs: ['$prefix%']);
    return {for (final r in rows) (r['key'] as String).substring(prefix.length): r['value'] as String};
  }

  Future<void> close() => db.close();
}
