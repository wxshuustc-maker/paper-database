import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

class RemoteEntry {
  final String name;
  final bool isDir;

  /// 用于判断远端文件是否变化：优先 ETag，否则用修改时间+大小。
  final String version;
  const RemoteEntry(this.name, this.isDir, this.version);
}

class WebDavException implements Exception {
  final int statusCode;
  final String message;
  WebDavException(this.statusCode, this.message);
  @override
  String toString() => switch (statusCode) {
        401 => 'WebDAV 认证失败，请检查账号和密码（坚果云需使用"应用密码"）',
        403 => 'WebDAV 拒绝访问（403），请检查目录权限',
        404 => 'WebDAV 路径不存在（404）：$message',
        _ => 'WebDAV 错误 $statusCode：$message',
      };
}

/// 远端存储接口，方便测试时替换成内存实现。
abstract class RemoteStore {
  /// 列出目录下的文件（不含目录本身）。目录不存在时返回空列表。
  Future<List<RemoteEntry>> list(String dir);
  Future<Uint8List> get(String path);

  /// 上传文件，返回新版本号（服务器没给时返回 null）。
  Future<String?> put(String path, Uint8List data);
  Future<void> ensureDir(String dir);
}

/// 精简的 WebDAV 客户端，只实现同步需要的 PROPFIND / GET / PUT / MKCOL。
/// 兼容坚果云、Nextcloud、群晖/威联通 NAS 等常见实现。
class WebDavClient implements RemoteStore {
  final Uri base;
  final String username;
  final String password;
  final http.Client _http;

  WebDavClient(String url, this.username, this.password, {http.Client? client})
      : base = Uri.parse(url.endsWith('/') ? url : '$url/'),
        _http = client ?? http.Client();

  Map<String, String> get _auth =>
      {'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}'};

  Uri _uri(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).map(Uri.encodeComponent).join('/');
    return base.resolve(segments + (path.endsWith('/') ? '/' : ''));
  }

  Future<http.StreamedResponse> _send(String method, String path,
      {Map<String, String>? headers, List<int>? body}) async {
    final req = http.Request(method, _uri(path))
      ..headers.addAll(_auth)
      ..headers.addAll(headers ?? {});
    if (body != null) req.bodyBytes = body;
    return _http.send(req).timeout(const Duration(seconds: 60));
  }

  static const _propfindBody = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/><d:getetag/><d:getlastmodified/><d:getcontentlength/>'
      '</d:prop></d:propfind>';

  @override
  Future<List<RemoteEntry>> list(String dir) async {
    final path = dir.endsWith('/') ? dir : '$dir/';
    final res = await _send('PROPFIND', path,
        headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
        body: utf8.encode(_propfindBody));
    if (res.statusCode == 404) return [];
    final body = await res.stream.bytesToString();
    if (res.statusCode != 207 && res.statusCode != 200) {
      throw WebDavException(res.statusCode, path);
    }
    return parseMultiStatus(body, _uri(path).path);
  }

  /// 解析 PROPFIND 的 207 Multi-Status 响应。公开出来便于单元测试。
  static List<RemoteEntry> parseMultiStatus(String xml, String selfPath) {
    final doc = XmlDocument.parse(xml);
    final out = <RemoteEntry>[];
    String norm(String p) => Uri.decodeFull(p).replaceAll(RegExp(r'/+$'), '');
    final self = norm(selfPath);
    for (final resp in doc.findAllElements('response', namespaceUri: 'DAV:')) {
      final href = resp.findElements('href', namespaceUri: 'DAV:').firstOrNull?.innerText ?? '';
      final hrefPath = norm(Uri.tryParse(href)?.path ?? href);
      if (hrefPath == self || hrefPath.isEmpty) continue;
      final isDir = resp.findAllElements('collection', namespaceUri: 'DAV:').isNotEmpty;
      String prop(String name) =>
          resp.findAllElements(name, namespaceUri: 'DAV:').firstOrNull?.innerText.trim() ?? '';
      final etag = prop('getetag').replaceAll('"', '');
      final version = etag.isNotEmpty ? etag : '${prop('getlastmodified')}|${prop('getcontentlength')}';
      out.add(RemoteEntry(hrefPath.split('/').last, isDir, version));
    }
    return out;
  }

  @override
  Future<Uint8List> get(String path) async {
    final res = await _send('GET', path);
    final bytes = await res.stream.toBytes();
    if (res.statusCode != 200) throw WebDavException(res.statusCode, path);
    return bytes;
  }

  @override
  Future<String?> put(String path, Uint8List data) async {
    final res = await _send('PUT', path, headers: {'Content-Type': 'application/octet-stream'}, body: data);
    await res.stream.drain<void>();
    if (res.statusCode < 200 || res.statusCode >= 300) throw WebDavException(res.statusCode, path);
    final etag = res.headers['etag'];
    return etag?.replaceAll('"', '');
  }

  @override
  Future<void> ensureDir(String dir) async {
    // 逐级创建，已存在时服务器返回 405，忽略即可。
    final parts = dir.split('/').where((s) => s.isNotEmpty).toList();
    for (var i = 1; i <= parts.length; i++) {
      final p = '${parts.sublist(0, i).join('/')}/';
      final res = await _send('MKCOL', p);
      await res.stream.drain<void>();
      if (res.statusCode == 401) throw WebDavException(401, p);
    }
  }

  /// 测试连接：列出根目录。
  Future<void> test() async {
    final res = await _send('PROPFIND', '',
        headers: {'Depth': '0', 'Content-Type': 'application/xml; charset=utf-8'},
        body: utf8.encode(_propfindBody));
    await res.stream.drain<void>();
    if (res.statusCode != 207 && res.statusCode != 200) throw WebDavException(res.statusCode, base.toString());
  }
}
