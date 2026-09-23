import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

/// Normalises WordPress post HTML into a tree that renders identically on any
/// phone: no inline styling, no scripts/embeds, lazy-loaded images resolved,
/// meaningless wrappers and empty blocks removed.
class HtmlCleaner {
  const HtmlCleaner._();

  static const _dropTags = {
    'script',
    'style',
    'noscript',
    'iframe',
    'form',
    'ins',
    'object',
    'embed',
    'link',
    'meta',
    'button',
    'input',
    'svg',
  };

  static const _dropAttributes = {
    'style',
    'width',
    'height',
    'align',
    'bgcolor',
    'color',
    'face',
    'size',
    'srcset',
    'sizes',
    'id',
    'loading',
    'decoding',
    'border',
    'cellpadding',
    'cellspacing',
    'valign',
  };

  static const _lazySrcAttributes = [
    'data-src',
    'data-lazy-src',
    'data-original',
    'data-orig-file',
  ];
  static const _wrapperTags = {
    'span',
    'font',
    'div',
    'section',
    'article',
    'center',
  };
  static const _inlineTags = {
    'a',
    'b',
    'strong',
    'i',
    'em',
    'u',
    'br',
    'img',
    'sup',
    'sub',
    'small',
    'mark',
    'code',
  };
  static const _emptyCheckedTags = {
    'p',
    'a',
    'b',
    'strong',
    'i',
    'em',
    'u',
    'li',
    'ul',
    'ol',
    'blockquote',
    'figure',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'div',
    'section',
    'article',
  };
  static const _mediaTags = ['img', 'video', 'audio', 'picture', 'table', 'hr'];

  /// [junkSelectors]: CSS selectors of website-only widgets to remove first
  /// (see `NewsSource.junkSelectors`).
  static String clean(String rawHtml, {List<String> junkSelectors = const []}) {
    if (rawHtml.trim().isEmpty) return '';
    final root = html_parser.parseFragment(rawHtml);

    _removeComments(root);
    for (final selector in junkSelectors) {
      root.querySelectorAll(selector).forEach((e) => e.remove());
    }
    for (final tag in _dropTags) {
      root.querySelectorAll(tag).forEach((e) => e.remove());
    }
    for (final picture in root.querySelectorAll('picture')) {
      final img = picture.querySelector('img');
      if (img != null) picture.replaceWith(img);
    }

    for (final element in root.querySelectorAll('*')) {
      element.attributes.removeWhere((name, _) {
        final key = name.toString();
        return _dropAttributes.contains(key) || key.startsWith('on');
      });
      if (element.localName == 'img') _resolveImageSource(element);
    }

    _flattenWrappers(root);
    _removeEmptyBlocks(root);

    return (Element.tag(
      'div',
    )..nodes.addAll(root.nodes.toList())).innerHtml.trim();
  }

  static void _removeComments(Node node) {
    for (final child in node.nodes.toList()) {
      if (child is Comment) {
        child.remove();
      } else {
        _removeComments(child);
      }
    }
  }

  static final _imgSrc = RegExp(r'''<img[^>]+src="(https?://[^"]+)"''');

  /// First body image, used as a thumbnail when a post has no featured image.
  static String firstImageUrl(String cleanedHtml) =>
      _imgSrc.firstMatch(cleanedHtml)?.group(1) ?? '';

  static void _resolveImageSource(Element img) {
    final src = img.attributes['src'] ?? '';
    if (src.isNotEmpty && !src.startsWith('data:')) return;
    for (final attribute in _lazySrcAttributes) {
      final lazy = img.attributes[attribute];
      if (lazy != null && lazy.isNotEmpty) {
        img.attributes['src'] = lazy;
        return;
      }
    }
  }

  /// `span`/`font` wrappers carry only styling; `div`-like wrappers are unwrapped
  /// when they only contain blocks, or become paragraphs when they hold text.
  static void _flattenWrappers(Node root) {
    final wrappers = (root as DocumentFragment)
        .querySelectorAll('*')
        .where((e) => _wrapperTags.contains(e.localName))
        .toList()
        .reversed;

    for (final wrapper in wrappers) {
      final parent = wrapper.parentNode;
      if (parent == null) continue;

      final holdsInlineContent =
          wrapper.localName == 'span' ||
          wrapper.localName == 'font' ||
          wrapper.nodes.any(
            (n) =>
                (n is Text && n.text.trim().isNotEmpty) ||
                (n is Element && _inlineTags.contains(n.localName)),
          );

      if (wrapper.localName == 'span' ||
          wrapper.localName == 'font' ||
          !holdsInlineContent) {
        final index = parent.nodes.indexOf(wrapper);
        parent.nodes.insertAll(index, wrapper.nodes.toList());
        wrapper.remove();
      } else if (parent is Element && parent.localName == 'p') {
        final index = parent.nodes.indexOf(wrapper);
        parent.nodes.insertAll(index, wrapper.nodes.toList());
        wrapper.remove();
      } else {
        final paragraph = Element.tag('p')
          ..nodes.addAll(wrapper.nodes.toList());
        wrapper.replaceWith(paragraph);
      }
    }
  }

  /// Bottom-up so a parent emptied by its children's removal is removed too.
  static void _removeEmptyBlocks(DocumentFragment root) {
    for (final element in root.querySelectorAll('*').reversed.toList()) {
      if (!_emptyCheckedTags.contains(element.localName)) continue;
      final hasText = element.text.replaceAll('\u00a0', ' ').trim().isNotEmpty;
      final hasMedia = _mediaTags.any(
        (tag) => element.querySelector(tag) != null,
      );
      if (!hasText && !hasMedia) element.remove();
    }
  }
}
