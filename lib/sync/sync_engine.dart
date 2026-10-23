import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../data/database.dart';
import '../models.dart';
import 'sync_cipher.dart';
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
/// 传入 [cipher] 时启用端到端加密：所有数据放在 `<root>/e2e/` 下，内容加密、文件名经 HMAC 处理。
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
  final SyncCipher? cipher;

  SyncEngine({
    required this.db,
    required this.remote,
    required this.filesDir,
    String root = 'PaperLibrary',
    this.syncFiles = true,
    this.cipher,
  }) : root = cipher == null ? root : '$root/e2e';

  static const _types = [RecordType.category, RecordType.paper, RecordType.annotation, RecordType.ink];

  String _dir(RecordType t) => '$root/records/${t.name}';
  // 已知远端版本按"远端文件名（去掉扩展名）"记录；明文和加密模式分开记。
  String _kvPrefix(RecordType t) => cipher == null ? 'sync.v.${t.name}/' : 'sync.e.${t.name}/';
  String get _ext => cipher == null ? '.json' : '.enc';
  String _remoteName(RecordType t, String id) => cipher == null ? id : cipher!.nameFor('${t.name}/$id');
  String _remoteFileName(String hash) => cipher == null ? '$hash.pdf' : '${cipher!.nameFor('file/$hash')}.bin';

  Future<Uint8List> _encode(Uint8List plain) async => cipher == null ? plain : await cipher!.encrypt(plain);
  Future<Uint8List> _decode(Uint8List data) async => cipher == null ? data : await cipher!.decrypt(data);

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
        if (!e.isDir && e.name.endsWith(_ext)) e.name.substring(0, e.name.length - _ext.length): e.version,
    };

    // 1. 拉取远端有变化的记录。
    for (final MapEntry(key: name, value: version) in remoteEntries.entries) {
      if (known[name] == version) continue;
      try {
        final bytes = await _decode(await remote.get('$dir/$name$_ext'));
        final incoming = recordFromString(type, utf8.decode(bytes));
        final local = await db.getStored(type, incoming.id);
        if (local == null || incoming.updatedAt > local.updatedAt) {
          await db.put(type, incoming, dirty: false);
          report.pulled++;
        } else if (incoming.updatedAt == local.updatedAt && local.dirty) {
          await db.markClean(type, incoming.id, local.updatedAt);
        }
        await db.setKv('${_kvPrefix(type)}$name', version);
      } catch (e) {
        report.errors.add('下载 ${type.name}/$name 失败：$e');
      }
    }

    // 2. 推送本地修改。
    final pushedWithoutVersion = <String>[];
    for (final rec in await db.dirty(type)) {
      final name = _remoteName(type, rec.id);
      try {
        final body = await _encode(Uint8List.fromList(utf8.encode(rec.json)));
        final version = await remote.put('$dir/$name$_ext', body);
        await db.markClean(type, rec.id, rec.updatedAt);
        if (version != null) {
          await db.setKv('${_kvPrefix(type)}$name', version);
        } else {
          pushedWithoutVersion.add(name);
        }
        report.pushed++;
      } catch (e) {
        report.errors.add('上传 ${type.name}/${rec.id} 失败：$e');
      }
    }

    // 3. 服务器没在 PUT 响应里给 ETag 时，重新列目录记下自己上传后的版本，避免下次重复下载。
    if (pushedWithoutVersion.isNotEmpty) {
      final fresh = {for (final e in await remote.list(dir)) e.name: e.version};
      for (final name in pushedWithoutVersion) {
        final v = fresh['$name$_ext'];
        if (v != null) await db.setKv('${_kvPrefix(type)}$name', v);
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
      final name = _remoteFileName(hash);
      final local = File('${filesDir.path}/$hash.pdf');
      final localExists = await local.exists();
      try {
        if (localExists && !remoteFiles.contains(name)) {
          await remote.put('$dir/$name', await _encode(await local.readAsBytes()));
          report.filesUp++;
        } else if (!localExists && remoteFiles.contains(name)) {
          final bytes = await _decode(await remote.get('$dir/$name'));
          // 校验内容哈希，防止文件损坏或被篡改。
          if (sha256.convert(bytes).toString() != hash) throw const FormatException('文件校验失败');
          final tmp = File('${local.path}.part');
          await tmp.writeAsBytes(bytes, flush: true);
          await tmp.rename(local.path);
          report.filesDown++;
        }
      } catch (e) {
        report.errors.add('同步文件 $hash 失败：$e');
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
