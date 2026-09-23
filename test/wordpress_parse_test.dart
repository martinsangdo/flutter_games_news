import 'dart:convert';

import 'package:games_news/models/article.dart';
import 'package:games_news/models/news_source.dart';
import 'package:games_news/services/feed_parsers.dart';
import 'package:flutter_test/flutter_test.dart';

const _rss = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
<channel>
<title>Siliconera</title>
<item>
  <title>Persona &#8211; Super Live &amp; More</title>
  <link>https://www.siliconera.com/persona-super-live/</link>
  <pubDate>Wed, 23 Sep 2026 14:00:00 +0200</pubDate>
  <category><![CDATA[News]]></category>
  <category><![CDATA[Persona 5 Royal]]></category>
  <category><![CDATA[News]]></category>
  <guid isPermaLink="false">https://www.siliconera.com/?p=1123538</guid>
  <content:encoded><![CDATA[<p style="color:red">Atlus <em>announced</em> it.</p><img data-id="1" src="https://cdn.example/lead.jpg?resize=1024%2C576"><div class="siliconera-plus-box"><strong>Go Ad-Free</strong></div><p>End.</p>]]></content:encoded>
</item>
<item>
  <title>No guid, no date</title>
  <link>https://www.siliconera.com/second/</link>
  <content:encoded><![CDATA[<p>Second</p>]]></content:encoded>
</item>
<item><title>No link: skipped</title></item>
</channel>
</rss>''';

void main() {
  test('parsePosts maps a WordPress post with embedded featured media', () {
    final body = jsonEncode([
      {
        'id': 42,
        'date_gmt': '2026-01-02T03:04:05',
        'link': 'https://example.com/p/42',
        'title': {'rendered': 'Zelda&#8217;s &amp; Co'},
        'content': {'rendered': '<p style="color:red">Body</p>'},
        'featured_media': 9,
        '_embedded': {
          'wp:featuredmedia': [
            {
              'source_url': 'https://example.com/full.jpg',
              'media_details': {
                'sizes': {
                  'medium_large': {'source_url': 'https://example.com/ml.jpg'},
                },
              },
            },
          ],
        },
      },
      {
        'id': 43,
        'link': 'https://example.com/p/43',
        'title': {'rendered': 'No media'},
        'content': {'rendered': '<img src="https://example.com/in.jpg">'},
      },
      {'title': 'malformed, skipped'},
    ]);

    final parsed = parsePosts(NewsSource.pcgamesn, body);
    final articles = parsed.articles;
    expect(articles, hasLength(2));
    expect(articles[0].id, 'pcgamesn:42');
    expect(articles[0].source, NewsSource.pcgamesn);
    expect(articles[0].title, 'Zelda’s & Co');
    expect(articles[0].pubDate, '2026-01-02T03:04:05.000Z');
    expect(articles[0].imageUrl, 'https://example.com/ml.jpg');
    expect(articles[0].contentHtml, '<p>Body</p>');
    expect(articles[1].imageUrl, 'https://example.com/in.jpg');
    expect(parsed.pendingMedia, isEmpty);
  });

  test('a site that ignores _embed leaves featured media pending', () {
    final body = jsonEncode([
      {
        'id': 1,
        'link': 'https://wccftech.com/a/',
        'date_gmt': '2026-01-02T03:04:05',
        'title': {'rendered': 'Has featured image'},
        'content': {'rendered': '<p>No image in the body</p>'},
        'featured_media': 77,
      },
      {
        'id': 2,
        'link': 'https://wccftech.com/b/',
        'date_gmt': '2026-01-02T03:04:05',
        'title': {'rendered': 'No featured image'},
        'content': {'rendered': '<p>x</p>'},
        'featured_media': 0,
      },
    ]);

    final parsed = parsePosts(NewsSource.wccftech, body);
    expect(parsed.articles.map((a) => a.imageUrl), ['', '']);
    expect(parsed.pendingMedia, {'wccftech:1': 77});
  });

  test("a site's website-only widgets are removed from the body", () {
    final body = jsonEncode([
      {
        'id': 1,
        'link': 'https://wccftech.com/a/',
        'date_gmt': '2026-01-02T03:04:05',
        'title': {'rendered': 'Poll inside'},
        'content': {
          'rendered':
              '<p>Story</p><div class="democracy"><ul><li>Yes</li><li>No</li></ul></div>',
        },
      },
    ]);
    expect(
      parsePosts(NewsSource.wccftech, body).articles.single.contentHtml,
      '<p>Story</p>',
    );
    // The same markup is kept on a site that does not list the widget.
    expect(
      parsePosts(NewsSource.pcgamesn, body).articles.single.contentHtml,
      contains('Yes'),
    );
  });

  test(
    'parsePosts rejects non-array payloads such as an HTML challenge page',
    () {
      expect(
        () => parsePosts(NewsSource.wccftech, '{"code":"rest_disabled"}'),
        throwsFormatException,
      );
      expect(
        () => parsePosts(NewsSource.wccftech, '<!DOCTYPE html><html>'),
        throwsFormatException,
      );
    },
  );

  test('parseFeed maps RSS items: id, UTC date, categories, cleaned body', () {
    final articles = parseFeed(NewsSource.siliconera, _rss);
    expect(articles, hasLength(2)); // the linkless item is skipped

    final first = articles[0];
    expect(first.id, 'siliconera:1123538');
    expect(first.source, NewsSource.siliconera);
    expect(first.title, 'Persona – Super Live & More');
    expect(first.link, 'https://www.siliconera.com/persona-super-live/');
    expect(first.pubDate, '2026-09-23T12:00:00.000Z'); // +0200 -> UTC
    expect(first.categories, ['news', 'persona-5-royal']); // deduplicated
    expect(first.imageUrl, 'https://cdn.example/lead.jpg?resize=1024%2C576');
    expect(first.contentHtml, isNot(contains('style=')));
    expect(first.contentHtml, isNot(contains('Go Ad-Free'))); // house ad
    expect(first.contentHtml, contains('<em>announced</em>'));
    expect(first.contentHtml, contains('<p>End.</p>'));

    final second = articles[1];
    expect(second.id, 'siliconera:https://www.siliconera.com/second/');
    expect(second.title, 'No guid, no date');
    expect(DateTime.tryParse(second.pubDate), isNotNull);
  });

  test('a video-only post uses the YouTube thumbnail as its image', () {
    const rss =
        '<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/"><channel>'
        '<item><title>Trailer</title><link>https://www.siliconera.com/t/</link>'
        '<content:encoded><![CDATA[<p>Watch.</p><figure class="wp-block-embed"><div class="wp-block-embed__wrapper">'
        '<iframe src="https://www.youtube.com/embed/OKh9HaTEUfk?feature=oembed"></iframe></div></figure>]]></content:encoded>'
        '</item></channel></rss>';
    final article = parseFeed(NewsSource.siliconera, rss).single;
    expect(
      article.imageUrl,
      'https://img.youtube.com/vi/OKh9HaTEUfk/hqdefault.jpg',
    );
    expect(
      article.contentHtml,
      isNot(contains('iframe')),
    ); // still not rendered

    // A real picture in the body wins over the video thumbnail.
    final withPicture = rss.replaceFirst(
      '<p>Watch.</p>',
      '<p>Watch.</p><img src="https://cdn/pic.jpg">',
    );
    expect(
      parseFeed(NewsSource.siliconera, withPicture).single.imageUrl,
      'https://cdn/pic.jpg',
    );
  });

  test('parseFeed rejects anything that is not RSS', () {
    expect(
      () =>
          parseFeed(NewsSource.siliconera, '<html><body>blocked</body></html>'),
      throwsFormatException,
    );
    expect(
      () => parseFeed(NewsSource.siliconera, '<!DOCTYPE html><html>'),
      throwsFormatException,
    );
    expect(() => parseFeed(NewsSource.siliconera, ''), throwsFormatException);
  });

  test('parseMedia maps ids to card-sized urls', () {
    final urls = parseMedia(
      jsonEncode([
        {
          'id': 1,
          'source_url': 'https://cdn/full.jpg',
          'media_details': {
            'sizes': {
              'large': {'source_url': 'https://cdn/large.jpg'},
            },
          },
        },
        {'id': 2, 'source_url': 'https://cdn/only-full.jpg'},
        {'id': 3},
      ]),
    );
    expect(urls, {1: 'https://cdn/large.jpg', 2: 'https://cdn/only-full.jpg'});
    expect(() => parseMedia('{"code":"x"}'), throwsFormatException);
  });

  test('timeAgo buckets', () {
    final now = DateTime.utc(2026, 1, 10, 12);
    expect(timeAgo('2026-01-10T11:59:40Z', now: now), 'just now');
    expect(timeAgo('2026-01-10T11:15:00Z', now: now), '45m ago');
    expect(timeAgo('2026-01-10T07:00:00Z', now: now), '5h ago');
    expect(timeAgo('2026-01-07T12:00:00Z', now: now), '3d ago');
    expect(timeAgo('garbage', now: now), '');
  });
}
