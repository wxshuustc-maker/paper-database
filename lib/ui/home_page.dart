import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library.dart';
import '../models.dart';
import 'app_scope.dart';
import 'category_widgets.dart';
import 'paper_detail_page.dart';
import 'reader_page.dart';
import 'settings_page.dart';

enum SortBy { added, year, title }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _category;
  String _query = '';
  SortBy _sort = SortBy.added;
  ReadStatus? _status;
  bool _importing = false;

  List<Paper> _visible(Library lib) {
    Iterable<Paper> list = lib.papers;
    if (_category != null) {
      final ids = lib.descendantIds(_category!);
      list = list.where((p) => ids.contains(p.categoryId));
    }
    if (_status != null) list = list.where((p) => p.readStatus == _status);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) => [p.title, p.authors.join(' '), p.abstract, p.keywords.join(' '), p.note, p.venue, p.doi]
          .any((f) => f.toLowerCase().contains(q)));
    }
    final out = list.toList();
    switch (_sort) {
      case SortBy.added:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case SortBy.year:
        out.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
      case SortBy.title:
        out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    }
    return out;
  }

  Future<void> _import(Library lib) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: '选择要导入的论文 PDF',
    );
    if (res.isEmpty || !mounted) return;
    setState(() => _importing = true);
    final messenger = ScaffoldMessenger.of(context);
    var ok = 0, dup = 0;
    Paper? last;
    for (final f in res) {
      if (f.path == null) continue;
      try {
        final r = await lib.importPdf(f.path!);
        if (r.duplicate) {
          dup++;
        } else {
          ok++;
          last = r.paper;
        }
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('导入 ${f.name} 失败：$e')));
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    if (ok == 1 && last != null) {
      final paper = last;
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('已导入《${paper.title}》，归入：${lib.categoryPath(paper.categoryId)}'),
        action: SnackBarAction(
          label: '修改分类',
          onPressed: () async {
            final current = lib.papers.firstWhere((p) => p.id == paper.id, orElse: () => paper);
            final id = await pickCategory(context, lib, current);
            if (id != null) await lib.setCategory(current, id);
          },
        ),
      ));
    } else if (ok + dup > 0) {
      messenger.showSnackBar(SnackBar(content: Text('导入 $ok 篇${dup > 0 ? '，$dup 篇已存在被跳过' : ''}，已自动分类')));
    }
  }

  Future<void> _addManual(Library lib) async {
    final title = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('手动添加论文'),
        content: TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: '标题')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('添加')),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty || !mounted) return;
    final paper = await lib.addManual(title: title.text.trim());
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PaperDetailPage(paperId: paper.id)));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final lib = scope.library;
    return ListenableBuilder(
      listenable: Listenable.merge([lib, scope.sync]),
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 840;
        final tree = CategoryTree(
          library: lib,
          selected: _category,
          onSelect: (id) {
            setState(() => _category = id);
            if (!wide) Navigator.maybePop(context);
          },
        );
        final papers = _visible(lib);
        final title = _category == null ? '全部论文' : lib.categoryPath(_category!);
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              _SyncButton(),
              PopupMenuButton<SortBy>(
                tooltip: '排序',
                icon: const Icon(Icons.sort),
                initialValue: _sort,
                onSelected: (v) => setState(() => _sort = v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: SortBy.added, child: Text('按导入时间')),
                  PopupMenuItem(value: SortBy.year, child: Text('按年份')),
                  PopupMenuItem(value: SortBy.title, child: Text('按标题')),
                ],
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
            ],
          ),
          drawer: wide ? null : Drawer(child: SafeArea(child: tree)),
          floatingActionButton: _importing
              ? const FloatingActionButton(onPressed: null, child: CircularProgressIndicator())
              : FloatingActionButton.extended(
                  onPressed: () => _import(lib),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('导入 PDF'),
                ),
          body: Row(children: [
            if (wide) SizedBox(width: 280, child: Material(color: Theme.of(context).colorScheme.surfaceContainerLow, child: tree)),
            Expanded(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: '搜索标题、作者、摘要、关键词、笔记',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(tooltip: '手动添加', onPressed: () => _addManual(lib), icon: const Icon(Icons.note_add_outlined)),
                  ]),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    for (final s in [null, ...ReadStatus.values])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(s == null ? '全部' : readStatusLabel(s)),
                          selected: _status == s,
                          onSelected: (_) => setState(() => _status = s),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text('${papers.length} 篇', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                Expanded(
                  child: papers.isEmpty
                      ? _Empty(hasAny: lib.papers.isNotEmpty)
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: papers.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, i) => _PaperTile(lib: lib, paper: papers[i]),
                        ),
                ),
              ]),
            ),
          ]),
        );
      },
    );
  }
}

String readStatusLabel(ReadStatus s) => switch (s) {
      ReadStatus.unread => '未读',
      ReadStatus.reading => '在读',
      ReadStatus.read => '已读',
    };

class _PaperTile extends StatelessWidget {
  final Library lib;
  final Paper paper;
  const _PaperTile({required this.lib, required this.paper});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = [
      if (paper.authors.isNotEmpty) paper.authors.length > 3 ? '${paper.authors.take(3).join(', ')} 等' : paper.authors.join(', '),
      if (paper.year != null) '${paper.year}',
      if (paper.venue.isNotEmpty) paper.venue,
    ].join(' · ');
    return ListTile(
      leading: Icon(
        switch (paper.readStatus) {
          ReadStatus.unread => Icons.circle_outlined,
          ReadStatus.reading => Icons.timelapse,
          ReadStatus.read => Icons.check_circle,
        },
        color: paper.readStatus == ReadStatus.read ? theme.colorScheme.primary : null,
      ),
      title: Text(paper.title.isEmpty ? '（无标题）' : paper.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (meta.isNotEmpty) Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _Tag(lib.categoryPath(paper.categoryId), theme.colorScheme.primaryContainer),
          for (final k in paper.keywords.take(3)) _Tag(k, theme.colorScheme.surfaceContainerHighest),
        ]),
      ]),
      isThreeLine: true,
      trailing: paper.fileHash == null
          ? null
          : IconButton(
              tooltip: '阅读',
              icon: Icon(lib.hasLocalFile(paper) ? Icons.menu_book_outlined : Icons.cloud_download_outlined),
              onPressed: lib.hasLocalFile(paper)
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(paperId: paper.id)))
                  : () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('PDF 还没有同步到这台设备，请先同步'))),
            ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaperDetailPage(paperId: paper.id))),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );
}

class _Empty extends StatelessWidget {
  final bool hasAny;
  const _Empty({required this.hasAny});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_stories_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(hasAny ? '没有符合条件的论文' : '还没有论文。点击右下角"导入 PDF"，会自动识别摘要和关键词并归类。',
                textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _SyncButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final sync = AppScope.of(context).sync;
    return IconButton(
      tooltip: sync.syncing ? (sync.progress.isEmpty ? '正在同步…' : sync.progress) : sync.status,
      onPressed: sync.syncing
          ? null
          : () async {
              if (!sync.settings.configured) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
                return;
              }
              final messenger = ScaffoldMessenger.of(context);
              final r = await sync.syncNow();
              messenger.showSnackBar(SnackBar(content: Text(r?.toString() ?? sync.status)));
            },
      icon: sync.syncing
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(sync.settings.configured ? Icons.cloud_sync_outlined : Icons.cloud_off_outlined),
    );
  }
}
