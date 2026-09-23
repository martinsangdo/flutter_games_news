import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_category.dart';
import '../providers/feed_provider.dart';

/// Every category as a tile. Picking one shows that category on the home feed
/// (the shell switches tabs through [onSelected]).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key, required this.onSelected});

  final ValueChanged<GameCategory?> onSelected;

  static IconData _icon(GameCategory? category) => switch (category) {
    null => Icons.newspaper,
    GameCategory.pc => Icons.computer,
    GameCategory.playstation => Icons.sports_esports,
    GameCategory.xbox => Icons.videogame_asset,
    GameCategory.nintendo => Icons.gamepad,
    GameCategory.hardware => Icons.memory,
    GameCategory.reviews => Icons.rate_review,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(feedProvider.select((s) => s.category));
    const entries = <GameCategory?>[null, ...GameCategory.values];

    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      body: GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: [
          for (final category in entries)
            _CategoryTile(
              icon: _icon(category),
              label: category?.label ?? 'All stories',
              selected: category == selected,
              onTap: () => onSelected(category),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Card(
        color: selected ? scheme.primaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 28, color: scheme.primary),
                Text(label, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
