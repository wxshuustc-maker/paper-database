import 'package:flutter/material.dart';

import '../classifier/classifier.dart';
import '../data/library.dart';
import '../models.dart';

/// 分类树：顶级分类可折叠，显示每个分类下的论文数量。
class CategoryTree extends StatefulWidget {
  final Library library;
  final String? selected;
  final ValueChanged<String?> onSelect;

  const CategoryTree({super.key, required this.library, required this.selected, required this.onSelect});

  @override
  State<CategoryTree> createState() => _CategoryTreeState();
}

class _CategoryTreeState extends State<CategoryTree> {
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final lib = widget.library;
    final counts = <String, int>{};
    for (final p in lib.papers) {
      counts[p.categoryId] = (counts[p.categoryId] ?? 0) + 1;
    }
    int countOf(String id) => lib.descendantIds(id).fold(0, (s, x) => s + (counts[x] ?? 0));

    final items = <Widget>[
      _tile(context, null, '全部论文', lib.papers.length, 0, Icons.library_books_outlined),
    ];
    void addLevel(String? parentId, int depth) {
      for (final c in lib.childrenOf(parentId)) {
        if (c.id == 'uncategorized') continue;
        final n = countOf(c.id);
        final children = lib.childrenOf(c.id);
        // 顶级分类下只有一个同名子分类时（如"化学/化学"），只显示一级。
        final single = children.length == 1 && children.first.name == c.name && lib.childrenOf(children.first.id).isEmpty;
        // 没有论文的内置顶级分类默认折叠掉，避免列表太长；用户自建分类总是显示。
        if (n == 0 && depth == 0 && !c.id.startsWith('u.')) continue;
        final hasChildren = children.isNotEmpty && !single;
        items.add(_tile(context, c.id, c.name, n, depth,
            depth == 0 ? Icons.folder_outlined : Icons.label_outline,
            category: single ? children.first : c,
            expandable: hasChildren,
            expanded: !_collapsed.contains(c.id),
            onToggle: () => setState(() => _collapsed.contains(c.id) ? _collapsed.remove(c.id) : _collapsed.add(c.id))));
        if (hasChildren && !_collapsed.contains(c.id)) addLevel(c.id, depth + 1);
      }
    }

    addLevel(null, 0);
    items.add(_tile(context, 'uncategorized', '未分类', counts['uncategorized'] ?? 0, 0, Icons.help_outline));
    items.add(Padding(
      padding: const EdgeInsets.all(8),
      child: Wrap(spacing: 8, children: [
        TextButton.icon(
          onPressed: () => _editCategory(context, lib, null),
          icon: const Icon(Icons.add),
          label: const Text('新建分类'),
        ),
        TextButton.icon(
          onPressed: () => _showAllCategories(context, lib),
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('管理全部分类'),
        ),
      ]),
    ));
    return ListView(padding: EdgeInsets.zero, children: items);
  }

  Widget _tile(BuildContext context, String? id, String name, int count, int depth, IconData icon,
      {Category? category, bool expandable = false, bool expanded = true, VoidCallback? onToggle}) {
    final selected = widget.selected == id;
    return ListTile(
      dense: true,
      selected: selected,
      contentPadding: EdgeInsets.only(left: 12.0 + depth * 18, right: 4),
      leading: Icon(icon, size: 20),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$count', style: Theme.of(context).textTheme.bodySmall),
        if (expandable)
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
            onPressed: onToggle,
          )
        else
          const SizedBox(width: 40),
      ]),
      onTap: () => widget.onSelect(id),
      onLongPress: category == null ? null : () => _categoryMenu(context, widget.library, category),
    );
  }
}

Future<void> _showAllCategories(BuildContext context, Library lib) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => ListenableBuilder(
      listenable: lib,
      builder: (ctx, _) {
        final rows = <Widget>[];
        void add(String? parent, int depth) {
          for (final c in lib.childrenOf(parent)) {
            if (c.id == 'uncategorized') continue;
            rows.add(ListTile(
              dense: true,
              contentPadding: EdgeInsets.only(left: 8.0 + depth * 20),
              title: Text(c.name),
              subtitle: c.keywords.isEmpty ? null : Text(c.keywords.take(6).join('、'), maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(icon: const Icon(Icons.more_vert), onPressed: () => _categoryMenu(ctx, lib, c)),
            ));
            add(c.id, depth + 1);
          }
        }

        add(null, 0);
        return AlertDialog(
          title: const Text('全部分类'),
          content: SizedBox(width: 480, height: 520, child: ListView(children: rows)),
          actions: [
            TextButton(onPressed: () => _editCategory(ctx, lib, null), child: const Text('新建分类')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        );
      },
    ),
  );
}

Future<void> _categoryMenu(BuildContext context, Library lib, Category c) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(lib.categoryPath(c.id), style: const TextStyle(fontWeight: FontWeight.bold))),
        ListTile(leading: const Icon(Icons.edit), title: const Text('重命名 / 编辑关键词'), onTap: () => Navigator.pop(ctx, 'edit')),
        ListTile(leading: const Icon(Icons.create_new_folder_outlined), title: const Text('新建子分类'), onTap: () => Navigator.pop(ctx, 'child')),
        ListTile(leading: const Icon(Icons.delete_outline), title: const Text('删除分类'), onTap: () => Navigator.pop(ctx, 'delete')),
      ]),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case 'edit':
      await _editCategory(context, lib, c);
    case 'child':
      await _editCategory(context, lib, null, parentId: c.id);
    case 'delete':
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('删除"${c.name}"？'),
          content: const Text('其中的论文会移到"未分类"，子分类会上移一级。论文本身不会被删除。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
          ],
        ),
      );
      if (ok == true) await lib.deleteCategory(c);
  }
}

/// 新建或编辑分类。关键词决定自动分类时哪些论文会被归到这里。
Future<void> _editCategory(BuildContext context, Library lib, Category? existing, {String? parentId}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final keywords = TextEditingController(text: existing?.keywords.join(', ') ?? '');
  String? parent = existing?.parentId ?? parentId;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? '新建分类' : '编辑分类'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: '名称'), autofocus: true),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: parent,
              decoration: const InputDecoration(labelText: '上级分类'),
              items: [
                const DropdownMenuItem(value: null, child: Text('（无，作为顶级分类）')),
                for (final c in lib.categories.where((c) => c.parentId == null && c.id != existing?.id && c.id != 'uncategorized'))
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => parent = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: keywords,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '关键词（逗号分隔，中英文均可）',
                helperText: '导入论文时，标题、摘要、关键词中出现这些词越多，越可能被归入此分类',
                helperMaxLines: 2,
              ),
            ),
            if (existing != null && existing.learnedKeywords.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('已从你的手动归类中学到：${existing.learnedKeywords.keys.take(12).join('、')}',
                    style: Theme.of(ctx).textTheme.bodySmall),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
        ],
      ),
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return;
  final kws = keywords.text.split(RegExp(r'[,，;；\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (existing == null) {
    await lib.addCategory(name.text.trim(), parentId: parent, keywords: kws);
  } else {
    await lib.saveCategory(existing.copyWith(name: name.text.trim(), parentId: () => parent, keywords: kws));
  }
}

/// 选择分类的对话框：上方是自动分类建议，下方是全部分类。返回所选分类 ID。
Future<String?> pickCategory(BuildContext context, Library lib, Paper paper) {
  final ranking = lib.rank(paper);
  final top = ranking.take(4).toList();
  final maxScore = top.isEmpty ? 1.0 : top.first.score;
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final rows = <Widget>[];
      void add(String? parent, int depth) {
        for (final c in lib.childrenOf(parent)) {
          final isLeafish = lib.childrenOf(c.id).isEmpty;
          rows.add(ListTile(
            dense: true,
            contentPadding: EdgeInsets.only(left: 8.0 + depth * 20, right: 8),
            title: Text(c.name, style: isLeafish ? null : const TextStyle(fontWeight: FontWeight.w600)),
            selected: c.id == paper.categoryId,
            onTap: () => Navigator.pop(ctx, c.id),
          ));
          add(c.id, depth + 1);
        }
      }

      add(null, 0);
      return AlertDialog(
        title: const Text('选择分类'),
        content: SizedBox(
          width: 480,
          height: 560,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (top.isNotEmpty) ...[
              Text('自动分类建议', style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in top) _SuggestionChip(lib: lib, score: s, maxScore: maxScore, onTap: () => Navigator.pop(ctx, s.category.id)),
              ]),
              const Divider(height: 20),
            ],
            Expanded(child: ListView(children: rows)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消'))],
      );
    },
  );
}

class _SuggestionChip extends StatelessWidget {
  final Library lib;
  final CategoryScore score;
  final double maxScore;
  final VoidCallback onTap;
  const _SuggestionChip({required this.lib, required this.score, required this.maxScore, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final pct = (score.score / maxScore * 100).round();
    return ActionChip(
      avatar: CircleAvatar(child: Text('$pct', style: const TextStyle(fontSize: 10))),
      label: Text(lib.categoryPath(score.category.id)),
      onPressed: onTap,
    );
  }
}
