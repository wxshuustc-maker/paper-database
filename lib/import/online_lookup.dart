import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// 联网补全的元数据，字段为空表示没查到。
class OnlineMetadata {
  String title = '';
  List<String> authors = [];
  int? year;
  String venue = '';
  String abstract = '';
  List<String> subjects = [];
}

/// 通过 DOI（Crossref）或 arXiv ID 查询更准确的元数据。
/// 任何网络错误都静默返回 null，不影响离线导入。
class OnlineLookup {
  final http.Client client;
  OnlineLookup([http.Client? client]) : client = client ?? http.Client();

  static const _timeout = Duration(seconds: 8);

  Future<OnlineMetadata?> byDoi(String doi) async {
    try {
      final res = await client
          .get(Uri.parse('https://api.crossref.org/works/${Uri.encodeComponent(doi)}'),
              headers: {'User-Agent': 'PaperLibrary/1.0 (personal paper manager)'})
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final msg = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['message'] as Map;
      final m = OnlineMetadata();
      m.title = _first(msg['title']);
      m.venue = _first(msg['container-title']);
      m.authors = ((msg['author'] as List?) ?? [])
          .map((a) => [a['given'], a['family']].whereType<String>().join(' ').trim())
          .where((s) => s.isNotEmpty)
          .cast<String>()
          .toList();
      final parts = (msg['issued'] ?? msg['published'])?['date-parts'];
      if (parts is List && parts.isNotEmpty && parts[0] is List && parts[0].isNotEmpty) {
        m.year = parts[0][0] as int?;
      }
      final abs = msg['abstract'];
      if (abs is String) m.abstract = abs.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      m.subjects = ((msg['subject'] as List?) ?? []).map((e) => e.toString()).toList();
      return m;
    } catch (_) {
      return null;
    }
  }

  Future<OnlineMetadata?> byArxiv(String id) async {
    try {
      final res = await client
          .get(Uri.parse('https://export.arxiv.org/api/query?id_list=$id'))
          .timeout(_timeout);
      if (res.statusCode != 200) return null;
      final doc = XmlDocument.parse(utf8.decode(res.bodyBytes));
      final entry = doc.findAllElements('entry').firstOrNull;
      if (entry == null) return null;
      String text(String name) =>
          (entry.getElement(name)?.innerText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final m = OnlineMetadata();
      m.title = text('title');
      m.abstract = text('summary');
      m.venue = 'arXiv';
      m.year = int.tryParse(text('published').split('-').first);
      m.authors = entry
          .findElements('author')
          .map((a) => a.getElement('name')?.innerText.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      m.subjects = entry
          .findElements('category')
          .map((c) => c.getAttribute('term') ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      return m;
    } catch (_) {
      return null;
    }
  }

  static String _first(dynamic v) => v is List && v.isNotEmpty ? v.first.toString() : '';
}

/// arXiv 学科代码到内置分类 ID 的映射，arXiv 论文可以直接据此分类。
const Map<String, String> arxivCategoryMap = {
  'cs.LG': 'cs.ml', 'stat.ML': 'cs.ml', 'cs.AI': 'cs.ml', 'cs.NE': 'cs.ml',
  'cs.CV': 'cs.cv', 'eess.IV': 'cs.cv',
  'cs.CL': 'cs.cl', 'cs.IR': 'cs.cl', 'eess.AS': 'cs.cl', 'cs.SD': 'cs.cl',
  'cs.DC': 'cs.sys', 'cs.OS': 'cs.sys', 'cs.NI': 'cs.sys', 'cs.DB': 'cs.sys', 'cs.AR': 'cs.sys', 'cs.PF': 'cs.sys',
  'cs.SE': 'cs.se', 'cs.PL': 'cs.se', 'cs.LO': 'cs.se',
  'cs.CR': 'cs.cr',
  'cs.HC': 'cs.hci', 'cs.GR': 'cs.hci',
  'cs.RO': 'cs.ro', 'cs.MA': 'cs.ro',
  'cs.DS': 'cs.theory', 'cs.CC': 'cs.theory', 'cs.DM': 'cs.theory', 'cs.GT': 'cs.theory', 'quant-ph': 'phys.quant',
  'math.AG': 'math.pure', 'math.AT': 'math.pure', 'math.NT': 'math.pure', 'math.GT': 'math.pure',
  'math.DG': 'math.pure', 'math.GR': 'math.pure', 'math.RA': 'math.pure', 'math.CO': 'math.pure',
  'math.ST': 'math.applied', 'stat.ME': 'math.applied', 'stat.TH': 'math.applied', 'math.NA': 'math.applied',
  'math.OC': 'math.applied', 'math.PR': 'math.applied', 'math.AP': 'math.applied', 'stat.AP': 'math.applied',
  'cond-mat': 'phys.cond', 'physics.optics': 'phys.quant', 'physics.atom-ph': 'phys.quant',
  'hep-th': 'phys.hep', 'hep-ph': 'phys.hep', 'hep-ex': 'phys.hep', 'nucl-th': 'phys.hep', 'gr-qc': 'phys.astro',
  'astro-ph': 'phys.astro',
  'q-bio': 'bio.mol', 'q-bio.NC': 'bio.neuro', 'q-bio.PE': 'bio.eco',
  'eess.SP': 'eng.ee', 'eess.SY': 'eng.control', 'cs.SY': 'eng.control',
  'econ': 'econ.econ', 'q-fin': 'econ.econ',
  'physics.ao-ph': 'earth.general', 'physics.geo-ph': 'earth.general',
  'physics.chem-ph': 'chem.general', 'cond-mat.mtrl-sci': 'mat.general',
  'physics.med-ph': 'med.imaging', 'cs.CY': 'soc.soc', 'physics.soc-ph': 'soc.soc',
};

/// 根据 arXiv 主分类找到内置分类，找不到返回 null。
String? categoryFromArxiv(List<String> subjects) {
  for (final s in subjects) {
    if (arxivCategoryMap.containsKey(s)) return arxivCategoryMap[s];
    final prefix = s.split('.').first;
    if (arxivCategoryMap.containsKey(prefix)) return arxivCategoryMap[prefix];
  }
  return null;
}
