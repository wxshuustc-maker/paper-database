import 'dart:math';

import '../models.dart';

/// 一个候选分类及其得分。
class CategoryScore {
  final Category category;
  final double score;
  const CategoryScore(this.category, this.score);

  @override
  String toString() => '${category.name}(${score.toStringAsFixed(2)})';
}

/// 基于关键词加权匹配的学科分类器，完全离线运行。
///
/// - 论文自带的关键词权重最高，其次是标题，最后是摘要。
/// - 多词短语比单个词更具体，权重更高。
/// - 每个分类除了预设关键词，还有 [Category.learnedKeywords]：
///   用户手动把论文改到某个分类时，论文的关键词会被学习进去，
///   之后同类论文会被分得更准。
class Classifier {
  static const double keywordWeight = 4.0;
  static const double titleWeight = 2.5;
  static const double abstractWeight = 1.0;

  /// 最高分低于该阈值时判定为"未分类"。
  static const double minScore = 1.5;

  /// 返回按得分从高到低排序的候选分类（只包含叶子分类且得分大于 0）。
  List<CategoryScore> rank(Paper paper, List<Category> categories) {
    final title = _normalize(paper.title);
    final abstract = _normalize(paper.abstract);
    final keywords = paper.keywords.map(_normalize).toList();
    final keywordText = keywords.join(' ; ');

    final parents = categories.map((c) => c.parentId).whereType<String>().toSet();
    final results = <CategoryScore>[];

    for (final cat in categories) {
      if (cat.deleted || cat.id == 'uncategorized') continue;
      // 只给叶子分类打分；没有子分类的用户自建顶级分类也算叶子。
      if (parents.contains(cat.id)) continue;

      var score = 0.0;
      final terms = <String, double>{};
      for (final k in cat.keywords) {
        terms[_normalize(k)] = 1.0;
      }
      cat.learnedKeywords.forEach((k, n) {
        final key = _normalize(k);
        terms[key] = max(terms[key] ?? 0, min(1.0 + log(n.toDouble()), 3.0));
      });

      terms.forEach((term, termBoost) {
        if (term.isEmpty) return;
        final specificity = _specificity(term);
        final inKeywords = _count(keywordText, term);
        final inTitle = _count(title, term);
        final inAbstract = _count(abstract, term);
        // 论文关键词与分类词完全一致时额外加分。
        final exactKeyword = keywords.contains(term) ? 1.0 : 0.0;
        final s = keywordWeight * (_damp(inKeywords) + exactKeyword) +
            titleWeight * _damp(inTitle) +
            abstractWeight * _damp(inAbstract);
        score += s * specificity * termBoost;
      });

      if (score > 0) results.add(CategoryScore(cat, score));
    }
    results.sort((a, b) => b.score.compareTo(a.score));
    return results;
  }

  /// 返回最佳分类的 ID，得分不足时返回 'uncategorized'。
  String classify(Paper paper, List<Category> categories) {
    final ranked = rank(paper, categories);
    if (ranked.isEmpty || ranked.first.score < minScore) return 'uncategorized';
    return ranked.first.category.id;
  }

  /// 用户把论文归入 [category] 后调用，学习论文关键词。
  /// 返回更新后的分类（调用方负责保存）。
  Category learn(Paper paper, Category category) {
    final learned = Map<String, int>.from(category.learnedKeywords);
    for (final k in paper.keywords) {
      final key = _normalize(k);
      if (key.length < 2) continue;
      learned[key] = (learned[key] ?? 0) + 1;
    }
    return category.copyWith(learnedKeywords: learned);
  }

  static double _damp(int count) => count == 0 ? 0 : 1 + log(count.toDouble());

  static double _specificity(String term) {
    if (_hasCjk(term)) {
      // 中文按字数衡量：2 字 1.0，4 字以上约 1.6。
      return 0.7 + 0.15 * min(term.length, 6);
    }
    final words = term.split(' ').length;
    final base = 1.0 + 0.6 * (words - 1);
    // 很短的英文词（如 "gan"、"cell"）容易误匹配，适当降权。
    return term.length <= 4 && words == 1 ? base * 0.7 : base;
  }

  static String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[‐-―]'), '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _hasCjk(String s) => RegExp(r'[一-鿿]').hasMatch(s);

  static final Map<String, RegExp> _patternCache = {};

  /// 统计 [term] 在 [text] 中出现的次数。
  /// 英文按词边界匹配（允许简单复数），中文按子串匹配。
  static int _count(String text, String term) {
    if (text.isEmpty) return 0;
    if (_hasCjk(term)) {
      var count = 0;
      var i = text.indexOf(term);
      while (i >= 0) {
        count++;
        i = text.indexOf(term, i + term.length);
      }
      return count;
    }
    final re = _patternCache.putIfAbsent(
        term,
        () => RegExp('(?<![a-z0-9])${RegExp.escape(term)}(?:s|es)?(?![a-z0-9])'));
    return re.allMatches(text).length;
  }
}
