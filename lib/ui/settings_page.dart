import 'package:flutter/material.dart';

import 'app_scope.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url, _user, _pass, _folder;
  bool _syncFiles = true, _autoSync = true, _showPass = false, _busy = false;
  String? _message;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final s = AppScope.of(context).sync.settings;
    _url = TextEditingController(text: s.url);
    _user = TextEditingController(text: s.username);
    _pass = TextEditingController(text: s.password);
    _folder = TextEditingController(text: s.folder);
    _syncFiles = s.syncFiles;
    _autoSync = s.autoSync;
  }

  Future<void> _apply() async {
    final sync = AppScope.of(context).sync;
    sync.settings
      ..url = _url.text.trim()
      ..username = _user.text.trim()
      ..password = _pass.text
      ..folder = _folder.text.trim()
      ..syncFiles = _syncFiles
      ..autoSync = _autoSync;
    await sync.save();
  }

  Future<void> _run(Future<String> Function() task) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final msg = await task();
    if (mounted) {
      setState(() {
        _busy = false;
        _message = msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text('WebDAV 同步', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '在每台设备上填写同一个 WebDAV 账号即可同步论文、分类、批注、手写笔记和 PDF。\n'
              '坚果云：地址填 https://dav.jianguoyun.com/dav/，密码使用"账户信息 → 安全选项 → 第三方应用管理"里生成的应用密码。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(
                  labelText: '服务器地址', hintText: 'https://dav.jianguoyun.com/dav/', border: OutlineInputBorder()),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextField(controller: _user, decoration: const InputDecoration(labelText: '账号', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: !_showPass,
              decoration: InputDecoration(
                labelText: '密码 / 应用密码',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPass = !_showPass),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _folder,
              decoration: const InputDecoration(
                  labelText: '远端文件夹', helperText: '数据保存在 WebDAV 根目录下的这个文件夹里', border: OutlineInputBorder()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('同步 PDF 原文件'),
              subtitle: const Text('关闭后只同步元数据和笔记，节省空间和流量'),
              value: _syncFiles,
              onChanged: (v) => setState(() => _syncFiles = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自动同步'),
              subtitle: const Text('启动时、修改后约 20 秒、以及每 10 分钟自动同步'),
              value: _autoSync,
              onChanged: (v) => setState(() => _autoSync = v),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await _apply();
                          return scope.sync.testConnection();
                        }),
                child: const Text('保存并测试连接'),
              ),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          await _apply();
                          final r = await scope.sync.syncNow();
                          return r?.toString() ?? scope.sync.status;
                        }),
                child: const Text('保存并立即同步'),
              ),
            ]),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_message != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_message!)),
            ListenableBuilder(
              listenable: scope.sync,
              builder: (context, _) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(scope.sync.status, style: theme.textTheme.bodySmall),
              ),
            ),
            const Divider(height: 40),
            Text('自动分类', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '导入时根据标题、摘要、关键词与各分类关键词的匹配度自动归类；arXiv 论文直接使用 arXiv 学科。'
              '手动修改过分类的论文会被记住，并用来改进后续分类。长按左侧分类可编辑它的关键词。',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                          final n = await scope.library.reclassifyAll();
                          return '重新分类完成，$n 篇论文的分类有变化（手动指定的不受影响）';
                        }),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('重新自动分类全部论文'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
