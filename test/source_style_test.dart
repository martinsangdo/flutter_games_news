import 'dart:math' as math;

import 'package:games_news/models/news_source.dart';
import 'package:games_news/theme/source_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final source in NewsSource.values) {
    for (final brightness in Brightness.values) {
      final name = '${source.name} ${brightness.name}';

      test('$name theme has real font sizes and the site palette', () {
        final theme = source.style.theme(brightness);
        final palette = source.style.palette(brightness);

        // A nested Theme never gets MaterialApp's size localization, so the
        // theme must carry sizes itself (otherwise headlines render at 14).
        expect(theme.textTheme.headlineSmall?.fontSize, 24);
        expect(theme.textTheme.bodyLarge?.fontSize, isNotNull);
        expect(theme.colorScheme.primary, palette.link);
        expect(theme.scaffoldBackgroundColor, palette.background);
        expect(theme.brightness, brightness);
      });

      test('$name text is legible on its background and card surface', () {
        final p = source.style.palette(brightness);
        for (final surface in [p.background, p.surface]) {
          expect(_contrast(p.body, surface), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.heading, surface), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.link, surface), greaterThanOrEqualTo(4.5));
          expect(_contrast(p.caption, surface), greaterThanOrEqualTo(4.5));
        }
      });
    }
  }
}
