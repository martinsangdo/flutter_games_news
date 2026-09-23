import 'dart:io';

import 'package:games_news/db/app_database.dart';
import 'package:games_news/models/article.dart';
import 'package:games_news/models/news_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Article _article(
  int n, {
  NewsSource source = NewsSource.wccftech,
  String? title,
  DateTime? date,
  List<String> categories = const [],
}) => Article(
  id: Article.idFor(source, n),
  source: source,
  title: title ?? 'Story $n',
  link: 'https://example.com/$n',
  pubDate: (date ?? DateTime.utc(2026, 1, 1).add(Duration(minutes: n)))
      .toIso8601String(),
  imageUrl: '',
  contentHtml: '<p>Body $n</p>',
  categories: categories,
);

String _id(int n, [NewsSource source = NewsSource.wccftech]) =>
    Article.idFor(source, n);

extension on AppDatabase {
  Future<List<Article>> feedOf(NewsSource source) async => [
    for (final a in await feed())
      if (a.source == source) a,
  ];
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('games_news_test');
    addTearDown(() => dir.delete(recursive: true));
    db = await AppDatabase.open(p.join(dir.path, 'test.db'));
  });

  test(
    'purge keeps at most 60 unbookmarked articles and never touches bookmarks',
    () async {
      await db.saveFeed([for (var i = 0; i < 30; i++) _article(i)]);
      await db.setBookmarked(_id(0), value: true);
      await db.saveFeed([for (var i = 30; i < 80; i++) _article(i)]);
      await db.saveFeed([for (var i = 80; i < 100; i++) _article(i)]);

      final all = await db.feed();
      final unbookmarked = all.where((a) => !a.isBookmarked).toList();
      expect(unbookmarked, hasLength(60));
      expect(all.any((a) => a.id == _id(0) && a.isBookmarked), isTrue);
      // Oldest unbookmarked rows were purged; the newest batches survived.
      expect(all.any((a) => a.id == _id(1)), isFalse);
      expect(all.any((a) => a.id == _id(99)), isTrue);
    },
  );

  test(
    'the purge is per source: a busy site cannot evict the others',
    () async {
      await db.saveFeed([
        for (var i = 0; i < 10; i++) _article(i, source: NewsSource.siliconera),
      ]);
      await db.saveFeed([
        for (var i = 0; i < 90; i++)
          _article(
            i,
            source: NewsSource.wccftech,
            date: DateTime.utc(2026, 2, 1),
          ),
      ]);

      expect(await db.feedOf(NewsSource.wccftech), hasLength(60));
      // Every siliconera story is older than every wccftech story, yet stays.
      expect(await db.feedOf(NewsSource.siliconera), hasLength(10));
    },
  );

  test(
    'the same site post id in two sources are two different articles',
    () async {
      await db.saveFeed([
        _article(7, source: NewsSource.wccftech, title: 'From wccftech'),
        _article(7, source: NewsSource.pcgamesn, title: 'From pcgamesn'),
      ]);
      expect((await db.feed()).map((a) => a.title).toSet(), {
        'From wccftech',
        'From pcgamesn',
      });
      expect(
        (await db.feedOf(NewsSource.pcgamesn)).single.source,
        NewsSource.pcgamesn,
      );
    },
  );

  test(
    're-fetching an article updates content but keeps its bookmark',
    () async {
      await db.saveFeed([_article(1)]);
      await db.setBookmarked(_id(1), value: true);
      await db.saveFeed([_article(1, title: 'Edited title')]);

      final bookmarked = await db.bookmarked();
      expect(bookmarked.single.title, 'Edited title');
      expect(await db.bookmarkedIds(), {_id(1)});
      expect(await db.contentHtml(_id(1)), '<p>Body 1</p>');
    },
  );

  test('list queries omit the body and are ordered newest first', () async {
    await db.saveFeed([_article(1), _article(2), _article(3)]);
    final feed = await db.feed();
    expect(feed.map((a) => a.id), [_id(3), _id(2), _id(1)]);
    expect(feed.every((a) => a.contentHtml.isEmpty), isTrue);
  });

  test('feed filters by publish date', () async {
    await db.saveFeed([
      _article(1, source: NewsSource.wccftech),
      _article(2, source: NewsSource.siliconera),
      _article(3, source: NewsSource.wccftech),
    ]);
    expect((await db.feedOf(NewsSource.siliconera)).map((a) => a.id), [
      _id(2, NewsSource.siliconera),
    ]);
    expect((await db.feed()).map((a) => a.id), [
      _id(3),
      _id(2, NewsSource.siliconera),
      _id(1),
    ]);
    final since = DateTime.utc(2026, 1, 1, 0, 2).toIso8601String();
    expect((await db.feed(since: since)).map((a) => a.id), [
      _id(3),
      _id(2, NewsSource.siliconera),
    ]);
  });

  test('categories round-trip through the database', () async {
    await db.saveFeed([
      _article(1, categories: ['escape-from-tarkov', 'news']),
    ]);
    expect((await db.article(_id(1)))!.categories, [
      'escape-from-tarkov',
      'news',
    ]);
  });

  test(
    'a pre-games (v2) database is reset to the multi-source schema',
    () async {
      final dir = await Directory.systemTemp.createTemp('games_news_v2');
      addTearDown(() => dir.delete(recursive: true));
      final path = p.join(dir.path, 'v2.db');

      final v2 = await openDatabase(
        path,
        version: 2,
        onCreate: (db, _) => db.execute(
          'CREATE TABLE articles (id TEXT PRIMARY KEY, title TEXT, link TEXT, '
          'pub_date TEXT, image_url TEXT, content_html TEXT, '
          "categories TEXT DEFAULT '', is_bookmarked INTEGER DEFAULT 0, "
          'created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)',
        ),
      );
      await v2.insert('articles', {
        'id':
            '9', // an old celebrity-news row: no source column, unnamespaced id
        'title': 'Old row',
        'pub_date': '2026-01-01T00:00:00.000Z',
        'is_bookmarked': 1,
      });
      await v2.close();

      final upgraded = await AppDatabase.open(path);
      expect(await upgraded.feed(), isEmpty);
      expect(await upgraded.bookmarked(), isEmpty);
      await upgraded.saveFeed([_article(1, source: NewsSource.pcgamesn)]);
      expect(
        (await upgraded.feedOf(NewsSource.pcgamesn)).single.id,
        _id(1, NewsSource.pcgamesn),
      );
    },
  );

  test('older pages loaded by scrolling never evict newer articles', () async {
    // Page 1 (newest), then two older pages stored without purging.
    await db.saveFeed([for (var i = 100; i < 130; i++) _article(i)]);
    await db.saveFeed([
      for (var i = 70; i < 100; i++) _article(i),
    ], purge: false);
    await db.saveFeed([
      for (var i = 40; i < 70; i++) _article(i),
    ], purge: false);
    expect(await db.feed(), hasLength(90));

    // The next fresh fetch purges: the 60 newest by publish date survive.
    await db.saveFeed([for (var i = 100; i < 130; i++) _article(i)]);
    final numbers = (await db.feed()).map(
      (a) => int.parse(a.id.split(':').last),
    );
    expect(numbers, hasLength(60));
    expect(numbers.reduce((a, b) => a < b ? a : b), 70);
    expect(numbers.reduce((a, b) => a > b ? a : b), 129);
  });
}
