import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/library.dart';
import 'sync_engine.dart';
import 'webdav.dart';

/// WebDAV 设置。保存在本地数据库的 kv 表里，不参与同步。
class SyncSettings {
  String url = '';
  String username = '';
  String password = '';
  String folder = 'PaperLibrary';
  bool syncFiles = true;
  bool autoSync = true;

  bool get configured => url.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}

/// 管理同步时机：启动时、本地修改后 20 秒、以及每 10 分钟各同步一次。
class SyncService extends ChangeNotifier {
  final Library library;
  final SyncSettings settings = SyncSettings();

  bool syncing = false;
  String status = '尚未同步';
  String progress = '';
  DateTime? lastSuccess;

  Timer? _debounce;
  Timer? _periodic;
  bool _pendingRerun = false;

  SyncService(this.library);

  Future<void> load() async {
    final db = library.db;
    settings
      ..url = await db.getKv('webdav.url') ?? ''
      ..username = await db.getKv('webdav.user') ?? ''
      ..password = await db.getKv('webdav.pass') ?? ''
      ..folder = await db.getKv('webdav.folder') ?? 'PaperLibrary'
      ..syncFiles = (await db.getKv('webdav.syncFiles') ?? '1') == '1'
      ..autoSync = (await db.getKv('webdav.autoSync') ?? '1') == '1';
    final last = await db.getKv('sync.lastSuccess');
    if (last != null) {
      lastSuccess = DateTime.tryParse(last);
      status = '上次同步：${_fmt(lastSuccess!)}';
    }
    library.onLocalChange = _scheduleAfterEdit;
    _periodic = Timer.periodic(const Duration(minutes: 10), (_) => _auto());
    _auto();
  }

  Future<void> save() async {
    final db = library.db;
    await db.setKv('webdav.url', settings.url.trim());
    await db.setKv('webdav.user', settings.username.trim());
    await db.setKv('webdav.pass', settings.password);
    await db.setKv('webdav.folder', settings.folder.trim().isEmpty ? 'PaperLibrary' : settings.folder.trim());
    await db.setKv('webdav.syncFiles', settings.syncFiles ? '1' : '0');
    await db.setKv('webdav.autoSync', settings.autoSync ? '1' : '0');
    notifyListeners();
  }

  WebDavClient _client() => WebDavClient(settings.url.trim(), settings.username.trim(), settings.password);

  Future<String> testConnection() async {
    try {
      await _client().test();
      return '连接成功';
    } catch (e) {
      return '连接失败：$e';
    }
  }

  void _scheduleAfterEdit() {
    if (!settings.configured || !settings.autoSync) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), _auto);
  }

  void _auto() {
    if (settings.configured && settings.autoSync) syncNow();
  }

  Future<SyncReport?> syncNow() async {
    if (!settings.configured) {
      status = '未配置 WebDAV';
      notifyListeners();
      return null;
    }
    if (syncing) {
      _pendingRerun = true;
      return null;
    }
    syncing = true;
    status = '正在同步…';
    notifyListeners();
    SyncReport? report;
    try {
      final engine = SyncEngine(
        db: library.db,
        remote: _client(),
        filesDir: library.filesDir,
        root: settings.folder.trim().isEmpty ? 'PaperLibrary' : settings.folder.trim(),
        syncFiles: settings.syncFiles,
      );
      report = await engine.run(onProgress: (s) {
        progress = s;
        notifyListeners();
      });
      lastSuccess = DateTime.now();
      status = report.errors.isEmpty ? '已同步 ${_fmt(lastSuccess!)}' : '同步完成但有错误：${report.errors.first}';
      if (report.pulled > 0 || report.filesDown > 0) await library.reload();
    } catch (e) {
      status = '同步失败：$e';
    } finally {
      syncing = false;
      progress = '';
      notifyListeners();
    }
    if (_pendingRerun) {
      _pendingRerun = false;
      unawaited(syncNow());
    }
    return report;
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    super.dispose();
  }
}
