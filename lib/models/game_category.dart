import 'article.dart';

/// Reader-facing categories, shared by every news site. The sites' own
/// taxonomies do not line up (ids only, game names, game slugs), so a story
/// belongs to a category when a keyword appears, as a whole word, in its title
/// or in its site categories/tags.
enum GameCategory {
  pc('PC', ['pc', 'steam', 'steam deck', 'epic games', 'windows', 'valve']),
  playstation('PlayStation', [
    'playstation',
    'ps5',
    'ps4',
    'ps6',
    'psn',
    'sony',
  ]),
  xbox('Xbox', ['xbox', 'game pass', 'series x', 'series s']),
  nintendo('Nintendo', [
    'nintendo',
    'switch',
    'switch 2',
    'zelda',
    'mario',
    'pokemon',
    'pokémon',
    'splatoon',
    'kirby',
  ]),
  hardware('Hardware', [
    'gpu',
    'cpu',
    'nvidia',
    'geforce',
    'rtx',
    'amd',
    'radeon',
    'ryzen',
    'intel',
    'snapdragon',
    'graphics card',
    'ssd',
    'ram',
    'dram',
    'laptop',
    'handheld',
  ]),
  reviews('Reviews', ['review', 'reviews', 'preview', 'hands-on']);

  const GameCategory(this.label, this.keywords);

  final String label;
  final List<String> keywords;

  bool matches(Article article) => _patterns[this]!.hasMatch(
    '${article.title} ${article.categories.join(' ')}',
  );

  /// The first category [article] belongs to, for its label on a card.
  static GameCategory? of(Article article) {
    for (final category in values) {
      if (category.matches(article)) return category;
    }
    return null;
  }
}

final _patterns = {
  for (final category in GameCategory.values)
    category: RegExp(
      r'\b(?:' + category.keywords.map(RegExp.escape).join('|') + r')\b',
      caseSensitive: false,
    ),
};
