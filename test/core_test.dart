import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:paper_library/classifier/classifier.dart';
import 'package:paper_library/classifier/taxonomy.dart';
import 'package:paper_library/data/database.dart';
import 'package:paper_library/data/library.dart';
import 'package:paper_library/import/online_lookup.dart';
import 'package:paper_library/import/text_metadata.dart';
import 'package:paper_library/models.dart';
import 'package:paper_library/sync/sync_engine.dart';
import 'package:paper_library/sync/webdav.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

List<Category> seeded() => [
      for (final s in seedCategories)
        Category(id: s.id, name: s.name, parentId: s.parentId, keywords: s.keywords, updatedAt: 0),
    ];

Paper paper({String title = '', String abstract = '', List<String> keywords = const []}) =>
    Paper(id: 'x', title: title, abstract: abstract, keywords: keywords, createdAt: 0, updatedAt: 0);

class MemoryRemote implements RemoteStore {
  final Map<String, Uint8List> files = {};
  int _v = 0;
  final Map<String, String> versions = {};

  @override
  Future<void> ensureDir(String dir) async {}

  @override
  Future<Uint8List> get(String path) async => files[path]!;

  @override
  Future<List<RemoteEntry>> list(String dir) async => [
        for (final k in files.keys)
          if (k.startsWith('$dir/') && !k.substring(dir.length + 1).contains('/'))
            RemoteEntry(k.substring(dir.length + 1), false, versions[k]!),
      ];

  @override
  Future<String?> put(String path, Uint8List data) async {
    files[path] = data;
    versions[path] = 'v${++_v}';
    return null; // 模拟不返回 ETag 的服务器
  }
}

Future<Library> newLibrary(Directory tmp, String name) async {
  sqfliteFfiInit();
  final db = await LocalDatabase.open(databaseFactoryFfiNoIsolate, '${tmp.path}/$name.db');
  final lib = Library(db: db, filesDir: Directory('${tmp.path}/$name'), online: OnlineLookup());
  await lib.init();
  return lib;
}

void main() {
  group('分类器', () {
    final cats = seeded();
    final c = Classifier();

    test('计算机视觉论文', () {
      final p = paper(
        title: 'Deep Residual Learning for Image Recognition',
        abstract: 'We present a residual learning framework to ease the training of deep convolutional neural '
            'networks for image classification and object detection on ImageNet and COCO.',
        keywords: ['image classification', 'convolutional neural network'],
      );
      expect(c.classify(p, cats), 'cs.cv');
    });

    test('自然语言处理论文', () {
      final p = paper(
        title: 'BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding',
        abstract: 'We introduce a new language representation model. BERT obtains new state-of-the-art results on '
            'eleven natural language processing tasks including question answering.',
      );
      expect(c.classify(p, cats), 'cs.cl');
    });

    test('中文论文', () {
      final p = paper(
        title: '基于钙钛矿薄膜的高效太阳能电池研究',
        abstract: '本文制备了一种新型钙钛矿薄膜材料，研究了其微观结构与光伏性能。',
        keywords: ['钙钛矿', '薄膜', '太阳能电池'],
      );
      expect(c.classify(p, cats), anyOf('mat.general', 'eng.energy'));
    });

    test('临床医学论文', () {
      final p = paper(
        title: 'Efficacy of a new drug in patients with type 2 diabetes: a randomized controlled trial',
        abstract: 'A total of 600 patients were enrolled. Treatment reduced mortality and improved prognosis.',
        keywords: ['diabetes', 'clinical trial'],
      );
      expect(c.classify(p, cats), 'med.clinical');
    });

    test('无关内容判为未分类', () {
      expect(c.classify(paper(title: 'Untitled document'), cats), 'uncategorized');
    });

    test('学习用户的手动归类', () {
      final custom = Category(id: 'u.1', name: '我的课题', updatedAt: 0);
      final p = paper(title: 'Some work', keywords: ['zebrafish locomotion', 'larval behaviour']);
      final learned = c.learn(p, custom);
      final p2 = paper(title: 'Another study', keywords: ['zebrafish locomotion']);
      expect(c.classify(p2, [...cats, learned]), 'u.1');
    });
  });

  group('元数据提取', () {
    test('英文论文', () {
      const text = '''arXiv:2103.00020v1 [cs.CV] 26 Feb 2021
Learning Transferable Visual Models From
Natural Language Supervision
Alec Radford * 1 Jong Wook Kim * 1
Abstract
State-of-the-art computer vision systems are
trained to predict a fixed set of predetermined object categories.
Keywords: contrastive learning, zero-shot transfer; vision-language
1. Introduction
Pre-training methods''';
      final m = extractMetadataFromText(text);
      expect(m.arxivId, '2103.00020');
      expect(m.title, 'Learning Transferable Visual Models From Natural Language Supervision');
      expect(m.abstract, startsWith('State-of-the-art computer vision systems are trained'));
      expect(m.abstract, isNot(contains('Keywords')));
      expect(m.keywords, ['contrastive learning', 'zero-shot transfer', 'vision-language']);
    });

    test('中文论文', () {
      const text = '''计算机学报 第45卷
基于深度学习的医学图像分割方法综述
张三 李四
摘 要：医学图像分割是医学影像分析中的关键步骤。本文综述了
近年来基于深度学习的方法。
关键词：医学图像；图像分割；深度学习
中图分类号：TP391
DOI: 10.11897/SP.J.1016.2022.00001''';
      final m = extractMetadataFromText(text);
      expect(m.title, '基于深度学习的医学图像分割方法综述');
      expect(m.abstract, '医学图像分割是医学影像分析中的关键步骤。本文综述了近年来基于深度学习的方法。');
      expect(m.keywords, ['医学图像', '图像分割', '深度学习']);
      expect(m.doi, '10.11897/SP.J.1016.2022.00001');
    });
  });

  test('arXiv 分类映射', () {
    expect(categoryFromArxiv(['cs.CV', 'cs.LG']), 'cs.cv');
    expect(categoryFromArxiv(['cond-mat.mtrl-sci']), 'mat.general');
    expect(categoryFromArxiv(['cond-mat.supr-con']), 'phys.cond');
  });

  test('解析 PROPFIND 响应', () {
    const xml = '''<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:">
 <d:response><d:href>/dav/PaperLibrary/records/paper/</d:href>
  <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat></d:response>
 <d:response><d:href>/dav/PaperLibrary/records/paper/abc.json</d:href>
  <d:propstat><d:prop><d:resourcetype/><d:getetag>"123"</d:getetag></d:prop></d:propstat></d:response>
 <d:response><d:href>/dav/PaperLibrary/records/paper/%E4%B8%AD.json</d:href>
  <d:propstat><d:prop><d:resourcetype/><d:getlastmodified>Mon</d:getlastmodified><d:getcontentlength>5</d:getcontentlength></d:prop></d:propstat></d:response>
</d:multistatus>''';
    final entries = WebDavClient.parseMultiStatus(xml, '/dav/PaperLibrary/records/paper/');
    expect(entries.map((e) => e.name), ['abc.json', '中.json']);
    expect(entries.first.version, '123');
    expect(entries.last.version, 'Mon|5');
  });

  group('同步', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pl'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('两台设备双向同步、后写入者胜出、删除同步', () async {
      final remote = MemoryRemote();
      final a = await newLibrary(tmp, 'a');
      final b = await newLibrary(tmp, 'b');
      SyncEngine engine(Library l) => SyncEngine(db: l.db, remote: remote, filesDir: l.filesDir);

      // A 新建论文并写批注、墨迹，同步上去。
      final p = await a.addManual(title: 'Graph neural networks for molecules', keywords: ['graph neural network']);
      await a.saveAnnotation(Annotation(
          id: 'n1', paperId: p.id, page: 1, selectedText: 'hello', note: '重要', createdAt: 1, updatedAt: nowMs()));
      await a.saveInk(InkPage(paperId: p.id, page: 2, updatedAt: nowMs(), strokes: const [
        InkStroke(id: 's1', tool: InkTool.pen, color: 0xFF000000, width: 0.002, points: [0.1, 0.1, 0.5, 0.2, 0.2, 0.5]),
      ]));
      final r1 = await engine(a).run();
      expect(r1.pushed, 3);

      // B 拉取。
      final r2 = await engine(b).run();
      expect(r2.pulled, 3);
      await b.reload();
      expect(b.papers.single.title, 'Graph neural networks for molecules');
      expect((await b.annotationsOf(p.id)).single.note, '重要');
      expect((await b.inkOf(p.id))[2]!.strokes.single.points.length, 6);

      // 再次同步没有任何传输。
      final r3 = await engine(b).run();
      expect(r3.pulled + r3.pushed, 0);

      // B 修改标题；A 之后修改评分 → A 的版本更新，最终两边一致为 A 的版本。
      await b.savePaper(b.papers.single.copyWith(title: 'B title'));
      await engine(b).run();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await a.savePaper(a.papers.single.copyWith(rating: 5));
      await engine(a).run();
      await engine(b).run();
      await a.reload();
      await b.reload();
      expect(a.papers.single.rating, 5);
      expect(b.papers.single.rating, 5);
      expect(b.papers.single.title, a.papers.single.title);

      // A 删除论文，B 同步后也消失。
      await a.deletePaper(a.papers.single);
      await engine(a).run();
      await engine(b).run();
      await b.reload();
      expect(b.papers, isEmpty);
      expect(await b.annotationsOf(p.id), isEmpty);
    });

    test('PDF 文件同步', () async {
      final remote = MemoryRemote();
      final a = await newLibrary(tmp, 'a');
      final b = await newLibrary(tmp, 'b');
      final src = File('${tmp.path}/paper.pdf')..writeAsBytesSync(utf8.encode('%PDF-1.4 fake'));
      final r = await a.importPdf(src.path, lookupOnline: false);
      expect(a.hasLocalFile(r.paper), isTrue);
      expect((await a.importPdf(src.path, lookupOnline: false)).duplicate, isTrue);

      final up = await SyncEngine(db: a.db, remote: remote, filesDir: a.filesDir).run();
      expect(up.filesUp, 1);
      final down = await SyncEngine(db: b.db, remote: remote, filesDir: b.filesDir).run();
      expect(down.filesDown, 1);
      await b.reload();
      expect(b.hasLocalFile(b.papers.single), isTrue);
    });
  });
}
