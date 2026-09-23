import 'dart:convert';

import 'package:games_news/models/news_source.dart';
import 'package:games_news/services/wordpress_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _post(
  int id, {
  int media = 0,
  String body = '<p>Hi</p>',
}) => {
  'id': id,
  'link': 'https://x/$id',
  'date_gmt': '2026-01-01T00:00:00',
  'title': {'rendered': 'Post $id'},
  'content': {'rendered': body},
  'featured_media': media,
};

String _feed(int firstId, int count) =>
    '<?xml version="1.0"?><rss version="2.0" '
    'xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>'
    '${[for (var i = 0; i < count; i++) '<item><title>Item ${firstId + i}</title>'
          '<link>https://s/${firstId + i}/</link>'
          '<pubDate>Wed, 23 Sep 2026 14:00:00 +0000</pubDate>'
          '<guid isPermaLink="false">https://s/?p=${firstId + i}</guid>'
          '<content:encoded><![CDATA[<p>Body</p>]]></content:encoded></item>'].join()}'
    '</channel></rss>';

void main() {
  test(
    'wccftech: resolves the topic slug once, filters by id, and batches featured images',
    () async {
      final requests = <Uri>[];
      final service = WordPressService(
        client: MockClient((request) async {
          requests.add(request.url);
          switch (request.url.path) {
            case '/wp-json/wp/v2/topics':
              return _json([
                {'id': 59411, 'slug': 'games'},
              ]);
            case '/wp-json/wp/v2/media':
              return _json([
                {'id': 11, 'source_url': 'https://cdn/eleven.jpg'},
                {'id': 12, 'source_url': 'https://cdn/twelve.jpg'},
              ]);
            default:
              return _json([_post(1, media: 11), _post(2, media: 12)]);
          }
        }),
      );

      final first = await service.fetchPosts(NewsSource.wccftech);
      await service.fetchPosts(NewsSource.wccftech);

      expect(first.map((a) => a.imageUrl), [
        'https://cdn/eleven.jpg',
        'https://cdn/twelve.jpg',
      ]);
      final lookups = requests.where((u) => u.path.endsWith('/topics'));
      expect(lookups, hasLength(1)); // cached after the first fetch
      expect(lookups.single.queryParameters['slug'], 'games');

      final posts = requests.where((u) => u.path.endsWith('/posts')).toList();
      expect(posts, hasLength(2));
      expect(posts.first.host, 'wccftech.com');
      expect(posts.first.queryParameters['topics'], '59411');
      // wccftech silently ignores `topics` without an explicit `orderby`.
      expect(posts.first.queryParameters['orderby'], 'date');
      expect(posts.first.queryParameters['per_page'], '30');
      expect(posts.first.queryParameters['_embed'], contains('wp:term'));

      final media = requests.firstWhere((u) => u.path.endsWith('/media'));
      expect(
        media.queryParameters['include'],
        '11,12',
      ); // one batch, not one per post
    },
  );

  test(
    'a failed media lookup keeps the posts, with their body image',
    () async {
      final service = WordPressService(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/topics')) {
            return _json([
              {'id': 5, 'slug': 'games'},
            ]);
          }
          if (request.url.path.endsWith('/media')) {
            return http.Response('nope', 500);
          }
          return _json([
            _post(
              1,
              media: 11,
              body: '<p>x</p><img src="https://cdn/body.jpg">',
            ),
          ]);
        }),
      );

      final posts = await service.fetchPosts(NewsSource.wccftech);
      expect(posts.single.imageUrl, 'https://cdn/body.jpg');
    },
  );

  test(
    'pcgamesn: embedded media needs no extra request; past the end is empty',
    () async {
      final requests = <Uri>[];
      final service = WordPressService(
        client: MockClient((request) async {
          requests.add(request.url);
          if (request.url.queryParameters['page'] == '3') {
            return _json({'code': 'rest_post_invalid_page_number'}, 400);
          }
          return _json([
            {
              ..._post(1, media: 8),
              '_embedded': {
                'wp:featuredmedia': [
                  {'source_url': 'https://cdn/embedded.jpg'},
                ],
              },
            },
          ]);
        }),
      );

      final page1 = await service.fetchPosts(NewsSource.pcgamesn);
      expect(page1.single.imageUrl, 'https://cdn/embedded.jpg');
      expect(requests, hasLength(1));
      expect(requests.single.host, 'www.pcgamesn.com');
      expect(requests.single.queryParameters.containsKey('page'), isFalse);
      expect(requests.single.queryParameters.containsKey('topics'), isFalse);

      expect(await service.fetchPosts(NewsSource.pcgamesn, page: 3), isEmpty);
    },
  );

  test(
    'siliconera: reads the RSS feed (never wp-json) and pages with ?paged',
    () async {
      final requests = <Uri>[];
      final service = WordPressService(
        client: MockClient((request) async {
          requests.add(request.url);
          final paged = int.parse(request.url.queryParameters['paged'] ?? '1');
          if (paged > 2) return http.Response('<html>not found</html>', 404);
          return http.Response(
            _feed(paged * 100, 15),
            200,
            headers: {'content-type': 'application/rss+xml; charset=UTF-8'},
          );
        }),
      );

      final page1 = await service.fetchPosts(NewsSource.siliconera);
      final page2 = await service.fetchPosts(NewsSource.siliconera, page: 2);
      final page3 = await service.fetchPosts(NewsSource.siliconera, page: 3);

      expect(page1, hasLength(15));
      expect(page1.first.id, 'siliconera:100');
      expect(page2.first.id, 'siliconera:200');
      expect(page3, isEmpty); // 404 past the last page = no more posts
      expect(requests.every((u) => u.path == '/feed/'), isTrue);
      expect(requests.every((u) => u.host == 'www.siliconera.com'), isTrue);
      expect(requests[0].queryParameters, isEmpty);
      expect(requests[1].queryParameters['paged'], '2');
    },
  );

  test('errors surface as FeedException without naming the site', () async {
    final blocked = WordPressService(
      client: MockClient(
        (_) async => http.Response('<html>blocked</html>', 403),
      ),
    );
    expect(
      blocked.fetchPosts(NewsSource.pcgamesn),
      throwsA(
        isA<FeedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('403'), isNot(contains('PCGamesN'))),
        ),
      ),
    );

    final notJson = WordPressService(
      client: MockClient((_) async => http.Response('<html>ok</html>', 200)),
    );
    expect(
      notJson.fetchPosts(NewsSource.pcgamesn),
      throwsA(isA<FeedException>()),
    );

    // A 200 challenge page where RSS was expected.
    expect(
      notJson.fetchPosts(NewsSource.siliconera),
      throwsA(
        isA<FeedException>().having(
          (e) => e.message,
          'message',
          equals('A news source sent an unexpected response.'),
        ),
      ),
    );

    final missingTopic = WordPressService(
      client: MockClient((_) async => _json([])),
    );
    expect(
      missingTopic.fetchPosts(NewsSource.wccftech),
      throwsA(isA<FeedException>()),
    );
  });
}
