/// How a site's posts are read.
enum FeedKind {
  /// `/wp-json/wp/v2/posts`.
  wpRest,

  /// WordPress' public RSS feed (`/feed/?paged=N`) with full post bodies.
  rss,
}

/// A server-side topic filter on a taxonomy other than `category`. The numeric
/// id is resolved from [slug] at runtime, so it survives site re-imports.
class TermFilter {
  const TermFilter(this.restBase, this.slug);

  /// REST route of the taxonomy, which is also the posts query parameter
  /// (`/wp/v2/topics` -> `posts?topics=<id>`).
  final String restBase;
  final String slug;
}

/// The news sites the app reads. Everything that differs per site's API lives
/// here; how a site *looks* lives in `theme/source_style.dart`. Sites are an
/// implementation detail: their names are never shown to the reader.
enum NewsSource {
  wccftech(
    baseUrl: 'https://wccftech.com',
    kind: FeedKind.wpRest,
    // wccftech.com/topic/games/ is the custom "topics" taxonomy, not a category.
    topic: TermFilter('topics', 'games'),
    // The site's poll widget (Democracy) leaves a bare list of answers behind.
    junkSelectors: ['.democracy'],
  ),
  siliconera(
    baseUrl: 'https://www.siliconera.com',
    // Cloudflare answers every /wp-json request with HTTP 403; the RSS feed
    // is open and carries the full post bodies.
    kind: FeedKind.rss,
    // The feed's length is a WordPress site setting the client cannot change.
    pageSize: 15,
    // House ad for the paid ad-free tier, inline in the body.
    junkSelectors: ['.siliconera-plus-box'],
  ),
  pcgamesn(
    // The bare host answers with a 301 to www.
    baseUrl: 'https://www.pcgamesn.com',
    kind: FeedKind.wpRest,
  );

  const NewsSource({
    required this.baseUrl,
    required this.kind,
    this.topic,
    this.pageSize = 30,
    this.junkSelectors = const [],
  });

  final String baseUrl;
  final FeedKind kind;
  final TermFilter? topic;

  /// Posts per request. A shorter page means the site has nothing older.
  final int pageSize;

  /// CSS selectors of site widgets embedded in post bodies that only make
  /// sense on the website (polls, promo boxes) and are removed when cleaning.
  final List<String> junkSelectors;
}
