import '../models/article.dart';

const _stopWords = {
  'about',
  'after',
  'again',
  'also',
  'amid',
  'been',
  'before',
  'from',
  'have',
  'into',
  'just',
  'more',
  'over',
  'says',
  'said',
  'than',
  'that',
  'their',
  'them',
  'then',
  'they',
  'this',
  'what',
  'when',
  'where',
  'which',
  'while',
  'who',
  'will',
  'with',
  'would',
  'your',
  'first',
  'new',
  'its',
  'her',
  'his',
};

Set<String> _titleWords(String title) => {
  for (final word in title.toLowerCase().split(
    RegExp(r"[^a-z0-9\u00C0-\u024F]+"),
  ))
    if (word.length >= 4 && !_stopWords.contains(word)) word,
};

/// Picks the best [limit] stories to read after [target].
///
/// Candidates fall into tiers, best first:
/// 0. unread and related (shares a title word or category)
/// 1. unread, unrelated (newest first) - keeps the list full and fresh
/// 2. already read and related
/// 3. already read, unrelated
///
/// Within a tier: higher score first, then newer. A shared title word
/// (usually a game or franchise) counts three times a shared category, which
/// is often broad ("news").
///
/// Because every opened story is added to [viewed] and drops to the bottom,
/// repeatedly following the top suggestion visits every unread story before
/// any repeat, so readers can never get stuck bouncing between a few articles.
List<Article> rankRelated(
  Article target,
  List<Article> candidates, {
  int limit = 5,
  Set<String> viewed = const {},
}) {
  final words = _titleWords(target.title);
  final categories = target.categories.toSet();

  final scored = <(Article, int, int)>[]; // article, tier, score
  for (final candidate in candidates) {
    if (candidate.id == target.id) continue;
    final score =
        3 * _titleWords(candidate.title).intersection(words).length +
        candidate.categories.toSet().intersection(categories).length;
    final tier = (viewed.contains(candidate.id) ? 2 : 0) + (score > 0 ? 0 : 1);
    scored.add((candidate, tier, score));
  }

  scored.sort((a, b) {
    final byTier = a.$2.compareTo(b.$2);
    if (byTier != 0) return byTier;
    final byScore = b.$3.compareTo(a.$3);
    return byScore != 0 ? byScore : b.$1.pubDate.compareTo(a.$1.pubDate);
  });
  return [for (final (article, _, _) in scored.take(limit)) article];
}
