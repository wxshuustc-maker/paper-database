import 'dart:convert';

/// 所有可同步的记录都有 id / updatedAt / deleted 三个字段。
/// 同步时按 updatedAt 做"后写入者胜出"合并，删除以墓碑（deleted=true）形式同步。
abstract class SyncRecord {
  String get id;
  int get updatedAt;
  bool get deleted;
  Map<String, dynamic> toJson();
}

enum RecordType { paper, category, annotation, ink }

int nowMs() => DateTime.now().millisecondsSinceEpoch;

enum ReadStatus { unread, reading, read }

class Paper implements SyncRecord {
  @override
  final String id;
  final String title;
  final List<String> authors;
  final int? year;
  final String venue;
  final String doi;
  final String abstract;
  final List<String> keywords;
  final String categoryId;

  /// 分类是否由用户手动指定（手动指定后不再被自动分类覆盖）。
  final bool categoryManual;

  /// PDF 文件的 SHA-256，本地和 WebDAV 上都以它命名文件。
  final String? fileHash;
  final String? fileName;
  final ReadStatus readStatus;
  final int rating;
  final String note;
  final int createdAt;
  @override
  final int updatedAt;
  @override
  final bool deleted;

  const Paper({
    required this.id,
    this.title = '',
    this.authors = const [],
    this.year,
    this.venue = '',
    this.doi = '',
    this.abstract = '',
    this.keywords = const [],
    this.categoryId = 'uncategorized',
    this.categoryManual = false,
    this.fileHash,
    this.fileName,
    this.readStatus = ReadStatus.unread,
    this.rating = 0,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  Paper copyWith({
    String? title,
    List<String>? authors,
    int? Function()? year,
    String? venue,
    String? doi,
    String? abstract,
    List<String>? keywords,
    String? categoryId,
    bool? categoryManual,
    String? fileHash,
    String? fileName,
    ReadStatus? readStatus,
    int? rating,
    String? note,
    bool? deleted,
  }) =>
      Paper(
        id: id,
        title: title ?? this.title,
        authors: authors ?? this.authors,
        year: year != null ? year() : this.year,
        venue: venue ?? this.venue,
        doi: doi ?? this.doi,
        abstract: abstract ?? this.abstract,
        keywords: keywords ?? this.keywords,
        categoryId: categoryId ?? this.categoryId,
        categoryManual: categoryManual ?? this.categoryManual,
        fileHash: fileHash ?? this.fileHash,
        fileName: fileName ?? this.fileName,
        readStatus: readStatus ?? this.readStatus,
        rating: rating ?? this.rating,
        note: note ?? this.note,
        createdAt: createdAt,
        updatedAt: nowMs(),
        deleted: deleted ?? this.deleted,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'authors': authors,
        'year': year,
        'venue': venue,
        'doi': doi,
        'abstract': abstract,
        'keywords': keywords,
        'categoryId': categoryId,
        'categoryManual': categoryManual,
        'fileHash': fileHash,
        'fileName': fileName,
        'readStatus': readStatus.name,
        'rating': rating,
        'note': note,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory Paper.fromJson(Map<String, dynamic> j) => Paper(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        authors: _strList(j['authors']),
        year: j['year'] as int?,
        venue: j['venue'] as String? ?? '',
        doi: j['doi'] as String? ?? '',
        abstract: j['abstract'] as String? ?? '',
        keywords: _strList(j['keywords']),
        categoryId: j['categoryId'] as String? ?? 'uncategorized',
        categoryManual: j['categoryManual'] as bool? ?? false,
        fileHash: j['fileHash'] as String?,
        fileName: j['fileName'] as String?,
        readStatus: ReadStatus.values.firstWhere((e) => e.name == j['readStatus'],
            orElse: () => ReadStatus.unread),
        rating: j['rating'] as int? ?? 0,
        note: j['note'] as String? ?? '',
        createdAt: j['createdAt'] as int? ?? 0,
        updatedAt: j['updatedAt'] as int? ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );
}

class Category implements SyncRecord {
  @override
  final String id;
  final String name;
  final String? parentId;
  final List<String> keywords;

  /// 从用户手动归类中学到的关键词及出现次数。
  final Map<String, int> learnedKeywords;
  final int sortOrder;
  @override
  final int updatedAt;
  @override
  final bool deleted;

  const Category({
    required this.id,
    required this.name,
    this.parentId,
    this.keywords = const [],
    this.learnedKeywords = const {},
    this.sortOrder = 0,
    required this.updatedAt,
    this.deleted = false,
  });

  Category copyWith({
    String? name,
    String? Function()? parentId,
    List<String>? keywords,
    Map<String, int>? learnedKeywords,
    int? sortOrder,
    bool? deleted,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        parentId: parentId != null ? parentId() : this.parentId,
        keywords: keywords ?? this.keywords,
        learnedKeywords: learnedKeywords ?? this.learnedKeywords,
        sortOrder: sortOrder ?? this.sortOrder,
        updatedAt: nowMs(),
        deleted: deleted ?? this.deleted,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'keywords': keywords,
        'learnedKeywords': learnedKeywords,
        'sortOrder': sortOrder,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory Category.fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        parentId: j['parentId'] as String?,
        keywords: _strList(j['keywords']),
        learnedKeywords: (j['learnedKeywords'] as Map?)
                ?.map((k, v) => MapEntry(k as String, (v as num).toInt())) ??
            const {},
        sortOrder: j['sortOrder'] as int? ?? 0,
        updatedAt: j['updatedAt'] as int? ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );
}

/// 页面上的一个矩形，坐标归一化到 0~1（相对页面宽高），与缩放无关。
/// [page] 为空表示与所属批注同一页；跨页选中的文字会带上各自的页码。
class NormRect {
  final double l, t, r, b;
  final int? page;
  const NormRect(this.l, this.t, this.r, this.b, [this.page]);
  bool contains(double x, double y) => x >= l && x <= r && y >= t && y <= b;
  List<num> toJson() => [l, t, r, b, ?page];
  factory NormRect.fromJson(List<dynamic> j) => NormRect((j[0] as num).toDouble(), (j[1] as num).toDouble(),
      (j[2] as num).toDouble(), (j[3] as num).toDouble(), j.length > 4 ? (j[4] as num).toInt() : null);
}

/// 选中文字后添加的批注。
class Annotation implements SyncRecord {
  @override
  final String id;
  final String paperId;
  final int page;
  final String selectedText;
  final String note;
  final int color;
  final List<NormRect> rects;
  final int createdAt;
  @override
  final int updatedAt;
  @override
  final bool deleted;

  const Annotation({
    required this.id,
    required this.paperId,
    required this.page,
    required this.selectedText,
    this.note = '',
    this.color = 0xFFFFEB3B,
    this.rects = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deleted = false,
  });

  Annotation copyWith({String? note, int? color, bool? deleted}) => Annotation(
        id: id,
        paperId: paperId,
        page: page,
        selectedText: selectedText,
        note: note ?? this.note,
        color: color ?? this.color,
        rects: rects,
        createdAt: createdAt,
        updatedAt: nowMs(),
        deleted: deleted ?? this.deleted,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'paperId': paperId,
        'page': page,
        'selectedText': selectedText,
        'note': note,
        'color': color,
        'rects': rects.map((r) => r.toJson()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
        id: j['id'] as String,
        paperId: j['paperId'] as String,
        page: j['page'] as int,
        selectedText: j['selectedText'] as String? ?? '',
        note: j['note'] as String? ?? '',
        color: j['color'] as int? ?? 0xFFFFEB3B,
        rects: ((j['rects'] as List?) ?? []).map((e) => NormRect.fromJson(e as List)).toList(),
        createdAt: j['createdAt'] as int? ?? 0,
        updatedAt: j['updatedAt'] as int? ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );
}

enum InkTool { pen, highlighter }

/// 一笔墨迹。points 为 [x, y, pressure] 三元组展开的扁平数组，x/y 归一化到页面。
class InkStroke {
  final String id;
  final InkTool tool;
  final int color;

  /// 笔宽，相对页面宽度的比例（例如 0.003），保证不同屏幕/缩放下粗细一致。
  final double width;
  final List<double> points;

  const InkStroke({
    required this.id,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  int get pointCount => points.length ~/ 3;

  Map<String, dynamic> toJson() => {
        'id': id,
        'tool': tool.name,
        'color': color,
        'width': width,
        // 保留 4 位小数，减小同步文件体积。
        'points': points.map((p) => double.parse(p.toStringAsFixed(4))).toList(),
      };

  factory InkStroke.fromJson(Map<String, dynamic> j) => InkStroke(
        id: j['id'] as String,
        tool: InkTool.values.firstWhere((e) => e.name == j['tool'], orElse: () => InkTool.pen),
        color: j['color'] as int,
        width: (j['width'] as num).toDouble(),
        points: ((j['points'] as List?) ?? []).map((e) => (e as num).toDouble()).toList(),
      );
}

/// 一篇论文某一页上的全部墨迹。id = "$paperId:$page"。
class InkPage implements SyncRecord {
  final String paperId;
  final int page;
  final List<InkStroke> strokes;
  @override
  final int updatedAt;
  @override
  final bool deleted;

  const InkPage({
    required this.paperId,
    required this.page,
    this.strokes = const [],
    required this.updatedAt,
    this.deleted = false,
  });

  static String makeId(String paperId, int page) => '${paperId}_p$page';

  @override
  String get id => makeId(paperId, page);

  InkPage withStrokes(List<InkStroke> strokes) =>
      InkPage(paperId: paperId, page: page, strokes: strokes, updatedAt: nowMs());

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'paperId': paperId,
        'page': page,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'updatedAt': updatedAt,
        'deleted': deleted,
      };

  factory InkPage.fromJson(Map<String, dynamic> j) => InkPage(
        paperId: j['paperId'] as String,
        page: j['page'] as int,
        strokes: ((j['strokes'] as List?) ?? [])
            .map((e) => InkStroke.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: j['updatedAt'] as int? ?? 0,
        deleted: j['deleted'] as bool? ?? false,
      );
}

SyncRecord recordFromJson(RecordType type, Map<String, dynamic> j) => switch (type) {
      RecordType.paper => Paper.fromJson(j),
      RecordType.category => Category.fromJson(j),
      RecordType.annotation => Annotation.fromJson(j),
      RecordType.ink => InkPage.fromJson(j),
    };

SyncRecord recordFromString(RecordType type, String s) =>
    recordFromJson(type, jsonDecode(s) as Map<String, dynamic>);

List<String> _strList(dynamic v) => v is List ? v.map((e) => e.toString()).toList() : const [];
