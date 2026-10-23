import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import 'webdav.dart';

class WrongPassphraseException implements Exception {
  @override
  String toString() => '同步密码不正确（与其他设备设置的不一致）';
}

/// 端到端加密：数据在本机用 AES-256-GCM 加密后再上传，WebDAV 服务器只能看到密文。
///
/// 密钥由用户的"同步密码"经 PBKDF2-SHA256 派生，盐值保存在远端的 crypto.json 里，
/// 所以每台设备输入同一个同步密码就能得到同一把密钥。密码本身从不上传。
/// 远端文件名也用 HMAC 处理过，服务器无法从文件名得知论文 ID 或 PDF 的哈希。
class SyncCipher {
  final SecretKey _encKey;
  final List<int> _macKey;
  final List<int> rawKey;

  SyncCipher._(this.rawKey)
      : _encKey = SecretKey(rawKey.sublist(0, 32)),
        _macKey = rawKey.sublist(32, 64);

  static final _aes = AesGcm.with256bits();
  static const _magic = [0x50, 0x4C, 0x45, 0x31]; // "PLE1"
  static const _checkPlain = 'paper-library-key-check';
  static const defaultIterations = 200000;

  /// 从缓存的密钥（本机安全存储里）恢复，避免每次启动都重新派生。
  factory SyncCipher.fromRawKey(List<int> raw) => SyncCipher._(raw);

  static Future<SyncCipher> derive(String passphrase, List<int> salt, int iterations) async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 512);
    final key = await kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
    return SyncCipher._(await key.extractBytes());
  }

  Future<Uint8List> encrypt(List<int> plain) async {
    final box = await _aes.encrypt(plain, secretKey: _encKey);
    return Uint8List.fromList([..._magic, ...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> decrypt(List<int> data) async {
    if (data.length < 4 + 12 + 16 || !_startsWithMagic(data)) {
      throw const FormatException('不是加密数据');
    }
    final nonce = data.sublist(4, 16);
    final mac = Mac(data.sublist(data.length - 16));
    final cipherText = data.sublist(16, data.length - 16);
    final plain = await _aes.decrypt(SecretBox(cipherText, nonce: nonce, mac: mac), secretKey: _encKey);
    return Uint8List.fromList(plain);
  }

  static bool _startsWithMagic(List<int> d) =>
      d[0] == _magic[0] && d[1] == _magic[1] && d[2] == _magic[2] && d[3] == _magic[3];

  /// 远端文件名：HMAC(密钥, 原名)，固定且不可逆。
  String nameFor(String original) =>
      hash.Hmac(hash.sha256, _macKey).convert(utf8.encode(original)).toString().substring(0, 40);

  /// 连接远端：已有 crypto.json 时用其中的盐值派生密钥并校验密码；
  /// 没有时（第一台启用加密的设备）创建它。
  static Future<SyncCipher> setupRemote(RemoteStore remote, String dir, String passphrase) async {
    await remote.ensureDir(dir);
    final path = '$dir/crypto.json';
    final exists = (await remote.list(dir)).any((e) => e.name == 'crypto.json');
    if (exists) {
      final meta = jsonDecode(utf8.decode(await remote.get(path))) as Map<String, dynamic>;
      final cipher = await derive(passphrase, base64Decode(meta['salt'] as String), meta['iterations'] as int);
      try {
        final check = utf8.decode(await cipher.decrypt(base64Decode(meta['check'] as String)));
        if (check != _checkPlain) throw WrongPassphraseException();
      } on SecretBoxAuthenticationError {
        throw WrongPassphraseException();
      }
      return cipher;
    }
    final salt = SecretKeyData.random(length: 16).bytes;
    final cipher = await derive(passphrase, salt, defaultIterations);
    final meta = {
      'version': 1,
      'kdf': 'pbkdf2-sha256',
      'cipher': 'aes-256-gcm',
      'iterations': defaultIterations,
      'salt': base64Encode(salt),
      'check': base64Encode(await cipher.encrypt(utf8.encode(_checkPlain))),
    };
    await remote.put(path, Uint8List.fromList(utf8.encode(jsonEncode(meta))));
    return cipher;
  }
}
