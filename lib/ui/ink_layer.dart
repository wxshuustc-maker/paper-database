import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models.dart';

enum InkMode { pen, highlighter, eraser }

/// 手写工具的当前设置，在阅读器工具栏和每页的墨迹层之间共享。
class InkSettings extends ChangeNotifier {
  bool enabled = false;
  InkMode mode = InkMode.pen;
  Color color = const Color(0xFF1565C0);

  /// 笔宽，相对页面宽度。
  double width = 0.0025;

  /// 只允许触控笔书写；手指仍然用于滚动和缩放（平板上防误触）。
  bool stylusOnly = true;

  void update(void Function(InkSettings s) f) {
    f(this);
    notifyListeners();
  }

  Set<PointerDeviceKind> get drawingDevices => {
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        // 桌面端没有触控笔时用鼠标书写。
        PointerDeviceKind.mouse,
        if (!stylusOnly) PointerDeviceKind.touch,
      };
}

/// 一页的墨迹数据和撤销栈。
class InkPageController extends ChangeNotifier {
  final String paperId;
  final int page;
  List<InkStroke> strokes;
  final List<List<InkStroke>> _undo = [];
  final List<List<InkStroke>> _redo = [];
  final void Function(InkPageController) onChanged;

  InkPageController(this.paperId, this.page, this.strokes, this.onChanged);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void _commit(List<InkStroke> next) {
    _undo.add(strokes);
    _redo.clear();
    strokes = next;
    notifyListeners();
    onChanged(this);
  }

  void add(InkStroke s) => _commit([...strokes, s]);

  /// 用存储里加载的数据替换（不进入撤销栈）。
  void load(List<InkStroke> data) {
    strokes = data;
    notifyListeners();
  }

  /// 擦除经过 [p]（归一化坐标）附近的整条笔画。
  bool eraseAt(Offset p, double radius, double aspect) {
    final keep = strokes.where((s) => !_hits(s, p, radius, aspect)).toList();
    if (keep.length == strokes.length) return false;
    _commit(keep);
    return true;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(strokes);
    strokes = _undo.removeLast();
    notifyListeners();
    onChanged(this);
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(strokes);
    strokes = _redo.removeLast();
    notifyListeners();
    onChanged(this);
  }

  static bool _hits(InkStroke s, Offset p, double r, double aspect) {
    final pts = s.points;
    for (var i = 0; i + 2 < pts.length; i += 3) {
      final dx = pts[i] - p.dx;
      final dy = (pts[i + 1] - p.dy) * aspect;
      if (dx * dx + dy * dy < r * r) return true;
    }
    return false;
  }
}

/// 覆盖在 PDF 页面上的墨迹层：绘制已有笔画，并在手写模式下接收触控笔输入。
class InkLayer extends StatefulWidget {
  final InkPageController controller;
  final InkSettings settings;
  final String Function() newId;

  const InkLayer({super.key, required this.controller, required this.settings, required this.newId});

  @override
  State<InkLayer> createState() => _InkLayerState();
}

class _InkLayerState extends State<InkLayer> {
  final List<double> _current = [];
  final ValueNotifier<int> _tick = ValueNotifier(0);
  Size _size = Size.zero;

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  Offset _norm(Offset local) => Offset(local.dx / _size.width, local.dy / _size.height);

  void _start(Offset local, double pressure) {
    final s = widget.settings;
    if (s.mode == InkMode.eraser) {
      _erase(local);
      return;
    }
    _current
      ..clear()
      ..addAll([_norm(local).dx, _norm(local).dy, pressure]);
    _tick.value++;
  }

  void _move(Offset local, double pressure) {
    if (widget.settings.mode == InkMode.eraser) {
      _erase(local);
      return;
    }
    if (_current.isEmpty) return;
    final n = _norm(local);
    // 距离太近的点丢弃，减少数据量。
    final lx = _current[_current.length - 3], ly = _current[_current.length - 2];
    final dx = (n.dx - lx) * _size.width, dy = (n.dy - ly) * _size.height;
    if (dx * dx + dy * dy < 1.5) return;
    _current.addAll([n.dx, n.dy, pressure]);
    _tick.value++;
  }

  void _end() {
    final s = widget.settings;
    if (s.mode == InkMode.eraser || _current.isEmpty) return;
    final highlighter = s.mode == InkMode.highlighter;
    widget.controller.add(InkStroke(
      id: widget.newId(),
      tool: highlighter ? InkTool.highlighter : InkTool.pen,
      color: highlighter ? s.color.withAlpha(0x66).toARGB32() : s.color.toARGB32(),
      width: highlighter ? s.width * 5 : s.width,
      points: List.of(_current),
    ));
    _current.clear();
    _tick.value++;
  }

  void _erase(Offset local) {
    widget.controller.eraseAt(_norm(local), 12 / _size.width, _size.height / _size.width);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _size = constraints.biggest;
      final paint = RepaintBoundary(
        child: CustomPaint(
          size: _size,
          painter: _InkPainter(widget.controller, _current, _tick, widget.settings),
        ),
      );
      return ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) {
          final s = widget.settings;
          if (!s.enabled) return IgnorePointer(child: paint);
          return RawGestureDetector(
            key: ValueKey(s.stylusOnly),
            // translucent：手指事件继续传给下面的 PDF 阅读器，用来滚动/缩放。
            behavior: HitTestBehavior.translucent,
            gestures: {
              _EagerDrawRecognizer: GestureRecognizerFactoryWithHandlers<_EagerDrawRecognizer>(
                () => _EagerDrawRecognizer(supportedDevices: s.drawingDevices),
                (r) => r
                  ..onStart = _start
                  ..onUpdate = _move
                  ..onEnd = _end,
              ),
            },
            child: paint,
          );
        },
      );
    });
  }
}

/// 一碰到允许的设备（触控笔/鼠标）就立刻赢得手势竞争，
/// 这样书写时 PDF 阅读器不会同时滚动；其他设备（手指）不受影响。
class _EagerDrawRecognizer extends OneSequenceGestureRecognizer {
  _EagerDrawRecognizer({super.supportedDevices});

  void Function(Offset local, double pressure)? onStart;
  void Function(Offset local, double pressure)? onUpdate;
  VoidCallback? onEnd;
  int? _pointer;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (_pointer != null) return false;
    // 鼠标只响应左键。
    if (event.kind == PointerDeviceKind.mouse && event.buttons != kPrimaryButton) return false;
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    resolve(GestureDisposition.accepted);
    onStart?.call(event.localPosition, _pressure(event));
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onUpdate?.call(event.localPosition, _pressure(event));
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      onEnd?.call();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) => _pointer = null;

  static double _pressure(PointerEvent e) {
    if (e.pressureMax <= e.pressureMin || e.kind != PointerDeviceKind.stylus) return 0.5;
    return ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin)).clamp(0.05, 1.0);
  }

  @override
  String get debugDescription => 'ink-draw';

  @override
  void rejectGesture(int pointer) {
    stopTrackingPointer(pointer);
  }
}

class _InkPainter extends CustomPainter {
  final InkPageController controller;
  final List<double> current;
  final InkSettings settings;

  _InkPainter(this.controller, this.current, Listenable tick, this.settings)
      : super(repaint: Listenable.merge([controller, tick]));

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in controller.strokes) {
      paintStroke(canvas, size, s.points, Color(s.color), s.width, s.tool == InkTool.highlighter);
    }
    if (current.isNotEmpty) {
      final hl = settings.mode == InkMode.highlighter;
      paintStroke(canvas, size, current, hl ? settings.color.withAlpha(0x66) : settings.color,
          hl ? settings.width * 5 : settings.width, hl);
    }
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) => true;

  // 画布本身不拦截触摸，手指事件才能穿透到下面的阅读器用于滚动缩放。
  @override
  bool? hitTest(Offset position) => false;
}

/// 绘制一条笔画。钢笔按压力变化粗细；荧光笔用固定粗细和平头端点。
void paintStroke(Canvas canvas, Size size, List<double> pts, Color color, double width, bool highlighter) {
  final n = pts.length ~/ 3;
  if (n == 0) return;
  final base = width * size.width;
  final paint = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = highlighter ? StrokeCap.square : StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  if (highlighter) paint.blendMode = BlendMode.multiply;

  Offset at(int i) => Offset(pts[i * 3] * size.width, pts[i * 3 + 1] * size.height);

  if (n == 1) {
    canvas.drawCircle(at(0), max(base * 0.5, 0.5), Paint()..color = color);
    return;
  }
  if (highlighter) {
    final path = ui.Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < n; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(path, paint..strokeWidth = base);
    return;
  }
  // 钢笔：相邻点之间用二次贝塞尔平滑，按压力分段设定粗细。
  for (var i = 1; i < n; i++) {
    final p0 = at(i - 1), p1 = at(i);
    final pressure = (pts[(i - 1) * 3 + 2] + pts[i * 3 + 2]) / 2;
    paint.strokeWidth = max(base * (0.4 + 1.2 * pressure), 0.6);
    if (i < n - 1) {
      final mid = (p1 + at(i + 1)) / 2;
      final start = i == 1 ? p0 : (p0 + p1) / 2;
      canvas.drawPath(
          ui.Path()
            ..moveTo(start.dx, start.dy)
            ..quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy),
          paint);
    } else {
      final start = n > 2 ? (p0 + p1) / 2 : p0;
      canvas.drawLine(start, p1, paint);
    }
  }
}
