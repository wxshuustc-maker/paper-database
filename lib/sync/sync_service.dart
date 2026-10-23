import 'dart:async';

import 'package:flutter/foundation.dart';

import 'dart:convert';

import '../data/library.dart';
import '../security/secret_store.dart';
import 'sync_cipher.dart';
import 'sync_engine.dart';
import 'webdav.dart';

/// WebDAV 设置。地址等保存在本地数据库，密码和加密密钥保存在系统安全存储；都不参与同步。
class SyncSettings {
  String url = '';
  String username = '';
  String password = '';
  String folder = 'PaperLibrary';
  bool syncFiles = true;
  bool autoSync = true;

  /// 是否启用端到端加密。
  bool e2e = false;

  bool get configured => url.isNotEmpty && username.isNotEmpty && password.isNotEmpty;
}

/// 管理同步时机：启动时、本地修改后 20 秒、以及每 10 分钟各同步一次。
class SyncService extends ChangeNotifier {
  final Library library;
  final SecretStore secrets;
  final SyncSettings settings = SyncSettings();
  SyncCipher? _cipher;

  bool syncing = false;
  String status = '尚未同步';
  String progress = '';
  DateTime? lastSuccess;

  Timer? _debounce;
  Timer? _periodic;
  bool _pendingRerun = false;

  SyncService(this.library, this.secrets);

  String get _folder => settings.folder.trim().isEmpty ? 'PaperLibrary' : settings.folder.trim();

  Future<void> load() async {
    final db = library.db;
    // 旧版本把密码明文存在数据库里，迁移到安全存储。
    await secrets.migrateFromKv('webdav.pass', 'webdav.pass');
    settings
      ..url = await db.getKv('webdav.url') ?? ''
      ..username = await db.getKv('webdav.user') ?? ''
      ..password = await secrets.read('webdav.pass') ?? ''
      ..e2e = (await db.getKv('e2e.enabled')) == '1'
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
    await secrets.write('webdav.pass', settings.password);
    await db.setKv('webdav.folder', settings.folder.trim().isEmpty ? 'PaperLibrary' : settings.folder.trim());
    await db.setKv('webdav.syncFiles', settings.syncFiles ? '1' : '0');
    await db.setKv('webdav.autoSync', settings.autoSync ? '1' : '0');
    notifyListeners();
  }

  /// 启用端到端加密。第一台设备会在云端创建加密参数；其他设备需输入相同的同步密码。
  /// 成功后把全部数据加密上传一遍。
  Future<String> enableEncryption(String passphrase) async {
    if (!settings.configured) return '请先填写 WebDAV 账号';
    if (passphrase.length < 8) return '同步密码至少 8 位';
    try {
      status = '正在派生加密密钥…';
      notifyListeners();
      final cipher = await SyncCipher.setupRemote(_client(), '$_folder/e2e', passphrase);
      await secrets.write('e2e.key', base64Encode(cipher.rawKey));
      _cipher = cipher;
      settings.e2e = true;
      await library.db.setKv('e2e.enabled', '1');
      await library.db.markAllDirty();
      final r = await syncNow();
      return '已启用端到端加密。${r ?? status}';
    } on WrongPassphraseException catch (e) {
      status = e.toString();
      notifyListeners();
      return e.toString();
    } catch (e) {
      status = '启用加密失败：$e';
      notifyListeners();
      return status;
    }
  }

  Future<String> disableEncryption() async {
    await secrets.write('e2e.key', null);
    _cipher = null;
    settings.e2e = false;
    await library.db.setKv('e2e.enabled', '0');
    await library.db.markAllDirty();
    final r = await syncNow();
    return '已关闭端到端加密，数据改为明文同步。${r ?? status}';
  }

  /// 删除云端旧的明文数据（启用加密前同步上去的）。
  Future<String> deletePlainRemoteData() async {
    try {
      final c = _client();
      await c.delete('$_folder/records/');
      await c.delete('$_folder/files/');
      return '已删除云端的明文数据，现在云端只有加密数据';
    } catch (e) {
      return '删除失败：$e';
    }
  }

  Future<SyncCipher?> _loadCipher() async {
    if (!settings.e2e) return null;
    if (_cipher != null) return _cipher;
    final raw = await secrets.read('e2e.key');
    if (raw == null) return null;
    return _cipher = SyncCipher.fromRawKey(base64Decode(raw));
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
    final cipher = await _loadCipher();
    if (settings.e2e && cipher == null) {
      status = '已启用加密，但本机没有密钥，请在设置中重新输入同步密码';
      notifyListeners();
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
        root: _folder,
        syncFiles: settings.syncFiles,
        cipher: cipher,
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
