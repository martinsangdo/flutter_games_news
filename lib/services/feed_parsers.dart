import 'dart:convert';

import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart';

import '../models/article.dart';
import '../models/news_source.dart';
import 'html_cleaner.dart';

// Everything here is synchronous and top-level so it can run in a background
// isolate: decoding and cleaning a full page of posts must not block the UI.

/// One page of REST posts.
class ParsedPosts {
  const ParsedPosts(this.articles, this.pendingMedia);

  final List<Article> articles;

  /// Article id -> featured-media id, for posts whose image was not embedded
  /// in the response. Some sites ignore `_embed`; the service resolves these
  /// with one batched media request.
  final Map<String, int> pendingMedia;
}

/// Parses a `/wp-json/wp/v2/posts` response. Throws [FormatException] when the
/// body is not a JSON array (e.g. a bot-challenge page).
ParsedPosts parsePosts(NewsSource source, String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array of posts.');
  }

  final articles = <Article>[];
  final pendingMedia = <String, int>{};
  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    final article = _parsePost(source, item);
    if (article == null) continue;
    articles.add(article);

    final media = item['featured_media'];
    if (media is int && media > 0 && _embeddedImage(item).isEmpty) {
      pendingMedia[article.id] = media;
    }
  }
  return ParsedPosts(articles, pendingMedia);
}

/// Parses a WordPress RSS feed (`/feed/`). Throws [FormatException] when the
/// body is not RSS.
List<Article> parseFeed(NewsSource source, String body) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(body);
  } on XmlException catch (error) {
    throw FormatException(error.message);
  }
  if (document.rootElement.name.local != 'rss') {
    throw const FormatException('Expected an RSS feed.');
  }

  final articles = <Article>[];
  for (final item in document.findAllElements('item')) {
    final link = item.getElement('link')?.innerText.trim() ?? '';
    final guid = item.getElement('guid')?.innerText ?? '';
    final sitePostId =
        RegExp(r'[?&]p=(\d+)').firstMatch(guid)?.group(1) ?? link;
    if (link.isEmpty || sitePostId.isEmpty) continue;

    final title = item.getElement('title')?.innerText.trim() ?? '';
    final rawContent = item.getElement('content:encoded')?.innerText ?? '';
    final content = HtmlCleaner.clean(
      rawContent,
      junkSelectors: source.junkSelectors,
    );
    articles.add(
      Article(
        id: Article.idFor(source, sitePostId),
        source: source,
        title: title.isEmpty ? 'Untitled' : title,
        link: link,
        pubDate:
            _rssDate(item.getElement('pubDate')?.innerText ?? '') ??
            DateTime.now().toUtc().toIso8601String(),
        // RSS carries no featured image; the lead image is in the body.
        imageUrl: _bodyImage(rawContent, content),
        contentHtml: content,
        categories: {
          for (final category in item.findElements('category'))
            if (_slug(category.innerText).isNotEmpty) _slug(category.innerText),
        }.toList(),
      ),
    );
  }
  return articles;
}

/// Parses a `/wp-json/wp/v2/media?include=...` response into media id -> URL.
Map<int, String> parseMedia(String body) {
  final decoded = jsonDecode(body);
  if (decoded is! List) {
    throw const FormatException('Expected a JSON array of media.');
  }
  return {
    for (final item in decoded)
      if (item is Map && item['id'] is int && _mediaUrl(item).isNotEmpty)
        item['id'] as int: _mediaUrl(item),
  };
}

Article? _parsePost(NewsSource source, Map<String, dynamic> post) {
  final id = post['id'];
  final link = post['link'];
  if (id == null || link is! String) return null;

  final rawTitle = _rendered(post['title']);
  final title = html_parser.parseFragment(rawTitle).text?.trim() ?? '';
  final content = HtmlCleaner.clean(
    _rendered(post['content']),
    junkSelectors: source.junkSelectors,
  );

  final featured = _embeddedImage(post);
  return Article(
    id: Article.idFor(source, id),
    source: source,
    title: title.isEmpty ? 'Untitled' : title,
    link: link,
    pubDate: _publishedDate(post),
    imageUrl: featured.isNotEmpty
        ? featured
        : _bodyImage(_rendered(post['content']), content),
    contentHtml: content,
    categories: _categorySlugs(post),
  );
}

/// A card image taken from the body: its first picture, or else the
/// thumbnail of an embedded YouTube video (which cleaning removes), since
/// video-only news posts are common.
String _bodyImage(String rawHtml, String cleanedHtml) {
  final image = HtmlCleaner.firstImageUrl(cleanedHtml);
  if (image.isNotEmpty) return image;
  final video = _youtubeId.firstMatch(rawHtml)?.group(1);
  return video == null ? '' : 'https://img.youtube.com/vi/$video/hqdefault.jpg';
}

final _youtubeId = RegExp(
  r'(?:youtube(?:-nocookie)?\.com/embed/|youtu\.be/)([\w-]{11})',
);

String _rendered(Object? field) => field is Map && field['rendered'] is String
    ? field['rendered'] as String
    : '';

String _publishedDate(Map<String, dynamic> post) {
  final gmt = post['date_gmt'];
  if (gmt is String) {
    final parsed = DateTime.tryParse(gmt.endsWith('Z') ? gmt : '${gmt}Z');
    if (parsed != null) return parsed.toUtc().toIso8601String();
  }
  return DateTime.now().toUtc().toIso8601String();
}

String _embeddedImage(Map<String, dynamic> post) {
  final embedded = post['_embedded'];
  if (embedded is! Map) return '';
  final media = embedded['wp:featuredmedia'];
  if (media is! List || media.isEmpty || media.first is! Map) return '';
  return _mediaUrl(media.first as Map);
}

/// A card-sized rendition of a media item, falling back to the original.
String _mediaUrl(Map media) {
  final details = media['media_details'];
  if (details is Map && details['sizes'] is Map) {
    final sizes = details['sizes'] as Map;
    for (final name in const ['medium_large', 'large', 'full']) {
      final size = sizes[name];
      if (size is Map && size['source_url'] is String) {
        return size['source_url'] as String;
      }
    }
  }
  final source = media['source_url'];
  return source is String ? source : '';
}

/// Slugs of the `category` terms in the embedded `wp:term` groups (which also
/// hold tags and custom taxonomies).
List<String> _categorySlugs(Map<String, dynamic> post) {
  final embedded = post['_embedded'];
  final groups = embedded is Map ? embedded['wp:term'] : null;
  if (groups is! List) return const [];

  return [
    for (final group in groups)
      if (group is List)
        for (final term in group)
          if (term is Map &&
              term['taxonomy'] == 'category' &&
              term['slug'] is String)
            term['slug'] as String,
  ];
}

/// RSS only has category *names* ("Persona 5 Royal"); slugs match what the
/// REST API reports, so related-story ranking treats both alike.
String _slug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

const _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

final _rfc822 = RegExp(
  r'(\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})\s*([+-]\d{4})?',
);

/// `Wed, 23 Sep 2026 14:00:00 +0000` -> ISO-8601 UTC, or null if unparseable.
/// (`HttpDate` lives in dart:io, which the web build cannot use.)
String? _rssDate(String value) {
  final m = _rfc822.firstMatch(value);
  if (m == null) return null;
  final month = _months.indexOf(m[2]!.toLowerCase()) + 1;
  if (month == 0) return null;

  var utc = DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
  final zone = m[7];
  if (zone != null) {
    final offset = Duration(
      hours: int.parse(zone.substring(1, 3)),
      minutes: int.parse(zone.substring(3, 5)),
    );
    utc = zone.startsWith('-') ? utc.add(offset) : utc.subtract(offset);
  }
  return utc.toIso8601String();
}
