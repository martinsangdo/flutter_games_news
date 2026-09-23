import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/game_category.dart';
import '../providers/feed_provider.dart';
import 'bookmarks_screen.dart';
import 'categories_screen.dart';
import 'home_screen.dart';

/// The app's frame: a bottom navigation bar that stays put on every screen,
/// article pages included. Each tab has its own [Navigator], so opening a story
/// pushes it *inside* its tab (the bar remains visible) and every tab keeps its
/// own back stack and scroll position while you visit another.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  static const _home = 0;

  int _index = _home;
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());

  void _select(int index) {
    if (index == _index) {
      // Tapping the current tab returns to its first screen.
      _navigators[index].currentState?.popUntil((route) => route.isFirst);
    } else {
      setState(() => _index = index);
    }
  }

  void _openCategory(GameCategory? category) {
    _navigators[_home].currentState?.popUntil((route) => route.isFirst);
    ref.read(feedProvider.notifier).selectCategory(category);
    setState(() => _index = _home);
  }

  /// Back closes the open story first, then returns to Home, then leaves.
  Future<void> _onBack() async {
    if (await _navigators[_index].currentState?.maybePop() ?? false) return;
    if (_index != _home) {
      setState(() => _index = _home);
    } else {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _TabNavigator(
              navigatorKey: _navigators[0],
              root: const HomeScreen(),
            ),
            _TabNavigator(
              navigatorKey: _navigators[1],
              root: CategoriesScreen(onSelected: _openCategory),
            ),
            _TabNavigator(
              navigatorKey: _navigators[2],
              root: const BookmarksScreen(),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Categories',
            ),
            NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined),
              selectedIcon: Icon(Icons.bookmarks),
              label: 'Bookmarks',
            ),
          ],
        ),
      ),
    );
  }
}

class _TabNavigator extends StatelessWidget {
  const _TabNavigator({required this.navigatorKey, required this.root});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget root;

  @override
  Widget build(BuildContext context) => Navigator(
    key: navigatorKey,
    onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => root),
  );
}
