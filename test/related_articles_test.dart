import 'package:games_news/models/article.dart';
import 'package:games_news/models/news_source.dart';
import 'package:games_news/services/related_articles.dart';
import 'package:flutter_test/flutter_test.dart';

Article _a(
  String id,
  String title, {
  List<String> categories = const [],
  int minute = 0,
}) => Article(
  id: id,
  source: NewsSource.pcgamesn,
  title: title,
  link: '',
  pubDate: DateTime.utc(2026, 1, 1, 0, minute).toIso8601String(),
  imageUrl: '',
  contentHtml: '',
  categories: categories,
);

void main() {
  final target = _a(
    '1',
    'Kit Harington joins Harry Potter series',
    categories: ['tv', 'news'],
  );

  test('title-word overlap outranks a shared broad category', () {
    final result = rankRelated(target, [
      _a('2', 'Weather report', categories: ['news'], minute: 5),
      _a('3', 'Harington speaks about Potter role', minute: 1),
    ]);
    expect(result.map((a) => a.id), ['3', '2']);
  });

  test('excludes itself; unrelated stories pad the list, newest first', () {
    final result = rankRelated(target, [
      target,
      _a('2', 'Other tv show', categories: ['tv'], minute: 1),
      _a('3', 'Nothing in common', minute: 3),
      _a('4', 'Also unrelated', minute: 9),
    ]);
    expect(result.map((a) => a.id), ['2', '4', '3']);
  });

  test('already-read stories sink below unread ones', () {
    final result = rankRelated(
      target,
      [
        _a('2', 'Harington interview', minute: 9), // related, read
        _a('3', 'Harry Potter casting', minute: 1), // related, unread
        _a('4', 'Unrelated fresh story', minute: 5), // unrelated, unread
        _a('5', 'Unrelated old read', minute: 7), // unrelated, read
      ],
      viewed: {'2', '5'},
    );
    expect(result.map((a) => a.id), ['3', '4', '2', '5']);
  });

  test('respects the limit', () {
    final many = [
      for (var i = 2; i < 12; i++) _a('$i', 'Harington $i', minute: i),
    ];
    expect(rankRelated(target, many, limit: 3), hasLength(3));
  });

  test('following the top suggestion never revisits a story early', () {
    // A tight cluster of near-identical titles is the worst case for loops:
    // each story is most related to the others.
    final pool = [
      for (var i = 0; i < 12; i++)
        _a('$i', 'Royal wedding photos $i', categories: ['royals'], minute: i),
    ];
    final viewed = <String>{};
    var current = pool.first;
    final path = <String>[];

    for (var step = 0; step < pool.length; step++) {
      viewed.add(current.id);
      path.add(current.id);
      final next = rankRelated(current, pool, viewed: viewed);
      expect(next, hasLength(5));
      current = next.first;
    }
    expect(path.toSet(), hasLength(pool.length));
  });

  test('a small pool still yields a full list without the current story', () {
    final result = rankRelated(target, [
      _a('2', 'A', minute: 1),
      _a('3', 'B', minute: 2),
    ]);
    expect(result, hasLength(2));
  });
}
