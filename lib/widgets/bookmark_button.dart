import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/bookmark_provider.dart';

class BookmarkButton extends ConsumerWidget {
  const BookmarkButton({super.key, required this.articleId, this.size = 24});

  final String articleId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookmarked = ref.watch(
      bookmarkIdsProvider.select((ids) => ids.contains(articleId)),
    );
    return IconButton(
      tooltip: bookmarked ? 'Remove bookmark' : 'Bookmark',
      iconSize: size,
      visualDensity: VisualDensity.compact,
      color: bookmarked ? Theme.of(context).colorScheme.primary : null,
      icon: Icon(bookmarked ? Icons.bookmark : Icons.bookmark_border),
      onPressed: () => ref.read(bookmarkIdsProvider.notifier).toggle(articleId),
    );
  }
}
