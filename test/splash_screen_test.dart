import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:games_news/providers/feed_provider.dart';
import 'package:games_news/views/splash_screen.dart';

/// A feed that does no work but records that it was started.
class _RecordingFeed extends FeedNotifier {
  static bool built = false;

  @override
  FeedState build() {
    built = true;
    return const FeedState();
  }
}

void main() {
  setUp(() => _RecordingFeed.built = false);

  Future<void> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [feedProvider.overrideWith(_RecordingFeed.new)],
        child: const MaterialApp(
          home: SplashGate(child: Scaffold(body: Text('HOME'))),
        ),
      ),
    );
    // Decoding the logo is real async work; it only progresses in runAsync.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
  }

  Finder logo() => find.byWidgetPredicate(
    (w) =>
        w is Image &&
        w.image is AssetImage &&
        (w.image as AssetImage).assetName == SplashGate.logoAsset,
  );

  testWidgets('shows the logo for one second, then fades into the app', (
    tester,
  ) async {
    await pumpGate(tester);

    expect(logo(), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    await tester.pump(const Duration(milliseconds: 900));
    expect(logo(), findsOneWidget); // still on screen just before the second
    expect(find.text('HOME'), findsNothing);

    await tester.pump(const Duration(milliseconds: 150)); // 1.05 s: swap starts
    await tester.pump(const Duration(milliseconds: 400)); // fade finished
    expect(find.text('HOME'), findsOneWidget);
    expect(logo(), findsNothing);
  });

  testWidgets('starts loading the feed while the logo is showing', (
    tester,
  ) async {
    await pumpGate(tester);
    expect(logo(), findsOneWidget);
    expect(_RecordingFeed.built, isTrue);
    expect(find.text('HOME'), findsNothing);
  });

  testWidgets('the splash is white and never dark-themed', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [feedProvider.overrideWith(_RecordingFeed.new)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const SplashGate(child: SizedBox()),
        ),
      ),
    );
    final box = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(SplashGate),
            matching: find.byType(ColoredBox),
          )
          .first,
    );
    expect(box.color, Colors.white);
  });
}
