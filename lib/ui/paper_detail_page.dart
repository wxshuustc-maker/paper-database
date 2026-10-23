import 'dart:async';

import 'package:flutter/material.dart';

import '../data/library.dart';
import '../models.dart';
import 'app_scope.dart';
import 'category_widgets.dart';
import 'home_page.dart' show readStatusLabel;
import 'reader_page.dart';

/// 论文详情：编辑元数据、调整分类、查看批注。修改会自动保存。
class PaperDetailPage extends StatefulWidget {
  final String paperId;
  const PaperDetailPage({super.key, required this.paperId});

  @override
  State<PaperDetailPage> createState() => _PaperDetailPageState();
}

class _PaperDetailPageState extends State<PaperDetailPage> {
  late Library _lib;
  late Paper _paper;
  final _c = <String, TextEditingController>{};
  Timer? _saveTimer;
  List<Annotation> _annotations = [];
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _lib = AppScope.of(context).library;
    _paper = _lib.papers.firstWhere((p) => p.id == widget.paperId);
    _c['title'] = TextEditingController(text: _paper.title);
    _c['authors'] = TextEditingController(text: _paper.authors.join(', '));
    _c['year'] = TextEditingController(text: _paper.year?.toString() ?? '');
    _c['venue'] = TextEditingController(text: _paper.venue);
    _c['doi'] = TextEditingController(text: _paper.doi);
    _c['keywords'] = TextEditingController(text: _paper.keywords.join(', '));
    _c['abstract'] = TextEditingController(text: _paper.abstract);
    _c['note'] = TextEditingController(text: _paper.note);
    _loadAnnotations();
  }

  Future<void> _loadAnnotations() async {
    final list = await _lib.annotationsOf(_paper.id);
    if (mounted) setState(() => _annotations = list);
  }

  @override
  void dispose() {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow();
    }
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> _split(String s) =>
      s.split(RegExp(r'[,，;；]')).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), _saveNow);
  }

  void _saveNow() {
    final current = _lib.papers.where((p) => p.id == _paper.id).firstOrNull ?? _paper;
    _paper = current.copyWith(
      title: _c['title']!.text.trim(),
      authors: _split(_c['authors']!.text),
      year: () => int.tryParse(_c['year']!.text.trim()),
      venue: _c['venue']!.text.trim(),
      doi: _c['doi']!.text.trim(),
      keywords: _split(_c['keywords']!.text),
      abstract: _c['abstract']!.text.trim(),
      note: _c['note']!.text,
    );
    _lib.savePaper(_paper);
  }

  Future<void> _changeCategory() async {
    if (_saveTimer?.isActive ?? false) {
      _saveTimer!.cancel();
      _saveNow();
    }
    final id = await pickCategory(context, _lib, _paper);
    if (id == null) return;
    await _lib.setCategory(_paper, id);
    setState(() => _paper = _lib.papers.firstWhere((p) => p.id == _paper.id));
  }

  Future<void> _autoClassify() async {
    _saveTimer?.cancel();
    _saveNow();
    final id = _lib.classifier.classify(_paper, _lib.categories);
    _paper = _paper.copyWith(categoryId: id, categoryManual: false);
    await _lib.savePaper(_paper);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已自动归入：${_lib.categoryPath(id)}')));
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这篇论文？'),
        content: const Text('论文记录、批注和手写笔记都会被删除，并同步到其他设备。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    _saveTimer?.cancel();
    await _lib.deletePaper(_paper);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openReader([int? page]) async {
    _saveTimer?.cancel();
    _saveNow();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ReaderPage(paperId: _paper.id, initialPage: page)));
    _paper = _lib.papers.firstWhere((p) => p.id == _paper.id, orElse: () => _paper);
    _loadAnnotations();
  }

  Widget _field(String key, String label, {int lines = 1, TextInputType? keyboard}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: _c[key],
          minLines: lines,
          maxLines: lines == 1 ? 1 : null,
          keyboardType: keyboard,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), alignLabelWithHint: lines > 1),
          onChanged: (_) => _scheduleSave(),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFile = _paper.fileHash != null;
    final local = _lib.hasLocalFile(_paper);
    final suggestions = _lib.rank(_paper).take(3).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('论文详情'),
        actions: [
          IconButton(tooltip: '删除', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (hasFile)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilledButton.icon(
                  onPressed: local ? () => _openReader() : null,
                  icon: const Icon(Icons.menu_book),
                  label: Text(local ? '阅读 PDF（批注 / 手写笔记）' : 'PDF 尚未同步到本机'),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.folder_outlined),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_lib.categoryPath(_paper.categoryId), style: theme.textTheme.titleMedium)),
                    if (_paper.categoryManual) Text('手动', style: theme.textTheme.labelSmall),
                    TextButton(onPressed: _changeCategory, child: const Text('修改')),
                    TextButton(onPressed: _autoClassify, child: const Text('重新自动分类')),
                  ]),
                  if (suggestions.isNotEmpty)
                    Wrap(spacing: 6, children: [
                      Text('建议：', style: theme.textTheme.bodySmall),
                      for (final s in suggestions)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(s.category.name),
                          onPressed: () async {
                            await _lib.setCategory(_paper, s.category.id);
                            setState(() => _paper = _lib.papers.firstWhere((p) => p.id == _paper.id));
                          },
                        ),
                    ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              SegmentedButton<ReadStatus>(
                segments: [
                  for (final s in ReadStatus.values) ButtonSegment(value: s, label: Text(readStatusLabel(s))),
                ],
                selected: {_paper.readStatus},
                onSelectionChanged: (v) {
                  _paper = _paper.copyWith(readStatus: v.first);
                  _lib.savePaper(_paper);
                  setState(() {});
                },
              ),
              const Spacer(),
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(i <= _paper.rating ? Icons.star : Icons.star_border, color: Colors.amber),
                  onPressed: () {
                    _paper = _paper.copyWith(rating: _paper.rating == i ? 0 : i);
                    _lib.savePaper(_paper);
                    setState(() {});
                  },
                ),
            ]),
            const SizedBox(height: 16),
            _field('title', '标题', lines: 2),
            _field('authors', '作者（逗号分隔）'),
            Row(children: [
              Expanded(child: _field('year', '年份', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(flex: 3, child: _field('venue', '期刊 / 会议')),
            ]),
            _field('doi', 'DOI'),
            _field('keywords', '关键词（逗号分隔）'),
            _field('abstract', '摘要', lines: 6),
            _field('note', '我的笔记', lines: 4),
            const SizedBox(height: 8),
            Text('批注（${_annotations.length}）', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_annotations.isEmpty)
              Text('在阅读器里选中文字，点"添加批注"即可。', style: theme.textTheme.bodySmall)
            else
              for (final a in _annotations)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Color(a.color), child: Text('${a.page}', style: const TextStyle(fontSize: 12, color: Colors.black87))),
                    title: Text('"${a.selectedText}"', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic)),
                    subtitle: a.note.isEmpty ? null : Text(a.note),
                    onTap: local ? () => _openReader(a.page) : null,
                  ),
                ),
          ]),
        ),
      ),
    );
  }
}
