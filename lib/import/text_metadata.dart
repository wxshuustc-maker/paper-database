/// 从 PDF 前几页的纯文本中提取论文元数据（标题、摘要、关键词、DOI 等）。
///
/// 这是纯启发式解析，适用于大多数中英文期刊/会议论文的版式；
/// 解析不出的字段留空，用户可以在详情页补全。
class ExtractedMetadata {
  String title = '';
  String abstract = '';
  List<String> keywords = [];
  String doi = '';
  String arxivId = '';
  int? year;

  @override
  String toString() =>
      'title=$title\ndoi=$doi arxiv=$arxivId year=$year\nkeywords=$keywords\nabstract=$abstract';
}

final _doiRe = RegExp(r'\b(10\.\d{4,9}/[^\s"<>,;]+[^\s"<>,;.)\]])', caseSensitive: false);
final _arxivRe = RegExp(r'arXiv:\s*(\d{4}\.\d{4,5})(v\d+)?', caseSensitive: false);
final _yearRe = RegExp(r'\b(19[5-9]\d|20[0-4]\d)\b');

final _abstractStart = RegExp(
  r'(?:^|\n)\s*(?:a\s?b\s?s\s?t\s?r\s?a\s?c\s?t|summary|摘\s*要)\s*[:：.—\-–]?\s*',
  caseSensitive: false,
);

final _keywordsStart = RegExp(
  r'(?:^|\n|\s)(?:key\s*-?\s*words?|index\s+terms|关\s*键\s*词|关键字)\s*[:：.—\-–]*\s*',
  caseSensitive: false,
);

final _sectionEnd = RegExp(
  r'\n\s*(?:(?:1|I)\.?\s+introduction|introduction\s*\n|1\s*引\s*言|一、|引\s*言|ccs concepts|acm reference format|'
  r'(?:1|I)\s*\.?\s*INTRODUCTION|中图分类号|文献标识码|background\s*\n)',
  caseSensitive: false,
);

const _titleBlacklist = [
  'arxiv', 'journal', 'vol.', 'volume', 'doi', 'http', 'www.', '©', 'copyright', 'received',
  'accepted', 'preprint', 'proceedings', 'conference', 'issn', 'published', 'licensed',
  'university', 'department', '@', 'page', '学报', '期刊', '收稿日期', '基金项目',
];

ExtractedMetadata extractMetadataFromText(String text) {
  final m = ExtractedMetadata();
  final normalized = text.replaceAll('\r', '\n').replaceAll(RegExp(r'[ \t ]+'), ' ');

  final doi = _doiRe.firstMatch(normalized);
  if (doi != null) m.doi = doi.group(1)!;
  final arxiv = _arxivRe.firstMatch(normalized);
  if (arxiv != null) m.arxivId = arxiv.group(1)!;
  final year = _yearRe.firstMatch(normalized);
  if (year != null) m.year = int.parse(year.group(1)!);

  m.title = _guessTitle(normalized);
  m.abstract = _extractAbstract(normalized);
  m.keywords = _extractKeywords(normalized);
  return m;
}

String _guessTitle(String text) {
  final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).take(25).toList();
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lower = line.toLowerCase();
    if (line.length < 8 || line.length > 250) continue;
    if (_titleBlacklist.any(lower.contains)) continue;
    if (_abstractStart.hasMatch('\n$line')) break;
    // 大部分是数字/符号的行（页眉、日期）跳过。
    final letters = RegExp(r'[A-Za-z一-鿿]').allMatches(line).length;
    if (letters < line.length * 0.6) continue;
    var title = line;
    // 标题折行：最多再拼接两行。
    for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
      if (!_continuesTitle(title, lines[j])) break;
      title = _hasCjkText(title) ? '$title${lines[j]}' : '$title ${lines[j]}';
    }
    return title;
  }
  return '';
}

bool _hasCjkText(String s) => RegExp(r'[\u4e00-\u9fff]').hasMatch(s);

/// 判断 [next] 是否是标题 [title] 的折行，而不是作者行或正文。
bool _continuesTitle(String title, String next) {
  if (RegExp(r'[.。:：;；!?]$').hasMatch(title)) return false;
  if (next.length < 3 || next.length > 200) return false;
  if (_abstractStart.hasMatch('\n$next')) return false;
  final lower = next.toLowerCase();
  if (_titleBlacklist.any(lower.contains)) return false;
  // 作者行常见特征：上标数字、星号、逗号分隔、邮箱。
  if (RegExp(r'[*†‡§0-9@]').hasMatch(next) || next.contains(',') || next.contains('，')) return false;
  if (_hasCjkText(title)) {
    // 中文标题一般较长才会折行；作者行通常是带空格的短姓名。
    return title.length >= 18 && !next.contains(' ') && next.length >= 4;
  }
  if (RegExp(r'^[a-z]').hasMatch(next)) return true;
  // 英文标题续行：多数单词首字母大写或是虚词。
  final words = next.split(' ');
  final titled = words.where((w) => RegExp(r'^[A-Z(]').hasMatch(w) || RegExp(r'^(of|for|and|the|in|on|with|via|to|a|an|from|by|at|as|is)$').hasMatch(w)).length;
  return words.length >= 2 && titled >= words.length * 0.8 && words.length <= 14;
}

String _extractAbstract(String text) {
  final start = _abstractStart.firstMatch(text);
  if (start == null) return '';
  var rest = text.substring(start.end);
  var end = rest.length;
  final kw = _keywordsStart.firstMatch(rest);
  if (kw != null && kw.start < end) end = kw.start;
  final sec = _sectionEnd.firstMatch(rest);
  if (sec != null && sec.start < end) end = sec.start;
  rest = rest.substring(0, end.clamp(0, 4000));
  return _joinLines(rest);
}

List<String> _extractKeywords(String text) {
  final start = _keywordsStart.firstMatch(text);
  if (start == null) return [];
  var rest = text.substring(start.end);
  // 关键词一般不超过两三行，遇到空行、章节标题或句号结束。
  final stop = RegExp(r'\n\s*\n|\n\s*(?:1|I)\.?\s+[A-Z]|\n\s*(?:1\s*)?引\s*言|中图分类号|\n\s*introduction', caseSensitive: false)
      .firstMatch(rest);
  rest = rest.substring(0, stop?.start ?? rest.length);
  if (rest.length > 400) rest = rest.substring(0, 400);
  rest = _joinLines(rest);
  final dot = rest.indexOf(RegExp(r'\.\s|。'));
  if (dot > 0) rest = rest.substring(0, dot);
  return rest
      .split(RegExp(r'[,;，；、·•]|\s{2,}| - '))
      .map((s) => s.trim().replaceAll(RegExp(r'[.。]+$'), ''))
      .where((s) => s.length >= 2 && s.length <= 60)
      .toSet()
      .take(12)
      .toList();
}

/// 把 PDF 里的硬换行合并成正常段落，处理英文断词连字符。
String _joinLines(String s) {
  return s
      .replaceAllMapped(RegExp(r'([a-z])-\n([a-z])'), (m) => '${m[1]}${m[2]}')
      .replaceAllMapped(RegExp(r'([一-鿿])\n([一-鿿])'), (m) => '${m[1]}${m[2]}')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}
