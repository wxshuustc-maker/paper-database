import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../classifier/classifier.dart';
import '../classifier/taxonomy.dart';
import '../import/online_lookup.dart';
import '../import/text_metadata.dart';
import '../models.dart';
import 'database.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class ImportResult {
  final Paper paper;
  final List<CategoryScore> ranking;
  final bool duplicate;
  const ImportResult(this.paper, this.ranking, {this.duplicate = false});
}

/// 应用的数据层：持有论文和分类的内存副本，负责导入、分类和保存。
class Library extends ChangeNotifier {
  final LocalDatabase db;
  final Directory filesDir;
  final Classifier classifier = Classifier();
  final OnlineLookup online;

  /// 读取 PDF 前几页文字的函数，由 UI 层注入（依赖 pdfrx），方便测试替换。
  final Future<String> Function(String path)? pdfTextReader;

  /// 每次本地修改后调用，用于触发自动同步。
  VoidCallback? onLocalChange;

  List<Paper> papers = [];
  List<Category> categories = [];

  Library({required this.db, required this.filesDir, this.pdfTextReader, OnlineLookup? online})
      : online = online ?? OnlineLookup();

  Future<void> init() async {
    await filesDir.create(recursive: true);
    // 内置分类 updatedAt=0：各设备内容一致无需同步，用户一旦修改就会以新时间戳同步出去。
    await db.putIfAbsent(
        RecordType.category, const Category(id: uncategorizedId, name: '未分类', sortOrder: 9999, updatedAt: 0));
    for (final (i, s) in seedCategories.indexed) {
      await db.putIfAbsent(
        RecordType.category,
        Category(id: s.id, name: s.name, parentId: s.parentId, keywords: s.keywords, sortOrder: i, updatedAt: 0),
      );
    }
    await reload();
  }

  Future<void> reload() async {
    papers = await db.all<Paper>(RecordType.paper);
    papers.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    categories = await db.all<Category>(RecordType.category);
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    notifyListeners();
  }

  Category? categoryById(String id) => categories.where((c) => c.id == id).firstOrNull;

  List<Category> childrenOf(String? parentId) => categories.where((c) => c.parentId == parentId).toList();

  /// 分类的完整路径，例如 "计算机科学 / 计算机视觉"。
  String categoryPath(String id) {
    final parts = <String>[];
    var c = categoryById(id);
    var guard = 0;
    while (c != null && guard++ < 10) {
      parts.insert(0, c.name);
      c = c.parentId == null ? null : categoryById(c.parentId!);
    }
    return parts.isEmpty ? '未分类' : parts.join(' / ');
  }

  /// 某分类（含子分类）下的论文。
  Set<String> descendantIds(String id) {
    final out = {id};
    for (final c in childrenOf(id)) {
      out.addAll(descendantIds(c.id));
    }
    return out;
  }

  File fileFor(Paper paper) => File(p.join(filesDir.path, '${paper.fileHash}.pdf'));

  bool hasLocalFile(Paper paper) => paper.fileHash != null && fileFor(paper).existsSync();

  // ---------------------------------------------------------------- 论文

  Future<void> savePaper(Paper paper) async {
    await db.put(RecordType.paper, paper);
    onLocalChange?.call();
    final i = papers.indexWhere((x) => x.id == paper.id);
    if (paper.deleted) {
      if (i >= 0) papers.removeAt(i);
    } else if (i >= 0) {
      papers[i] = paper;
    } else {
      papers.insert(0, paper);
    }
    notifyListeners();
  }

  /// 删除论文，连同它的批注和手写笔记（以墓碑形式同步到其他设备）。
  Future<void> deletePaper(Paper paper) async {
    for (final a in await annotationsOf(paper.id)) {
      await db.put(RecordType.annotation, a.copyWith(deleted: true));
    }
    for (final ink in (await inkOf(paper.id)).values) {
      await db.put(RecordType.ink, InkPage(paperId: ink.paperId, page: ink.page, updatedAt: nowMs(), deleted: true));
    }
    await savePaper(paper.copyWith(deleted: true));
  }

  List<CategoryScore> rank(Paper paper) => classifier.rank(paper, categories);

  /// 用户手动修改分类：记录为手动，并让分类器学习这篇论文的关键词。
  Future<void> setCategory(Paper paper, String categoryId) async {
    await savePaper(paper.copyWith(categoryId: categoryId, categoryManual: true));
    final cat = categoryById(categoryId);
    if (cat != null && categoryId != uncategorizedId && paper.keywords.isNotEmpty) {
      await saveCategory(classifier.learn(paper, cat));
    }
  }

  /// 对没有手动指定分类的论文重新自动分类，返回变动数量。
  Future<int> reclassifyAll() async {
    var changed = 0;
    for (final paper in List.of(papers)) {
      if (paper.categoryManual) continue;
      final id = classifier.classify(paper, categories);
      if (id != paper.categoryId) {
        await savePaper(paper.copyWith(categoryId: id));
        changed++;
      }
    }
    return changed;
  }

  /// 导入一个 PDF：计算哈希去重、复制到应用目录、提取元数据、自动分类。
  Future<ImportResult> importPdf(String sourcePath, {bool lookupOnline = true}) async {
    final bytes = await File(sourcePath).readAsBytes();
    final hash = sha256.convert(bytes).toString();
    final existing = papers.where((x) => x.fileHash == hash).firstOrNull;
    if (existing != null) return ImportResult(existing, rank(existing), duplicate: true);

    final dest = File(p.join(filesDir.path, '$hash.pdf'));
    if (!await dest.exists()) await dest.writeAsBytes(bytes, flush: true);

    var text = '';
    try {
      text = await pdfTextReader?.call(dest.path) ?? '';
    } catch (e) {
      debugPrint('读取 PDF 文本失败: $e');
    }
    final meta = extractMetadataFromText(text);
    final fileName = p.basename(sourcePath);

    var paper = Paper(
      id: newId(),
      title: meta.title.isNotEmpty ? meta.title : p.basenameWithoutExtension(sourcePath),
      abstract: meta.abstract,
      keywords: meta.keywords,
      doi: meta.doi,
      year: meta.year,
      fileHash: hash,
      fileName: fileName,
      createdAt: nowMs(),
      updatedAt: nowMs(),
    );

    String? arxivCategory;
    if (lookupOnline) {
      OnlineMetadata? om;
      if (meta.arxivId.isNotEmpty) om = await online.byArxiv(meta.arxivId);
      if (om == null && meta.doi.isNotEmpty) om = await online.byDoi(meta.doi);
      if (om != null) {
        paper = paper.copyWith(
          title: om.title.isNotEmpty ? om.title : null,
          authors: om.authors.isNotEmpty ? om.authors : null,
          year: om.year != null ? () => om!.year : null,
          venue: om.venue.isNotEmpty ? om.venue : null,
          abstract: paper.abstract.isEmpty && om.abstract.isNotEmpty ? om.abstract : null,
        );
        if (meta.arxivId.isNotEmpty) arxivCategory = categoryFromArxiv(om.subjects);
      }
    }

    final ranking = rank(paper);
    final catId = arxivCategory ?? classifier.classify(paper, categories);
    paper = paper.copyWith(categoryId: catId);
    await savePaper(paper);
    return ImportResult(paper, ranking);
  }

  /// 手动新建一条没有 PDF 的论文记录。
  Future<Paper> addManual({required String title, String abstract = '', List<String> keywords = const []}) async {
    var paper = Paper(
      id: newId(),
      title: title,
      abstract: abstract,
      keywords: keywords,
      createdAt: nowMs(),
      updatedAt: nowMs(),
    );
    paper = paper.copyWith(categoryId: classifier.classify(paper, categories));
    await savePaper(paper);
    return paper;
  }

  // ---------------------------------------------------------------- 分类

  Future<void> saveCategory(Category c) async {
    await db.put(RecordType.category, c);
    onLocalChange?.call();
    final i = categories.indexWhere((x) => x.id == c.id);
    if (c.deleted) {
      if (i >= 0) categories.removeAt(i);
    } else if (i >= 0) {
      categories[i] = c;
    } else {
      categories.add(c);
    }
    notifyListeners();
  }

  Future<Category> addCategory(String name, {String? parentId, List<String> keywords = const []}) async {
    final c = Category(
      id: 'u.${newId().substring(0, 8)}',
      name: name,
      parentId: parentId,
      keywords: keywords,
      sortOrder: categories.length + 100,
      updatedAt: nowMs(),
    );
    await saveCategory(c);
    return c;
  }

  /// 删除分类：其下论文移到"未分类"，子分类上移一级。
  Future<void> deleteCategory(Category c) async {
    for (final paper in papers.where((x) => x.categoryId == c.id).toList()) {
      await savePaper(paper.copyWith(categoryId: uncategorizedId, categoryManual: false));
    }
    for (final child in childrenOf(c.id)) {
      await saveCategory(child.copyWith(parentId: () => c.parentId));
    }
    await saveCategory(c.copyWith(deleted: true));
  }

  // ---------------------------------------------------------------- 批注与墨迹

  Future<List<Annotation>> annotationsOf(String paperId) async {
    final list = await db.byParent<Annotation>(RecordType.annotation, paperId);
    list.sort((a, b) => a.page != b.page ? a.page.compareTo(b.page) : a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> saveAnnotation(Annotation a) async {
    await db.put(RecordType.annotation, a);
    onLocalChange?.call();
    notifyListeners();
  }

  Future<Map<int, InkPage>> inkOf(String paperId) async {
    final list = await db.byParent<InkPage>(RecordType.ink, paperId);
    return {for (final p in list) p.page: p};
  }

  Future<void> saveInk(InkPage page) async {
    await db.put(RecordType.ink, page);
    onLocalChange?.call();
  }
}
