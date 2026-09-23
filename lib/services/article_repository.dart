import 'dart:async';

import '../db/app_database.dart';
import '../models/article.dart';
import '../models/game_category.dart';
import '../models/news_source.dart';
import 'image_cache_service.dart';
import 'related_articles.dart';
import 'wordpress_service.dart';

class ArticleRepository {
  ArticleRepository(this._db, this._api);

  final AppDatabase _db;
  final WordPressService _api;

  /// Stories opened this session; related lists steer away from them.
  final Set<String> _viewed = {};

  /// Cached articles (of every site) in [category], or all of them when null.
  /// Categories are matched in Dart, on whole words; see [GameCategory].
  Future<List<Article>> cachedFeed(
    GameCategory? category, {
    String? since,
  }) async {
    final articles = await _db.feed(since: since);
    return category == null
        ? articles
        : articles.where(category.matches).toList(growable: false);
  }

  /// Fetches one page of [source] into SQLite. Page 1 is a refresh and also
  /// purges beyond the cache cap; older pages (infinite scroll) do not, so the
  /// purge waits for the next refresh. Returns the posts the site returned
  /// (newest first; fewer than a full page means the end).
  /// Throws [FeedException] on network or site failure; the cache is untouched then.
  Future<List<Article>> fetchPage(NewsSource source, int page) async {
    final fresh = await _api.fetchPosts(source, page: page);
    await _db.saveFeed(fresh, purge: page == 1);
    unawaited(ImageCacheService.trim());
    return fresh;
  }

  Future<List<Article>> related(String id) async {
    _viewed.add(id);
    final target = await _db.article(id);
    if (target == null) return const [];
    return rankRelated(
      target,
      await _db.recent(excludeId: id),
      viewed: _viewed,
    );
  }

  Future<List<Article>> bookmarked() => _db.bookmarked();

  Future<Set<String>> bookmarkedIds() => _db.bookmarkedIds();

  Future<String> contentHtml(String id) => _db.contentHtml(id);

  Future<void> setBookmarked(String id, {required bool value}) =>
      _db.setBookmarked(id, value: value);
}
