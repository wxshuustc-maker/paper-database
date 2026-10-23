import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/database.dart';

/// 保存密码、密钥等敏感信息。
///
/// 优先使用系统安全存储：安卓 Keystore、Windows 凭据管理器、macOS 钥匙串、
/// Linux Secret Service（GNOME 钥匙环 / KWallet）。
/// 只有在系统不提供安全存储时（例如没有钥匙环服务的 Linux）才退回本地数据库，
/// 此时 [secure] 为 false，设置页会提示用户。
class SecretStore {
  final LocalDatabase db;
  final FlutterSecureStorage? _storage;
  bool secure;

  SecretStore._(this.db, this._storage, this.secure);

  static const _prefix = 'secret.';

  static Future<SecretStore> open(LocalDatabase db, {bool useSystemStore = true}) async {
    if (!useSystemStore) return SecretStore._(db, null, false);
    final storage = FlutterSecureStorage(
      // 不启用 Keychain Sharing，避免 macOS 版需要开发者证书描述文件。
      mOptions: Platform.isMacOS ? const MacOsOptions(usesDataProtectionKeychain: false) : MacOsOptions.defaultOptions,
    );
    try {
      // 写读一次，确认系统安全存储可用。
      await storage.write(key: 'paper_library.probe', value: '1');
      final ok = await storage.read(key: 'paper_library.probe') == '1';
      if (ok) return SecretStore._(db, storage, true);
    } catch (e) {
      debugPrint('系统安全存储不可用，改用本地数据库: $e');
    }
    return SecretStore._(db, null, false);
  }

  Future<String?> read(String key) async {
    if (_storage != null) {
      try {
        return await _storage.read(key: 'paper_library.$key');
      } catch (e) {
        debugPrint('读取安全存储失败: $e');
        return null;
      }
    }
    return db.getKv('$_prefix$key');
  }

  Future<void> write(String key, String? value) async {
    if (_storage != null) {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: 'paper_library.$key');
      } else {
        await _storage.write(key: 'paper_library.$key', value: value);
      }
      return;
    }
    await db.setKv('$_prefix$key', value == null || value.isEmpty ? null : value);
  }

  /// 把旧版本以明文存在数据库里的值搬进安全存储，并从数据库删除。
  Future<void> migrateFromKv(String kvKey, String secretKey) async {
    final old = await db.getKv(kvKey);
    if (old == null) return;
    if (await read(secretKey) == null) await write(secretKey, old);
    if (secure) await db.setKv(kvKey, null);
  }
}
