import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bookmark_provider.dart';
import '../widgets/article_card.dart';
import '../widgets/status_views.dart';

class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarks = ref.watch(bookmarkedArticlesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: bookmarks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => MessageView(
          icon: Icons.error_outline,
          title: "Couldn't load bookmarks",
          onRetry: () => ref.invalidate(bookmarkedArticlesProvider),
        ),
        data: (articles) => articles.isEmpty
            ? const MessageView(
                icon: Icons.bookmark_border,
                title: 'No bookmarks yet',
                message:
                    'Tap the bookmark on any story to keep it here, even after it leaves the feed.',
              )
            : ListView.builder(
                itemExtent: kFeedItemExtent,
                itemCount: articles.length,
                itemBuilder: (context, index) =>
                    ArticleCard(article: articles[index]),
              ),
      ),
    );
  }
}
