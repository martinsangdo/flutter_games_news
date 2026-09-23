import 'package:games_news/services/html_cleaner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips inline styling, scripts and layout attributes', () {
    final out = HtmlCleaner.clean(
      '<div style="background:#000"><p style="color:red" class="x">Hi <span style="font-size:9px">there</span></p>'
      '<script>alert(1)</script><iframe src="https://x"></iframe>'
      '<img src="https://a/b.jpg" width="900" height="600" srcset="a 1x" style="float:left"></div>',
    );
    expect(out, isNot(contains('style=')));
    expect(out, isNot(contains('<script')));
    expect(out, isNot(contains('<iframe')));
    expect(out, isNot(contains('<span')));
    expect(out, isNot(contains('<div')));
    expect(out, isNot(contains('width=')));
    expect(out, isNot(contains('srcset')));
    expect(out, contains('Hi there'));
    expect(out, contains('<img src="https://a/b.jpg"'));
  });

  test('resolves lazy-loaded images and removes empty blocks', () {
    final out = HtmlCleaner.clean(
      '<p>&nbsp;</p><p><img src="data:image/gif;base64,R0lG" data-src="https://a/lazy.jpg"></p><div><br></div>',
    );
    expect(out, contains('https://a/lazy.jpg'));
    expect(out, isNot(contains('R0lG')));
    expect(out, isNot(contains('&nbsp;')));
  });

  test('drops HTML comments and escapes top-level text', () {
    expect(
      HtmlCleaner.clean(
        '<!-- do not apply CSS styles! --><p>Kept<!-- inner --></p>1 < 2 & 3',
      ),
      '<p>Kept</p>1 &lt; 2 &amp; 3',
    );
  });

  test('text-only div becomes a paragraph', () {
    expect(HtmlCleaner.clean('<div>Loose text</div>'), '<p>Loose text</p>');
  });

  test('firstImageUrl finds the first http image', () {
    expect(
      HtmlCleaner.firstImageUrl(
        '<p>x</p><img src="https://a/1.jpg"><img src="https://a/2.jpg">',
      ),
      'https://a/1.jpg',
    );
    expect(HtmlCleaner.firstImageUrl('<p>none</p>'), '');
  });

  test('junk selectors remove website-only widgets and leave the story', () {
    const html =
        '<p>Story</p><div class="promo box"><strong>Buy!</strong></div>'
        '<div id="poll"><p>Vote</p></div><p>More</p>';
    final out = HtmlCleaner.clean(
      html,
      junkSelectors: const ['.promo', '#poll'],
    );
    expect(out, '<p>Story</p><p>More</p>');
    expect(HtmlCleaner.clean(html), contains('Buy!')); // opt-in per call
  });
}
