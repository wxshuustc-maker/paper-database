import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/library.dart';
import '../models.dart';
import 'app_scope.dart';
import 'ink_layer.dart';

const annotationColors = [0xFFFFEB3B, 0xFF81C784, 0xFF64B5F6, 0xFFF48FB1, 0xFFFFB74D];
const inkColors = [Color(0xFF212121), Color(0xFF1565C0), Color(0xFFD32F2F), Color(0xFF2E7D32), Color(0xFFF9A825)];
const inkWidths = [0.0015, 0.0025, 0.004];

/// PDF 阅读器：支持选中文字添加批注、在页面上手写。
class ReaderPage extends StatefulWidget {
  final String paperId;
  final int? initialPage;
  const ReaderPage({super.key, required this.paperId, this.initialPage});

  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  final _controller = PdfViewerController();
  final _ink = InkSettings();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late Library _lib;
  late Paper _paper;
  List<Annotation> _annotations = [];
  final Map<int, InkPageController> _inkPages = {};
  Map<int, InkPage> _storedInk = {};
  final Map<int, Timer> _inkSaveTimers = {};
  InkPageController? _lastEdited;
  bool _hasSelection = false;
  int? _page;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _lib = AppScope.of(context).library;
    _paper = _lib.papers.firstWhere((p) => p.id == widget.paperId);
    if (_paper.readStatus == ReadStatus.unread) {
      _paper = _paper.copyWith(readStatus: ReadStatus.reading);
      _lib.savePaper(_paper);
    }
    _load();
  }

  Future<void> _load() async {
    final annotations = await _lib.annotationsOf(_paper.id);
    final ink = await _lib.inkOf(_paper.id);
    if (!mounted) return;
    setState(() {
      _annotations = annotations;
      _storedInk = ink;
      // 墨迹层可能在数据加载完之前就已经创建了，补上数据。
      for (final MapEntry(key: page, value: c) in _inkPages.entries) {
        c.load(ink[page]?.strokes ?? const []);
      }
    });
    if (_controller.isReady) _controller.invalidate();
  }

  @override
  void dispose() {
    for (final MapEntry(key: page, value: t) in _inkSaveTimers.entries) {
      if (t.isActive) {
        t.cancel();
        _saveInk(_inkPages[page]!);
      }
    }
    for (final c in _inkPages.values) {
      c.dispose();
    }
    _ink.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ 墨迹

  InkPageController _inkFor(int page) => _inkPages.putIfAbsent(
        page,
        () => InkPageController(_paper.id, page, _storedInk[page]?.strokes ?? const [], (c) {
          _lastEdited = c;
          _inkSaveTimers[page]?.cancel();
          _inkSaveTimers[page] = Timer(const Duration(milliseconds: 800), () => _saveInk(c));
          setState(() {});
        }),
      );

  void _saveInk(InkPageController c) {
    final base = _storedInk[c.page] ?? InkPage(paperId: c.paperId, page: c.page, updatedAt: 0);
    final updated = base.withStrokes(c.strokes);
    _storedInk[c.page] = updated;
    _lib.saveInk(updated);
  }

  InkPageController? get _undoTarget {
    final current = _page == null ? null : _inkPages[_page!];
    if (current != null && (current.canUndo || current.canRedo)) return current;
    return _lastEdited;
  }

  // ------------------------------------------------------------------ 批注

  Future<void> _annotateSelection(PdfTextSelectionDelegate selection) async {
    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) return;
    final text = (await selection.getSelectedText()).replaceAll(RegExp(r'\s+'), ' ').trim();
    final firstPage = ranges.first.pageNumber;
    final rects = <NormRect>[];
    for (final range in ranges) {
      final page = _controller.pages[range.pageNumber - 1];
      for (final f in range.enumerateFragmentBoundingRects()) {
        final r = f.bounds.toRect(page: page);
        rects.add(NormRect(r.left / page.width, r.top / page.height, r.right / page.width, r.bottom / page.height,
            range.pageNumber == firstPage ? null : range.pageNumber));
      }
    }
    if (!mounted) return;
    final result = await showAnnotationEditor(context, quote: text);
    if (result == null) return;
    final a = Annotation(
      id: newId(),
      paperId: _paper.id,
      page: firstPage,
      selectedText: text,
      note: result.note,
      color: result.color,
      rects: rects,
      createdAt: nowMs(),
      updatedAt: nowMs(),
    );
    await _lib.saveAnnotation(a);
    await selection.clearTextSelection();
    setState(() => _annotations = [..._annotations, a]..sort((x, y) => x.page.compareTo(y.page)));
    _controller.invalidate();
  }

  Future<void> _editAnnotation(Annotation a) async {
    final result = await showAnnotationEditor(context, quote: a.selectedText, initial: a);
    if (result == null) return;
    final updated = result.delete ? a.copyWith(deleted: true) : a.copyWith(note: result.note, color: result.color);
    await _lib.saveAnnotation(updated);
    setState(() {
      _annotations = [
        for (final x in _annotations)
          if (x.id != a.id) x else if (!updated.deleted) updated,
      ];
    });
    _controller.invalidate();
  }

  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final a in _annotations) {
      final paint = Paint()
        ..color = Color(a.color).withAlpha(0x70)
        ..blendMode = BlendMode.multiply;
      for (final r in a.rects) {
        if ((r.page ?? a.page) != page.pageNumber) continue;
        canvas.drawRect(
          Rect.fromLTRB(pageRect.left + r.l * pageRect.width, pageRect.top + r.t * pageRect.height,
              pageRect.left + r.r * pageRect.width, pageRect.top + r.b * pageRect.height),
          paint,
        );
      }
      // 有批注内容的高亮在左侧画一个小标记。
      if (a.note.isNotEmpty && a.page == page.pageNumber && a.rects.isNotEmpty) {
        final r = a.rects.first;
        canvas.drawCircle(
          Offset(pageRect.left + r.l * pageRect.width - 6, pageRect.top + r.t * pageRect.height + 4),
          3.5,
          Paint()..color = Color(a.color).withAlpha(0xFF),
        );
      }
    }
  }

  bool _onTap(BuildContext context, PdfViewerController c, PdfViewerGeneralTapHandlerDetails d) {
    if (_ink.enabled || d.type != PdfViewerGeneralTapType.tap) return false;
    final layouts = c.layout.pageLayouts;
    for (var i = 0; i < layouts.length; i++) {
      final rect = layouts[i];
      if (!rect.contains(d.documentPosition)) continue;
      final x = (d.documentPosition.dx - rect.left) / rect.width;
      final y = (d.documentPosition.dy - rect.top) / rect.height;
      for (final a in _annotations) {
        if (a.rects.any((r) => (r.page ?? a.page) == i + 1 && r.contains(x, y))) {
          _editAnnotation(a);
          return true;
        }
      }
      break;
    }
    return false;
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final file = _lib.fileFor(_paper);
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_paper.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_page != null && _controller.isReady)
            Center(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text('$_page / ${_controller.pageCount}'))),
          IconButton(
            tooltip: _ink.enabled ? '退出手写' : '手写笔记',
            isSelected: _ink.enabled,
            icon: const Icon(Icons.draw_outlined),
            selectedIcon: const Icon(Icons.draw),
            onPressed: () => setState(() => _ink.update((s) => s.enabled = !s.enabled)),
          ),
          IconButton(
            tooltip: '批注列表',
            icon: Badge(
              isLabelVisible: _annotations.isNotEmpty,
              label: Text('${_annotations.length}'),
              child: const Icon(Icons.comment_outlined),
            ),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: _AnnotationDrawer(
        annotations: _annotations,
        onTap: (a) {
          Navigator.pop(context);
          _controller.goToPage(pageNumber: a.page);
        },
        onEdit: _editAnnotation,
      ),
      floatingActionButton: _hasSelection && !_ink.enabled
          ? FloatingActionButton.extended(
              onPressed: () => _annotateSelection(_controller.textSelectionDelegate),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('批注选中内容'),
            )
          : null,
      body: Stack(children: [
        PdfViewer.file(
          file.path,
          controller: _controller,
          params: PdfViewerParams(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            textSelectionParams: PdfTextSelectionParams(
              enabled: !_ink.enabled,
              onTextSelectionChange: (sel) {
                if (sel.hasSelectedText != _hasSelection) setState(() => _hasSelection = sel.hasSelectedText);
              },
            ),
            customizeContextMenuItems: (params, items) {
              if (params.textSelectionDelegate.hasSelectedText) {
                items.insert(
                  0,
                  ContextMenuButtonItem(
                    label: '添加批注',
                    onPressed: () {
                      params.dismissContextMenu();
                      _annotateSelection(params.textSelectionDelegate);
                    },
                  ),
                );
              }
            },
            pagePaintCallbacks: [_paintHighlights],
            onGeneralTap: _onTap,
            pageOverlaysBuilder: (context, pageRect, page) => [
              Positioned.fill(
                child: InkLayer(
                  key: ValueKey('ink-${page.pageNumber}'),
                  controller: _inkFor(page.pageNumber),
                  settings: _ink,
                  newId: newId,
                ),
              ),
            ],
            onPageChanged: (n) => setState(() => _page = n),
            onViewerReady: (doc, c) {
              if (widget.initialPage != null) c.goToPage(pageNumber: widget.initialPage!, duration: Duration.zero);
              setState(() => _page = c.pageNumber);
            },
          ),
        ),
        if (_ink.enabled)
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(child: _InkToolbar(settings: _ink, undoTarget: _undoTarget, onChanged: () => setState(() {}))),
          ),
      ]),
    );
  }
}

class _InkToolbar extends StatelessWidget {
  final InkSettings settings;
  final InkPageController? undoTarget;
  final VoidCallback onChanged;
  const _InkToolbar({required this.settings, required this.undoTarget, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final s = settings;
    void set(void Function(InkSettings) f) {
      s.update(f);
      onChanged();
    }

    Widget tool(InkMode m, IconData icon, String tip) => IconButton(
          tooltip: tip,
          isSelected: s.mode == m,
          icon: Icon(icon),
          onPressed: () => set((x) => x.mode = m),
        );

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            tool(InkMode.pen, Icons.edit, '钢笔'),
            tool(InkMode.highlighter, Icons.highlight, '荧光笔'),
            tool(InkMode.eraser, Icons.cleaning_services_outlined, '橡皮擦（整笔擦除）'),
            const SizedBox(width: 4),
            for (final c in inkColors)
              GestureDetector(
                onTap: () => set((x) => x.color = c),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: s.color == c ? 3 : 1, color: s.color == c ? Theme.of(context).colorScheme.primary : Colors.grey),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            for (final w in inkWidths)
              IconButton(
                tooltip: '笔宽',
                isSelected: s.width == w,
                icon: Container(width: 18, height: w * 2400, color: Theme.of(context).colorScheme.onSurface),
                onPressed: () => set((x) => x.width = w),
              ),
            IconButton(
              tooltip: '撤销',
              icon: const Icon(Icons.undo),
              onPressed: undoTarget?.canUndo == true ? () => undoTarget!.undo() : null,
            ),
            IconButton(
              tooltip: '重做',
              icon: const Icon(Icons.redo),
              onPressed: undoTarget?.canRedo == true ? () => undoTarget!.redo() : null,
            ),
            const SizedBox(width: 4),
            FilterChip(
              label: const Text('仅触控笔'),
              tooltip: '开启后手指用于翻页缩放，只有触控笔（或鼠标）会写字',
              selected: s.stylusOnly,
              onSelected: (v) => set((x) => x.stylusOnly = v),
            ),
          ]),
        ),
      ),
    );
  }
}

class _AnnotationDrawer extends StatelessWidget {
  final List<Annotation> annotations;
  final ValueChanged<Annotation> onTap;
  final ValueChanged<Annotation> onEdit;
  const _AnnotationDrawer({required this.annotations, required this.onTap, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 360,
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('批注（${annotations.length}）', style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(
            child: annotations.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('选中一段文字，点"添加批注"或右下角按钮即可添加。'))
                : ListView.builder(
                    itemCount: annotations.length,
                    itemBuilder: (context, i) {
                      final a = annotations[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: Color(a.color),
                          child: Text('${a.page}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                        ),
                        title: Text('"${a.selectedText}"',
                            maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontStyle: FontStyle.italic)),
                        subtitle: a.note.isEmpty ? null : Text(a.note),
                        trailing: IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => onEdit(a)),
                        onTap: () => onTap(a),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

class AnnotationEdit {
  final String note;
  final int color;
  final bool delete;
  const AnnotationEdit(this.note, this.color, {this.delete = false});
}

Future<AnnotationEdit?> showAnnotationEditor(BuildContext context, {required String quote, Annotation? initial}) {
  final note = TextEditingController(text: initial?.note ?? '');
  var color = initial?.color ?? annotationColors.first;
  return showDialog<AnnotationEdit>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(initial == null ? '添加批注' : '编辑批注'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Color(color).withAlpha(0x55),
                border: Border(left: BorderSide(color: Color(color), width: 4)),
              ),
              child: SingleChildScrollView(child: Text(quote, style: const TextStyle(fontStyle: FontStyle.italic))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              autofocus: true,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(hintText: '写下你的批注（可留空，只做高亮）', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(children: [
              for (final c in annotationColors)
                GestureDetector(
                  onTap: () => setState(() => color = c),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(width: color == c ? 3 : 1, color: color == c ? Colors.black54 : Colors.black12),
                    ),
                  ),
                ),
            ]),
          ]),
        ),
        actions: [
          if (initial != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, AnnotationEdit('', color, delete: true)),
              child: const Text('删除'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, AnnotationEdit(note.text.trim(), color)), child: const Text('保存')),
        ],
      ),
    ),
  );
}
