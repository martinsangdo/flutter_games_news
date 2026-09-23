import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_category.dart';
import '../providers/feed_provider.dart';
import '../services/wordpress_service.dart';
import '../widgets/article_card.dart';
import '../widgets/status_views.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  /// "All" first (null), then one tab per category.
  static const List<GameCategory?> _tabCategories = [
    null,
    ...GameCategory.values,
  ];

  late final TabController _tabs = TabController(
    length: _tabCategories.length,
    vsync: this,
  );
  final ScrollController _scroll = ScrollController();

  /// Start loading older articles this far before the end of the list.
  static const _loadMoreDistance = 900.0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients ||
        _scroll.position.extentAfter > _loadMoreDistance ||
        ref.read(feedProvider).loadMoreError != null) {
      return;
    }
    ref.read(feedProvider.notifier).loadMore();
  }

  @override
  void dispose() {
    _scroll.removeListener(_maybeLoadMore);
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _selectFilter(int index) async {
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await ref.read(feedProvider.notifier).selectCategory(_tabCategories[index]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // A short list (big screen, few results) never fires a scroll event, so
    // check again whenever the article list changes.
    ref.listen(feedProvider.select((s) => s.articles), (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());
    });

    // The Categories tab can change the category from outside this screen.
    ref.listen(feedProvider.select((s) => s.category), (_, category) {
      final index = _tabCategories.indexOf(category);
      if (index != _tabs.index) {
        if (_scroll.hasClients) _scroll.jumpTo(0);
        _tabs.animateTo(index);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text.rich(
          TextSpan(
            text: 'Games',
            children: [
              TextSpan(
                text: 'News',
                style: TextStyle(color: scheme.primary),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          onTap: _selectFilter,
          tabs: [
            for (final category in _tabCategories)
              Tab(text: category?.label ?? 'All'),
          ],
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: ref.read(feedProvider.notifier).refresh,
            child: _FeedList(controller: _scroll),
          ),
          const Positioned(top: 0, left: 0, right: 0, child: _SyncBar()),
        ],
      ),
    );
  }
}

/// Thin progress bar under the tabs while a refresh runs behind cached
/// articles. (With nothing cached, the empty state shows a spinner instead.)
class _SyncBar extends ConsumerWidget {
  const _SyncBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(
      feedProvider.select((s) => s.syncing && s.articles.isNotEmpty),
    );
    return visible
        ? const LinearProgressIndicator(minHeight: 3)
        : const SizedBox.shrink();
  }
}

class _FeedList extends ConsumerWidget {
  const _FeedList({required this.controller});

  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final articles = ref.watch(feedProvider.select((s) => s.articles));
    final syncing = ref.watch(feedProvider.select((s) => s.syncing));
    final error = ref.watch(feedProvider.select((s) => s.error));
    final notifier = ref.read(feedProvider.notifier);

    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (error != null && articles.isNotEmpty)
          SliverToBoxAdapter(
            child: StatusBanner(
              message: '${error.message} Showing saved stories.',
              onRetry: notifier.refresh,
            ),
          ),
        if (articles.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              syncing: syncing,
              error: error,
              onRetry: notifier.refresh,
            ),
          )
        else
          SliverFixedExtentList(
            itemExtent: kFeedItemExtent,
            delegate: SliverChildBuilderDelegate(
              childCount: articles.length,
              (context, index) => ArticleCard(article: articles[index]),
            ),
          ),
        if (articles.isNotEmpty) const _FeedFooter(),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.syncing,
    required this.error,
    required this.onRetry,
  });

  final bool syncing;
  final FeedException? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (syncing) return const Center(child: CircularProgressIndicator());
    final failure = error;
    if (failure != null) {
      return MessageView(
        icon: Icons.cloud_off,
        title: failure.isOffline ? "You're offline" : "Can't load stories",
        message: failure.message,
        onRetry: onRetry,
      );
    }
    return MessageView(
      icon: Icons.search_off,
      title: 'Nothing here yet',
      message: 'No stories here yet. Pull down to refresh.',
      onRetry: onRetry,
    );
  }
}

/// End of the list: spinner while loading more, retry on failure, or a
/// closing line once there is nothing older to load.
class _FeedFooter extends ConsumerWidget {
  const _FeedFooter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(feedProvider.select((s) => s.loadingMore));
    final error = ref.watch(feedProvider.select((s) => s.loadMoreError));
    final ended = ref.watch(feedProvider.select((s) => s.reachedEnd));
    final theme = Theme.of(context);

    if (loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: SizedBox.square(
              dimension: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ),
        ),
      );
    }
    if (error != null) {
      return SliverToBoxAdapter(
        child: StatusBanner(
          message: "Couldn't load more stories.",
          onRetry: ref.read(feedProvider.notifier).loadMore,
        ),
      );
    }
    if (ended) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(
            child: Text(
              "You're all caught up",
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }
    return const SliverToBoxAdapter(child: SizedBox.shrink());
  }
}
