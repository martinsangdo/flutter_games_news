import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/news_source.dart';

/// One site's colours for one brightness, taken from its stylesheet.
class SourcePalette {
  const SourcePalette({
    required this.accent,
    required this.link,
    required this.background,
    required this.surface,
    required this.heading,
    required this.body,
    required this.caption,
    required this.rule,
  });

  /// The brand colour (badges, indicators).
  final Color accent;

  /// Colour for link text: the accent, or a variant of it dark enough to read
  /// on [background] (the sites do the same in their light themes).
  final Color link;
  final Color background;
  final Color surface;
  final Color heading;
  final Color body;
  final Color caption;

  /// Borders, table lines and quote bars.
  final Color rule;
}

/// How a site looks: its palette in both brightnesses, its typography and the
/// few article-body conventions that differ between sites. Values come from the
/// sites' own CSS (custom properties such as `--primary`, `--site-color`,
/// `--wp--custom--*`); a few captions are darkened where the site's own grey
/// would fail contrast on white.
class SourceStyle {
  SourceStyle({
    required this.light,
    required this.dark,
    required this.fontTheme,
    this.underlineLinks = false,
    this.italicQuotes = false,
  });

  final SourcePalette light;
  final SourcePalette dark;

  /// Applies the site's body font to a text theme.
  final TextTheme Function(TextTheme) fontTheme;

  /// Article links carry an underline (siliconera) instead of colour alone.
  final bool underlineLinks;

  /// Block quotes are set in italics (pcgamesn).
  final bool italicQuotes;

  final Map<Brightness, ThemeData> _themes = {};

  SourcePalette palette(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The whole app theme restyled as this site: use it around a site's article.
  ThemeData theme(Brightness brightness) =>
      _themes[brightness] ??= _buildTheme(brightness);

  ThemeData _buildTheme(Brightness brightness) {
    final p = palette(brightness);
    final onLink =
        ThemeData.estimateBrightnessForColor(p.link) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: brightness,
        ).copyWith(
          primary: p.link,
          onPrimary: onLink,
          secondary: p.accent,
          surface: p.surface,
          onSurface: p.body,
          onSurfaceVariant: p.caption,
          outlineVariant: p.rule,
          surfaceContainerHighest: p.rule,
        );

    // A bare ThemeData has no font sizes: MaterialApp merges them in when it
    // localizes the theme, which a nested Theme never goes through.
    final text = fontTheme(
      Typography.englishLike2021.merge(
        ThemeData(brightness: brightness).textTheme,
      ),
    ).apply(bodyColor: p.body, displayColor: p.heading);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.background,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        foregroundColor: p.heading,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: p.rule),
        ),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: text.copyWith(
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w800,
          height: 1.2,
        ),
      ),
    );
  }
}

extension NewsSourceStyle on NewsSource {
  SourceStyle get style => _styles[this]!;
}

final _styles = <NewsSource, SourceStyle>{
  // wccftech.com: `--primary` #ff0055 (light) / #ff1a66 (dark), dark
  // surfaces #23292c / #282e31 on #edf3f5 text. Inter.
  NewsSource.wccftech: SourceStyle(
    light: const SourcePalette(
      accent: Color(0xFFFF0055),
      link: Color(0xFFE5004C), // `--primary-active`, readable on white
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      heading: Color(0xFF000000),
      body: Color(0xFF23292C),
      caption: Color(0xFF5F7079),
      rule: Color(0xFFE1EAED),
    ),
    dark: const SourcePalette(
      accent: Color(0xFFFF1A66),
      link: Color(0xFFFF5C8D), // the accent, lightened to read as text
      background: Color(0xFF23292C),
      surface: Color(0xFF282E31),
      heading: Color(0xFFEDF3F5),
      body: Color(0xFFEDF3F5),
      caption: Color(0xFF91A8B0),
      rule: Color(0xFF3B4449),
    ),
    fontTheme: (t) => GoogleFonts.interTextTheme(t),
  ),

  // siliconera.com: `--wp--custom--*` tokens. Red #bd000b, or #f95a46 on its
  // #161616 dark theme; underlined links; Montserrat throughout.
  NewsSource.siliconera: SourceStyle(
    light: const SourcePalette(
      accent: Color(0xFFBD000B),
      link: Color(0xFFBD000B),
      background: Color(0xFFFEFEFE),
      surface: Color(0xFFFFFFFF),
      heading: Color(0xFF171717),
      body: Color(0xFF494949),
      caption: Color(0xFF5D5D5D),
      rule: Color(0xFFE2E2E2),
    ),
    dark: const SourcePalette(
      accent: Color(0xFFF95A46),
      link: Color(0xFFF95A46),
      background: Color(0xFF161616),
      surface: Color(0xFF212121),
      heading: Color(0xFFECECEC),
      body: Color(0xFFA9A9A9),
      caption: Color(0xFF909090),
      rule: Color(0xFF3A3A3A),
    ),
    fontTheme: (t) => GoogleFonts.montserratTextTheme(t),
    underlineLinks: true,
  ),

  // pcgamesn.com: `--site-color` #f65002 on near-black #141414, grey #9b9b9b
  // captions, #bbb italic quotes, system UI font.
  NewsSource.pcgamesn: SourceStyle(
    light: const SourcePalette(
      accent: Color(0xFFF65002),
      link: Color(0xFFBA3A07), // `--site-color-dark`, readable on white
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFFFFFFF),
      heading: Color(0xFF141414),
      body: Color(0xFF333333),
      caption: Color(0xFF6B6B6B),
      rule: Color(0xFFBBBBBB),
    ),
    dark: const SourcePalette(
      accent: Color(0xFFF65002),
      link: Color(0xFFFB923C), // `--site-color-light`
      background: Color(0xFF141414),
      surface: Color(0xFF1E1E1E),
      heading: Color(0xFFFFFFFF),
      body: Color(0xFFDADADA),
      caption: Color(0xFF9B9B9B),
      rule: Color(0xFF3F3F3F),
    ),
    fontTheme: (t) => t,
    italicQuotes: true,
  ),
};
