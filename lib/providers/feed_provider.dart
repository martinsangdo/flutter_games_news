import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../models/article.dart';
import '../models/game_category.dart';
import '../models/news_source.dart';
import '../services/wordpress_service.dart';
import 'app_providers.dart';

class FeedState {
  const FeedState({
    this.category,
    this.articles = const [],
    this.syncing = true,
    this.error,
    this.loadingMore = false,
    this.reachedEnd = false,
    this.loadMoreError,
  });

  /// The selected tab; null is "All".
  final GameCategory? category;
  final List<Article> articles;

  /// A refresh (page 1) is in flight.
  final bool syncing;

  /// The last refresh failed; [articles] still holds whatever is cached.
  final FeedException? error;

  /// An infinite-scroll page is in flight.
  final bool loadingMore;

  /// No older articles can be loaded for this tab.
  final bool reachedEnd;

  /// The last infinite-scroll page failed; scrolling again or tapping retry
  /// tries the same page again.
  final FeedException? loadMoreError;

  FeedState copyWith({
    List<Article>? articles,
    bool? loadingMore,
    bool? reachedEnd,
    FeedException? loadMoreError,
    bool clearLoadMoreError = false,
  }) => FeedState(
    category: category,
    articles: articles ?? this.articles,
    syncing: syncing,
    error: error,
    loadingMore: loadingMore ?? this.loadingMore,
    reachedEnd: reachedEnd ?? this.reachedEnd,
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );
}

final feedProvider = NotifierProvider<FeedNotifier, FeedState>(
  FeedNotifier.new,
);

/// How far one site has been read: pages fetched and the oldest post seen.
class _Cursor {
  _Cursor(this.source);

  final NewsSource source;
  int page = 1;

  /// Publish date (ISO strings compare chronologically) of the oldest post
  /// fetched so far.
  String? oldest;

  /// Nothing older can be fetched (last page reached), or the site failed.
  bool ended = false;

  void advance(List<Article> fetched) {
    final fetchedOldest = _oldest(fetched);
    if (fetchedOldest != null &&
        (oldest == null || fetchedOldest.compareTo(oldest!) < 0)) {
      oldest = fetchedOldest;
    }
    ended = fetched.length < source.pageSize;
  }

  static String? _oldest(List<Article> articles) => articles.isEmpty
      ? null
      : articles
            .map((a) => a.pubDate)
            .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
}

class FeedNotifier extends Notifier<FeedState> {
  /// Incremented on every refresh / tab change so a slow response for an
  /// earlier one can never overwrite the current list.
  int _generation = 0;

  /// One cursor per site. Empty until the first refresh completes.
  List<_Cursor> _cursors = const [];

  /// How many consecutive pages may add nothing visible (already cached, or
  /// outside the selected category) before giving up.
  static const _maxEmptyPages = 4;

  @override
  FeedState build() {
    Future.microtask(() => _showCachedThenSync(null));
    return const FeedState();
  }

  /// Categories are filters over the same stream, so once the sites have been
  /// read, switching is instant: no request is made.
  Future<void> selectCategory(GameCategory? category) async {
    if (category == state.category) return;
    if (_cursors.isEmpty) return _showCachedThenSync(category);

    final generation = ++_generation;
    final articles = await ref
        .read(articleRepositoryProvider)
        .cachedFeed(category, since: _cutoff);
    if (generation != _generation) return;
    state = FeedState(
      category: category,
      articles: articles,
      syncing: false,
      error: state.error,
      reachedEnd: _cursors.every((c) => c.ended),
    );
  }

  /// Pull-to-refresh / retry.
  /// Bumps the generation so an in-flight infinite-scroll page is discarded.
  Future<void> refresh() => _sync(state.category, ++_generation);

  Future<void> _showCachedThenSync(GameCategory? category) async {
    final generation = ++_generation;
    _cursors = const [];
    final cached = await ref
        .read(articleRepositoryProvider)
        .cachedFeed(category);
    if (generation != _generation) return;
    state = FeedState(category: category, articles: cached);
    await _sync(category, generation);
  }

  /// The list shows only articles at least this new, so it stays a contiguous
  /// run (see `AppDatabase.feed`): the newest of the sites' oldest fetched
  /// posts, because every site is complete back to that point and no further.
  /// Null when there is nothing left to page through.
  String? get _cutoff {
    String? cutoff;
    for (final cursor in _cursors) {
      final oldest = cursor.oldest;
      if (cursor.ended || oldest == null) continue;
      if (cutoff == null || oldest.compareTo(cutoff) > 0) cutoff = oldest;
    }
    return cutoff;
  }

  /// The site holding the window back: the one whose fetched posts reach back
  /// the least. Fetching its next page moves the whole list furthest.
  _Cursor? get _bottleneck {
    _Cursor? best;
    for (final cursor in _cursors) {
      if (cursor.ended) continue;
      if (best == null || cursor.oldest!.compareTo(best.oldest!) > 0) {
        best = cursor;
      }
    }
    return best;
  }

  Future<void> _sync(GameCategory? category, int generation) async {
    final repository = ref.read(articleRepositoryProvider);
    if (generation == _generation) {
      state = FeedState(category: category, articles: state.articles);
    }

    final failures = <FeedException>[];
    Future<_Cursor> fetchFirstPage(NewsSource site) async {
      final cursor = _Cursor(site);
      try {
        cursor.advance(await repository.fetchPage(site, 1));
      } on FeedException catch (error) {
        failures.add(error);
        cursor.ended = true; // scrolling cannot fix a failed site
      }
      return cursor;
    }

    final cursors = await Future.wait([
      for (final site in NewsSource.values) fetchFirstPage(site),
    ]);
    if (generation != _generation) return;

    if (failures.length == cursors.length) {
      state = FeedState(
        category: category,
        articles: state.articles,
        syncing: false,
        error: failures.first,
      );
      return;
    }

    _cursors = cursors;
    final fresh = await repository.cachedFeed(category, since: _cutoff);
    if (generation != _generation) return;
    state = FeedState(
      category: category,
      articles: fresh,
      syncing: false,
      reachedEnd: cursors.every((c) => c.ended),
      error: failures.isEmpty
          ? null
          : const FeedException("Some stories couldn't be refreshed."),
    );
  }

  /// Infinite scroll: fetch the next older page(s) and append them.
  Future<void> loadMore() async {
    final start = state;
    if (start.syncing ||
        start.loadingMore ||
        start.reachedEnd ||
        start.articles.isEmpty) {
      return;
    }
    if (start.articles.length >= AppConfig.maxScrollArticles) {
      state = start.copyWith(reachedEnd: true);
      return;
    }

    final generation = _generation;
    final repository = ref.read(articleRepositoryProvider);
    state = start.copyWith(loadingMore: true, clearLoadMoreError: true);

    var articles = start.articles;
    try {
      for (var attempt = 0; attempt < _maxEmptyPages; attempt++) {
        final cursor = _bottleneck;
        if (cursor == null) break;
        final fetched = await repository.fetchPage(
          cursor.source,
          cursor.page + 1,
        );
        if (generation != _generation) return;
        cursor.page++;
        cursor.advance(fetched);
        articles = await repository.cachedFeed(start.category, since: _cutoff);
        if (generation != _generation) return;

        if (articles.length > start.articles.length) break;
      }
    } on FeedException catch (error) {
      if (generation != _generation) return;
      state = state.copyWith(loadingMore: false, loadMoreError: error);
      return;
    }

    state = state.copyWith(
      articles: articles,
      loadingMore: false,
      reachedEnd:
          _cursors.every((c) => c.ended) ||
          articles.length <= start.articles.length ||
          articles.length >= AppConfig.maxScrollArticles,
    );
  }
}
