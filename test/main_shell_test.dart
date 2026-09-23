import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:games_news/db/app_database.dart';
import 'package:games_news/models/game_category.dart';
import 'package:games_news/providers/app_providers.dart';
import 'package:games_news/providers/feed_provider.dart';
import 'package:games_news/services/wordpress_service.dart';
import 'package:games_news/theme/app_theme.dart';
import 'package:games_news/views/article_screen.dart';
import 'package:games_news/views/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _post(int id, String title) => {
  'id': id,
  'link': 'https://x/$id',
  'date_gmt': '2026-01-01T0$id:00:00',
  'title': {'rendered': title},
  'content': {'rendered': '<p>Body of $title</p>'},
};

Future<http.Response> _web(http.Request request) async {
  final path = request.url.path;
  if (path.endsWith('/topics')) {
    return http.Response(
      jsonEncode([
        {'id': 1, 'slug': 'games'},
      ]),
      200,
    );
  }
  if (request.url.host == 'wccftech.com') {
    return http.Response(
      jsonEncode([
        _post(3, 'Gamma indie darling'),
        _post(2, 'Beta Xbox news'),
        _post(1, 'Alpha PS5 launch'),
      ]),
      200,
    );
  }
  return request.url.path == '/feed/'
      ? http.Response('<rss version="2.0"><channel></channel></rss>', 200)
      : http.Response('[]', 200);
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late ProviderContainer container;

  /// Real async work (isolates, sqlite) only progresses inside runAsync.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Let page transitions finish and their routes be removed.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  Future<void> pumpShell(WidgetTester tester) async {
    // With fetching on, an unavailable font download is only logged (as in the
    // app when offline); with it off, google_fonts throws for missing assets.
    GoogleFonts.config.allowRuntimeFetching = true;
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final dir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('games_news_shell'),
    );
    addTearDown(() => dir!.delete(recursive: true));
    final db = await tester.runAsync(
      () => AppDatabase.open(p.join(dir!.path, 'shell.db')),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db!),
          wordPressServiceProvider.overrideWithValue(
            WordPressService(client: MockClient(_web)),
          ),
          adsReadyProvider.overrideWith((ref) => Completer<void>().future),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const MainShell()),
      ),
    );
    container = ProviderScope.containerOf(
      tester.element(find.byType(MainShell)),
    );
    await settle(tester);
  }

  Finder navLabel(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  testWidgets('the bottom bar has Home, Categories and Bookmarks', (
    tester,
  ) async {
    await pumpShell(tester);
    expect(navLabel('Home'), findsOneWidget);
    expect(navLabel('Categories'), findsOneWidget);
    expect(navLabel('Bookmarks'), findsOneWidget);
    expect(find.text('Alpha PS5 launch'), findsOneWidget);
  });

  testWidgets('no story or message ever names a news site', (tester) async {
    await pumpShell(tester);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase())
        .join(' ');
    for (final name in ['wccftech', 'siliconera', 'pcgamesn']) {
      expect(texts, isNot(contains(name)));
    }
  });

  testWidgets(
    'the bar stays on a story page, and each tab keeps its own stack',
    (tester) async {
      await pumpShell(tester);

      await tester.tap(find.text('Alpha PS5 launch'));
      await settle(tester);
      expect(find.byType(ArticleScreen), findsOneWidget);
      expect(
        find.textContaining('Body of Alpha PS5 launch', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.byType(NavigationBar),
        findsOneWidget,
      ); // still there on the detail page

      // Go elsewhere from the story, and come back: the story is still open.
      await tester.tap(navLabel('Bookmarks'));
      await settle(tester);
      expect(find.text('No bookmarks yet'), findsOneWidget);
      await tester.tap(navLabel('Home'));
      await settle(tester);
      expect(find.byType(ArticleScreen), findsOneWidget);

      // Tapping the current tab again returns to its first screen.
      await tester.tap(navLabel('Home'));
      await settle(tester);
      expect(find.byType(ArticleScreen), findsNothing);
      expect(find.text('Alpha PS5 launch'), findsOneWidget);
    },
  );

  testWidgets(
    'picking a category from a story page shows that category on Home',
    (tester) async {
      await pumpShell(tester);
      await tester.tap(find.text('Beta Xbox news'));
      await settle(tester);
      expect(find.byType(ArticleScreen), findsOneWidget);

      await tester.tap(navLabel('Categories'));
      await settle(tester);
      await tester.tap(find.text('PlayStation'));
      await settle(tester);

      expect(container.read(feedProvider).category, GameCategory.playstation);
      expect(
        find.byType(ArticleScreen),
        findsNothing,
      ); // Home is back at its feed
      expect(find.text('Alpha PS5 launch'), findsOneWidget);
      expect(find.text('Beta Xbox news'), findsNothing);
    },
  );
}
