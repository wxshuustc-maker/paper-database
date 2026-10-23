import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../data/database.dart';
import '../models.dart';
import 'webdav.dart';

class SyncReport {
  int pulled = 0;
  int pushed = 0;
  int filesUp = 0;
  int filesDown = 0;
  final List<String> errors = [];

  @override
  String toString() {
    final s = '下载 $pulled 条、上传 $pushed 条记录，上传 $filesUp 个、下载 $filesDown 个 PDF';
    return errors.isEmpty ? s : '$s；${errors.length} 个错误：${errors.first}';
  }
}

/// 双向同步引擎。
///
/// 远端目录结构：
/// ```
/// <root>/records/<type>/<id>.json   每条记录一个 JSON 文件
/// <root>/files/<sha256>.pdf          PDF 原文件（按内容哈希命名，天然去重）
/// ```
/// 每条记录按 updatedAt "后写入者胜出"。本地记录了每个远端文件上次看到的版本号，
/// 只下载有变化的文件，只上传本地标记为 dirty 的记录。
class SyncEngine {
  final LocalDatabase db;
  final RemoteStore remote;
  final String root;

  /// 本地 PDF 所在目录。
  final Directory filesDir;
  final bool syncFiles;

  SyncEngine({
    required this.db,
    required this.remote,
    required this.filesDir,
    this.root = 'PaperLibrary',
    this.syncFiles = true,
  });

  static const _types = [RecordType.category, RecordType.paper, RecordType.annotation, RecordType.ink];

  String _dir(RecordType t) => '$root/records/${t.name}';
  String _kvPrefix(RecordType t) => 'sync.v.${t.name}/';

  Future<SyncReport> run({void Function(String)? onProgress}) async {
    final report = SyncReport();
    for (final t in _types) {
      onProgress?.call('同步${_label(t)}…');
      await remote.ensureDir(_dir(t));
      await _syncType(t, report);
    }
    if (syncFiles) {
      onProgress?.call('同步 PDF 文件…');
      await _syncFiles(report);
    }
    await db.setKv('sync.lastSuccess', DateTime.now().toIso8601String());
    return report;
  }

  Future<void> _syncType(RecordType type, SyncReport report) async {
    final dir = _dir(type);
    final known = await db.kvWithPrefix(_kvPrefix(type));
    final remoteEntries = {
      for (final e in await remote.list(dir))
        if (!e.isDir && e.name.endsWith('.json')) e.name.substring(0, e.name.length - 5): e.version,
    };

    // 1. 拉取远端有变化的记录。
    for (final MapEntry(key: id, value: version) in remoteEntries.entries) {
      if (known[id] == version) continue;
      try {
        final bytes = await remote.get('$dir/$id.json');
        final incoming = recordFromString(type, utf8.decode(bytes));
        final local = await db.getStored(type, id);
        if (local == null || incoming.updatedAt > local.updatedAt) {
          await db.put(type, incoming, dirty: false);
          report.pulled++;
        } else if (incoming.updatedAt == local.updatedAt && local.dirty) {
          await db.markClean(type, id, local.updatedAt);
        }
        await db.setKv('${_kvPrefix(type)}$id', version);
      } catch (e) {
        report.errors.add('下载 $type/$id 失败：$e');
      }
    }

    // 2. 推送本地修改。
    final pushedWithoutVersion = <String>[];
    for (final rec in await db.dirty(type)) {
      try {
        final version = await remote.put('$dir/${rec.id}.json', Uint8List.fromList(utf8.encode(rec.json)));
        await db.markClean(type, rec.id, rec.updatedAt);
        if (version != null) {
          await db.setKv('${_kvPrefix(type)}${rec.id}', version);
        } else {
          pushedWithoutVersion.add(rec.id);
        }
        report.pushed++;
      } catch (e) {
        report.errors.add('上传 $type/${rec.id} 失败：$e');
      }
    }

    // 3. 服务器没在 PUT 响应里给 ETag 时，重新列目录记下自己上传后的版本，避免下次重复下载。
    if (pushedWithoutVersion.isNotEmpty) {
      final fresh = {for (final e in await remote.list(dir)) e.name: e.version};
      for (final id in pushedWithoutVersion) {
        final v = fresh['$id.json'];
        if (v != null) await db.setKv('${_kvPrefix(type)}$id', v);
      }
    }
  }

  Future<void> _syncFiles(SyncReport report) async {
    final dir = '$root/files';
    await remote.ensureDir(dir);
    final remoteFiles = {for (final e in await remote.list(dir)) e.name};
    final papers = await db.all<Paper>(RecordType.paper);
    final hashes = papers.map((p) => p.fileHash).whereType<String>().toSet();
    for (final hash in hashes) {
      final name = '$hash.pdf';
      final local = File('${filesDir.path}/$name');
      final localExists = await local.exists();
      try {
        if (localExists && !remoteFiles.contains(name)) {
          await remote.put('$dir/$name', await local.readAsBytes());
          report.filesUp++;
        } else if (!localExists && remoteFiles.contains(name)) {
          final bytes = await remote.get('$dir/$name');
          final tmp = File('${local.path}.part');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(local.path);
          report.filesDown++;
        }
      } catch (e) {
        report.errors.add('同步文件 $name 失败：$e');
      }
    }
  }

  static String _label(RecordType t) => switch (t) {
        RecordType.paper => '论文',
        RecordType.category => '分类',
        RecordType.annotation => '批注',
        RecordType.ink => '手写笔记',
      };
}
