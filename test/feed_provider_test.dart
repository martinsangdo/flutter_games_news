import 'dart:convert';
import 'dart:io';

import 'package:games_news/db/app_database.dart';
import 'package:games_news/models/game_category.dart';
import 'package:games_news/models/news_source.dart';
import 'package:games_news/providers/app_providers.dart';
import 'package:games_news/providers/feed_provider.dart';
import 'package:games_news/services/wordpress_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// How a fake site publishes: [total] posts, newest first, [step] apart.
class _Site {
  const _Site(this.total, this.step);

  final int total;
  final Duration step;

  DateTime date(int i) => _newest.subtract(step * i);

  /// Posts published at or after [since].
  int newerThan(DateTime since) => [
    for (var i = 0; i < total; i++)
      if (!date(i).isBefore(since)) i,
  ].length;
}

final _newest = DateTime.utc(2026, 1, 10, 12);

/// Every fifth post is about the PS5, so category tabs have something to match.
String _title(int i) => 'Post ${i + 1}${i % 5 == 0 ? ' PS5' : ''}';

const _sites = {
  NewsSource.wccftech: _Site(60, Duration(seconds: 30)), // REST, 30 / page
  NewsSource.pcgamesn: _Site(40, Duration(minutes: 1)), // REST, 30 / page
  NewsSource.siliconera: _Site(30, Duration(minutes: 4)), // RSS, 15 / page
};

const _hosts = {
  'wccftech.com': NewsSource.wccftech,
  'www.pcgamesn.com': NewsSource.pcgamesn,
  'www.siliconera.com': NewsSource.siliconera,
};

/// Fake wccftech, pcgamesn and siliconera.
class _FakeWeb {
  /// `(site, page)` for every posts / feed request.
  final requests = <(NewsSource, int)>[];
  final failing = <NewsSource>{};
  final failPage2 = <NewsSource>{};

  List<int> pages(NewsSource site) => [
    for (final (s, page) in requests)
      if (s == site) page,
  ];

  Future<http.Response> handle(http.Request request) async {
    final site = _hosts[request.url.host]!;
    if (failing.contains(site)) return http.Response('boom', 500);

    if (request.url.path.endsWith('/topics')) {
      return http.Response(
        jsonEncode([
          {'id': 1, 'slug': 'games'},
        ]),
        200,
      );
    }

    final rss = site.kind == FeedKind.rss;
    final page = int.parse(
      request.url.queryParameters[rss ? 'paged' : 'page'] ?? '1',
    );
    requests.add((site, page));
    if (page == 2 && failPage2.contains(site)) {
      return http.Response('boom', 500);
    }

    final spec = _sites[site]!;
    final first = (page - 1) * site.pageSize;
    if (first >= spec.total) {
      return rss
          ? http.Response('<html>not found</html>', 404)
          : http.Response('{"code":"rest_post_invalid_page_number"}', 400);
    }
    final count = (spec.total - first).clamp(0, site.pageSize);
    return http.Response(
      rss ? _rss(site, spec, first, count) : _rest(site, spec, first, count),
      200,
    );
  }

  String _rest(NewsSource site, _Site spec, int first, int count) =>
      jsonEncode([
        for (var i = first; i < first + count; i++)
          {
            'id': i + 1,
            'link': 'https://${site.name}/${i + 1}',
            'date_gmt': spec.date(i).toIso8601String().replaceAll('Z', ''),
            'title': {'rendered': _title(i)},
            'content': {'rendered': '<p>Body</p>'},
          },
      ]);

  String _rss(NewsSource site, _Site spec, int first, int count) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '<?xml version="1.0"?><rss version="2.0" '
        'xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>'
        '${[for (var i = first; i < first + count; i++) '<item><title>${_title(i)}</title>'
              '<link>https://${site.name}/${i + 1}</link>'
              '<pubDate>Sat, ${spec.date(i).day} Jan 2026 ${two(spec.date(i).hour)}:${two(spec.date(i).minute)}:${two(spec.date(i).second)} +0000</pubDate>'
              '<guid isPermaLink="false">https://${site.name}/?p=${i + 1}</guid>'
              '<content:encoded><![CDATA[<p>Body</p>]]></content:encoded></item>'].join()}'
        '</channel></rss>';
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late _FakeWeb web;
  late ProviderContainer container;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('games_news_feed');
    addTearDown(() => dir.delete(recursive: true));
    final db = await AppDatabase.open(p.join(dir.path, 'feed.db'));

    web = _FakeWeb();
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        wordPressServiceProvider.overrideWithValue(
          WordPressService(client: MockClient(web.handle)),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(feedProvider, (_, _) {}); // keep the notifier alive
  });

  Future<void> until(bool Function(FeedState) done) async {
    for (var i = 0; i < 500; i++) {
      if (done(container.read(feedProvider))) return;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail(
      'condition not reached; state: ${container.read(feedProvider).articles.length} articles',
    );
  }

  FeedState state() => container.read(feedProvider);
  FeedNotifier notifier() => container.read(feedProvider.notifier);

  /// The list must be a gapless run: every post of every site that is at
  /// least as new as the oldest one shown is shown.
  void expectContiguous() {
    final articles = state().articles;
    final oldest = articles
        .map((a) => a.publishedAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    for (final entry in _sites.entries) {
      expect(
        articles.where((a) => a.source == entry.key),
        hasLength(entry.value.newerThan(oldest)),
        reason: '${entry.key.name} has a gap',
      );
    }
    final dates = articles.map((a) => a.pubDate).toList();
    expect(dates, [...dates]..sort((a, b) => b.compareTo(a)));
  }

  test(
    'refresh fetches every site in parallel and merges them by date',
    () async {
      await until((s) => !s.syncing);
      expect(web.pages(NewsSource.wccftech), [1]);
      expect(web.pages(NewsSource.pcgamesn), [1]);
      expect(web.pages(NewsSource.siliconera), [1]);

      expect(state().category, isNull);
      expect(state().error, isNull);
      expect(
        state().articles.map((a) => a.source).toSet(),
        NewsSource.values.toSet(),
      );
      // wccftech posts fastest, so its 30 posts reach back the least; the
      // window is only as deep as that, and has no gaps for the other sites.
      expectContiguous();
    },
  );

  test('scrolling fetches only the site that limits the window', () async {
    await until((s) => !s.syncing);
    web.requests.clear();

    await notifier().loadMore();
    expect(web.requests, [(NewsSource.wccftech, 2)]);
    expectContiguous();

    // Now pcgamesn reaches back the least.
    await notifier().loadMore();
    expect(web.requests.last, (NewsSource.pcgamesn, 2));
    expect(web.requests, hasLength(2));
    expectContiguous();
  });

  test(
    'scrolling to the end shows every story once, then stops asking',
    () async {
      await until((s) => !s.syncing);
      for (var i = 0; i < 30 && !state().reachedEnd; i++) {
        await notifier().loadMore();
        expectContiguous();
      }

      expect(state().reachedEnd, isTrue);
      expect(state().articles, hasLength(60 + 40 + 30));
      expect(state().articles.map((a) => a.id).toSet(), hasLength(130));

      final requests = web.requests.length;
      await notifier().loadMore();
      expect(web.requests, hasLength(requests));
    },
  );

  test(
    'a failed page keeps the list, reports the error, and retries the same page',
    () async {
      await until((s) => !s.syncing);
      final before = state().articles.length;
      web.failPage2.add(NewsSource.wccftech); // the site limiting the window

      await notifier().loadMore();
      expect(state().articles, hasLength(before));
      expect(state().loadMoreError, isNotNull);
      expect(state().loadingMore, isFalse);
      expect(state().reachedEnd, isFalse);

      web.failPage2.clear();
      await notifier().loadMore();
      expect(state().loadMoreError, isNull);
      expect(state().articles.length, greaterThan(before));
      expect(web.pages(NewsSource.wccftech), [1, 2, 2]);
    },
  );

  test(
    'refresh after scrolling returns to the newest window, not a jump',
    () async {
      await until((s) => !s.syncing);
      final firstWindow = state().articles.length;
      await notifier().loadMore();
      await notifier().loadMore();
      expect(state().articles.length, greaterThan(firstWindow));

      await notifier().refresh();
      expect(state().articles, hasLength(firstWindow));
      expect(state().loadMoreError, isNull);
      expectContiguous();
    },
  );

  group('categories', () {
    test(
      'switching is a local filter: no request, only matching stories',
      () async {
        await until((s) => !s.syncing);
        final all = state().articles;
        web.requests.clear();

        await notifier().selectCategory(GameCategory.playstation);

        expect(web.requests, isEmpty);
        expect(state().category, GameCategory.playstation);
        expect(state().syncing, isFalse);
        expect(state().articles, isNotEmpty);
        expect(state().articles.every((a) => a.title.contains('PS5')), isTrue);
        expect(
          state().articles.map((a) => a.id),
          all.where(GameCategory.playstation.matches).map((a) => a.id),
        );

        await notifier().selectCategory(null);
        expect(state().articles.map((a) => a.id), all.map((a) => a.id));
      },
    );

    test('scrolling inside a category pages the same stream', () async {
      await until((s) => !s.syncing);
      await notifier().selectCategory(GameCategory.playstation);
      final before = state().articles.length;

      web.requests.clear();
      await notifier().loadMore();

      expect(web.requests, isNotEmpty);
      expect(state().articles.length, greaterThan(before));
      expect(state().articles.every((a) => a.title.contains('PS5')), isTrue);
    });

    test('switching category mid-load discards the stale response', () async {
      await until((s) => !s.syncing);
      final pending = notifier().loadMore();
      await notifier().selectCategory(GameCategory.xbox);
      await pending;

      expect(state().category, GameCategory.xbox);
      expect(state().loadingMore, isFalse);
      expect(state().syncing, isFalse);
    });
  });

  group('failures', () {
    test(
      'a site that fails to refresh is reported without naming it; the others still show',
      () async {
        web.failing.add(NewsSource.siliconera);
        await until((s) => !s.syncing);

        expect(state().error?.message, "Some stories couldn't be refreshed.");
        expect(state().articles, isNotEmpty);
        expect(
          state().articles.any((a) => a.source == NewsSource.siliconera),
          isFalse,
        );

        // Scrolling never asks the failed site for older pages.
        web.requests.clear();
        await notifier().loadMore();
        await notifier().loadMore();
        expect(web.pages(NewsSource.siliconera), isEmpty);
      },
    );

    test(
      'when every site fails the cached list stays and the error shows',
      () async {
        await until((s) => !s.syncing);
        final before = state().articles.map((a) => a.id).toList();

        web.failing.addAll(NewsSource.values);
        await notifier().refresh();

        expect(state().syncing, isFalse);
        expect(state().error, isNotNull);
        expect(state().articles.map((a) => a.id), before);
      },
    );
  });
}
