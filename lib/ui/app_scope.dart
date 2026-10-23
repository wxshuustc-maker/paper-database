import 'package:flutter/widgets.dart';

import '../data/library.dart';
import '../sync/sync_service.dart';

/// 向整个界面提供 [Library] 和 [SyncService]。
class AppScope extends InheritedWidget {
  final Library library;
  final SyncService sync;

  const AppScope({super.key, required this.library, required this.sync, required super.child});

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => library != oldWidget.library || sync != oldWidget.sync;
}
