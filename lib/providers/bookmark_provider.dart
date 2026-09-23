import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/article.dart';
import 'app_providers.dart';

/// IDs of bookmarked articles. Cards watch `select((ids) => ids.contains(id))`
/// so toggling one bookmark rebuilds only that card's button.
final bookmarkIdsProvider = NotifierProvider<BookmarkIdsNotifier, Set<String>>(
  BookmarkIdsNotifier.new,
);

class BookmarkIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref
        .read(articleRepositoryProvider)
        .bookmarkedIds()
        .then((ids) => state = {...state, ...ids});
    return const {};
  }

  Future<void> toggle(String id) async {
    final bookmark = !state.contains(id);
    await ref
        .read(articleRepositoryProvider)
        .setBookmarked(id, value: bookmark);
    state = bookmark ? {...state, id} : ({...state}..remove(id));
  }
}

final bookmarkedArticlesProvider = FutureProvider.autoDispose<List<Article>>((
  ref,
) {
  ref.watch(bookmarkIdsProvider);
  return ref.watch(articleRepositoryProvider).bookmarked();
});
