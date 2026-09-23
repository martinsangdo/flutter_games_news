import 'news_source.dart';

class Article {
  const Article({
    required this.id,
    required this.source,
    required this.title,
    required this.link,
    required this.pubDate,
    required this.imageUrl,
    required this.contentHtml,
    this.categories = const [],
    this.isBookmarked = false,
  });

  /// `<source>:<site post id>`. Post ids are only unique within one site.
  final String id;
  final NewsSource source;
  final String title;
  final String link;

  /// ISO-8601 UTC timestamp.
  final String pubDate;
  final String imageUrl;

  /// Empty for rows loaded by list queries, which skip the heavy body column.
  final String contentHtml;

  /// Category slugs. Persisted as `,a,b,` so a category is one exact `LIKE`.
  final List<String> categories;
  final bool isBookmarked;

  DateTime? get publishedAt => DateTime.tryParse(pubDate);

  static String idFor(NewsSource source, Object sitePostId) =>
      '${source.name}:$sitePostId';

  Article withImage(String url) => Article(
    id: id,
    source: source,
    title: title,
    link: link,
    pubDate: pubDate,
    imageUrl: url,
    contentHtml: contentHtml,
    categories: categories,
    isBookmarked: isBookmarked,
  );

  factory Article.fromMap(Map<String, Object?> map) => Article(
    id: map['id'] as String,
    source: NewsSource.values.byName(map['source'] as String),
    title: (map['title'] as String?) ?? '',
    link: (map['link'] as String?) ?? '',
    pubDate: (map['pub_date'] as String?) ?? '',
    imageUrl: (map['image_url'] as String?) ?? '',
    contentHtml: (map['content_html'] as String?) ?? '',
    categories: [
      for (final slug in ((map['categories'] as String?) ?? '').split(','))
        if (slug.isNotEmpty) slug,
    ],
    isBookmarked: (map['is_bookmarked'] as int?) == 1,
  );

  Map<String, Object?> toInsertMap() => {
    'id': id,
    'source': source.name,
    'title': title,
    'link': link,
    'pub_date': pubDate,
    'image_url': imageUrl,
    'content_html': contentHtml,
    'categories': categories.isEmpty ? '' : ',${categories.join(',')},',
  };
}

String timeAgo(String isoDate, {DateTime? now}) {
  final published = DateTime.tryParse(isoDate);
  if (published == null) return '';
  final diff = (now ?? DateTime.now()).toUtc().difference(published.toUtc());
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
  if (diff.inDays < 365) return '${diff.inDays ~/ 30}mo ago';
  return '${diff.inDays ~/ 365}y ago';
}
