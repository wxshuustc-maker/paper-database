import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/database.dart';
import 'data/library.dart';
import 'sync/sync_service.dart';
import 'ui/app_scope.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  sqfliteFfiInit();

  final dir = await getApplicationSupportDirectory();
  final db = await LocalDatabase.open(databaseFactoryFfi, p.join(dir.path, 'library.db'));
  final library = Library(db: db, filesDir: Directory(p.join(dir.path, 'files')), pdfTextReader: readPdfText);
  await library.init();
  final sync = SyncService(library);
  await sync.load();

  runApp(PaperLibraryApp(library: library, sync: sync));
}

/// 读取 PDF 前两页文字，用于提取标题、摘要和关键词。
Future<String> readPdfText(String path) async {
  final doc = await PdfDocument.openFile(path);
  try {
    final buf = StringBuffer();
    for (final page in doc.pages.take(2)) {
      final text = await page.loadText();
      if (text != null) buf.writeln(text.fullText);
    }
    return buf.toString();
  } finally {
    await doc.dispose();
  }
}

class PaperLibraryApp extends StatelessWidget {
  final Library library;
  final SyncService sync;
  const PaperLibraryApp({super.key, required this.library, required this.sync});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      library: library,
      sync: sync,
      child: MaterialApp(
        title: '论文库',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF3F51B5), useMaterial3: true),
        darkTheme: ThemeData(
            colorSchemeSeed: const Color(0xFF3F51B5), useMaterial3: true, brightness: Brightness.dark),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomePage(),
      ),
    );
  }
}
