import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../models/news_source.dart';
import '../theme/source_style.dart';
import 'network_images.dart';

/// Sliver-based renderer for cleaned article HTML. Being a sliver means long
/// bodies are built lazily instead of as one giant unconstrained column.
///
/// The body is styled after [source]'s own stylesheet (see `SourceStyle`);
/// the surrounding `Theme` supplies the site's fonts and text colours.
class ArticleHtml extends StatelessWidget {
  const ArticleHtml({super.key, required this.html, required this.source});

  final String html;
  final NewsSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = source.style;
    final palette = style.palette(theme.brightness);
    final link = _hex(palette.link);
    final heading = _hex(palette.heading);
    final caption = _hex(palette.caption);
    final rule = _hex(palette.rule);

    return HtmlWidget(
      html,
      renderMode: RenderMode.sliverList,
      textStyle: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 17,
        height: 1.65,
      ),
      customStylesBuilder: (element) {
        switch (element.localName) {
          case 'a':
            return {
              'color': link,
              'text-decoration': style.underlineLinks ? 'underline' : 'none',
              'font-weight': '600',
            };
          case 'p':
            // pcgamesn's standfirst under the headline.
            if (element.classes.contains('entry-strapline')) {
              return {
                'font-size': '1.2em',
                'font-weight': '600',
                'color': heading,
                'margin': '0 0 1em',
              };
            }
          case 'blockquote':
            return {
              'margin': '1em 0',
              'padding': '0 0 0 1em',
              'border-left': '3px solid $rule',
              if (style.italicQuotes) 'font-style': 'italic',
            };
          case 'h1':
          case 'h2':
            return {
              'font-size': '1.4em',
              'font-weight': '800',
              'color': heading,
              'margin': '1.2em 0 0.4em',
            };
          case 'h3':
          case 'h4':
            return {
              'font-size': '1.2em',
              'font-weight': '700',
              'color': heading,
              'margin': '1.1em 0 0.3em',
            };
          case 'figcaption':
            return {
              'font-size': '0.8em',
              'color': caption,
              'margin': '0.4em 0 1em',
            };
          case 'figure':
            return {'margin': '1em 0'};
          case 'table':
            return {'border-collapse': 'collapse', 'margin': '1em 0'};
          case 'th':
            return {
              'border': '1px solid $rule',
              'padding': '6px 8px',
              'font-weight': '700',
              'color': heading,
            };
          case 'td':
            return {'border': '1px solid $rule', 'padding': '6px 8px'};
        }
        return null;
      },
      customWidgetBuilder: (element) {
        if (element.localName != 'img') return null;
        if (element.classes.contains('wp-smiley') ||
            element.classes.contains('emoji')) {
          return null;
        }

        final src = element.attributes['src'] ?? '';
        if (!src.startsWith('http')) return const SizedBox.shrink();
        return NetworkPhoto(url: src);
      },
    );
  }

  static String _hex(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}
