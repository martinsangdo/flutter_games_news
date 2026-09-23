import 'package:games_news/models/article.dart';
import 'package:games_news/models/game_category.dart';
import 'package:games_news/models/news_source.dart';
import 'package:flutter_test/flutter_test.dart';

Article _a(String title, [List<String> categories = const []]) => Article(
  id: 'x:$title',
  source: NewsSource.pcgamesn,
  title: title,
  link: '',
  pubDate: '2026-01-01T00:00:00.000Z',
  imageUrl: '',
  contentHtml: '',
  categories: categories,
);

void main() {
  test('matches whole words only', () {
    expect(GameCategory.pc.matches(_a('Best PC games of the year')), isTrue);
    expect(
      GameCategory.pc.matches(_a('Meet the NPC who runs the shop')),
      isFalse,
    );
    expect(GameCategory.hardware.matches(_a('Nvidia RTX 5090 review')), isTrue);
    expect(
      GameCategory.hardware.matches(_a('The Pram Story')),
      isFalse,
    ); // "ram" inside a word
  });

  test('is case-insensitive and understands multi-word keywords', () {
    expect(
      GameCategory.playstation.matches(_a('PLAYSTATION plus is changing')),
      isTrue,
    );
    expect(
      GameCategory.xbox.matches(_a('Everything new on game pass')),
      isTrue,
    );
    expect(
      GameCategory.nintendo.matches(_a('Pokémon Legends gets a date')),
      isTrue,
    );
  });

  test("also looks at the site's own categories and tags", () {
    final article = _a('A big announcement', ['news', 'ps5', 'atlus']);
    expect(GameCategory.playstation.matches(article), isTrue);
    expect(GameCategory.xbox.matches(article), isFalse);
  });

  test('a story can be in several categories; of() picks the first', () {
    final article = _a('Review: Zelda on Switch 2 with a PS5 port rumour');
    expect(GameCategory.nintendo.matches(article), isTrue);
    expect(GameCategory.reviews.matches(article), isTrue);
    expect(GameCategory.of(article), GameCategory.playstation);
    expect(GameCategory.of(_a('Something unrelated')), isNull);
  });
}
