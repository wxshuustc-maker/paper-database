// 端到端界面测试：在真实桌面环境里运行应用，导入 PDF、打开阅读器、
// 用触控笔书写、选中文字添加批注，并把每一步截图保存到 SCREENSHOT_DIR。
//
// 运行：flutter test integration_test/app_test.dart -d linux
//      --dart-define=TEST_PDFS=/path/a.pdf,/path/b.pdf --dart-define=SCREENSHOT_DIR=/tmp/shots
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:paper_library/data/database.dart';
import 'package:paper_library/data/library.dart';
import 'package:paper_library/main.dart';
import 'package:paper_library/sync/sync_service.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const pdfs = String.fromEnvironment('TEST_PDFS');
const shotDir = String.fromEnvironment('SCREENSHOT_DIR', defaultValue: '/tmp/shots');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final boundaryKey = GlobalKey();

  Future<void> wait(WidgetTester t, int ms) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    await wait(t, 300);
    final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(shotDir).createSync(recursive: true);
    File('$shotDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  }

  testWidgets('导入、分类、阅读、手写、批注', (t) async {
    await pdfrxFlutterInitialize();
    sqfliteFfiInit();
    final tmp = Directory.systemTemp.createTempSync('pl_it');
    final db = await LocalDatabase.open(databaseFactoryFfi, '${tmp.path}/library.db');
    final lib = Library(db: db, filesDir: Directory('${tmp.path}/files'), pdfTextReader: readPdfText);
    await lib.init();
    final sync = SyncService(lib);
    await sync.load();

    final results = <ImportResult>[];
    for (final path in pdfs.split(',').where((s) => s.isNotEmpty)) {
      results.add(await lib.importPdf(path, lookupOnline: false));
    }
    for (final r in results) {
      // ignore: avoid_print
      print('IMPORTED: "${r.paper.title}" -> ${lib.categoryPath(r.paper.categoryId)} | '
          'keywords=${r.paper.keywords} | abstract=${r.paper.abstract.substring(0, 40)}…');
    }

    await t.pumpWidget(RepaintBoundary(key: boundaryKey, child: PaperLibraryApp(library: lib, sync: sync)));
    await wait(t, 800);
    await shot(t, '1_home');

    // 详情页
    await t.tap(find.text(results.first.paper.title).first);
    await wait(t, 800);
    await shot(t, '2_detail');

    // 阅读器
    await t.tap(find.textContaining('阅读 PDF'));
    await wait(t, 2500);
    await shot(t, '3_reader');

    // 鼠标拖选摘要中的一段文字
    final viewer = t.getRect(find.byType(PdfViewer));
    final from = Offset(viewer.left + viewer.width * 0.18, viewer.top + viewer.height * 0.62);
    final to = Offset(viewer.left + viewer.width * 0.62, viewer.top + viewer.height * 0.62);
    final g = await t.startGesture(from, kind: PointerDeviceKind.mouse, buttons: kPrimaryButton);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 10)!);
      await t.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await wait(t, 600);
    await shot(t, '4_selected');

    final fab = find.text('批注选中内容');
    // ignore: avoid_print
    print('SELECTION FAB FOUND: ${fab.evaluate().isNotEmpty}');
    if (fab.evaluate().isNotEmpty) {
      await t.tap(fab);
      await wait(t, 600);
      await t.enterText(find.byType(TextField).last, '残差连接解决了深层网络退化问题');
      await shot(t, '5_annotation_dialog');
      await t.tap(find.text('保存'));
      await wait(t, 800);
      await shot(t, '6_highlight');
    }

    // 手写模式：用触控笔在页面上画一个波浪线，再用手指拖动（应滚动而不是写字）
    await t.tap(find.byTooltip('手写笔记'));
    await wait(t, 500);
    final start = Offset(viewer.left + viewer.width * 0.25, viewer.top + viewer.height * 0.55);
    final pen = await t.startGesture(start, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 40; i++) {
      await pen.moveTo(start + Offset(i * 8.0, 25 * (i.isEven ? 1 : -1) * 0.6));
      await t.pump(const Duration(milliseconds: 16));
    }
    await pen.up();
    await wait(t, 400);
    final circle = Offset(viewer.left + viewer.width * 0.6, viewer.top + viewer.height * 0.7);
    final pen2 = await t.startGesture(circle, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 36; i++) {
      final a = i / 36 * 6.283;
      await pen2.moveTo(circle + Offset(40 * math.cos(a) - 40, 40 * math.sin(a)));
      await t.pump(const Duration(milliseconds: 16));
    }
    await pen2.up();
    await wait(t, 400);
    final finger = await t.startGesture(Offset(viewer.left + 60, viewer.top + viewer.height * 0.7), kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await finger.moveBy(const Offset(0, -20));
      await t.pump(const Duration(milliseconds: 16));
    }
    await finger.up();
    await wait(t, 1200);
    await shot(t, '7_ink');
    // 手指滚动后，再用触控笔在同一屏幕位置画一笔：如果页面滚动了，它在页面上的纵坐标应比第一笔更靠下。
    final pen3 = await t.startGesture(start, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await pen3.moveTo(start + Offset(i * 8.0, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await pen3.up();
    await wait(t, 1200);
    final pageInk = (await lib.inkOf(results.first.paper.id)).values.expand((p) => p.strokes).toList();
    // ignore: avoid_print
    print('FIRST STROKE Y=${pageInk.first.points[1]}, LAST STROKE Y=${pageInk.last.points[1]}');
    expect(pageInk.last.points[1], greaterThan(pageInk.first.points[1] + 0.05), reason: '手写模式下手指应能滚动页面');

    final ink = await lib.inkOf(results.first.paper.id);
    final strokes = ink.values.fold(0, (s, p) => s + p.strokes.length);
    // ignore: avoid_print
    print('INK STROKES SAVED: $strokes, ANNOTATIONS: ${(await lib.annotationsOf(results.first.paper.id)).length}');
    expect(strokes, 3, reason: '两笔触控笔笔画应被保存，手指拖动不应产生笔画');

    // 返回首页查看分类树
    await t.tap(find.byType(BackButton));
    await wait(t, 500);
    await shot(t, '8_detail_after');
    await t.tap(find.byType(BackButton));
    await wait(t, 800);
    await shot(t, '9_home_after');
    expect(results.length, greaterThan(0));
    expect(lib.papers.where((p) => p.categoryId != 'uncategorized'), isNotEmpty);
  });
}

