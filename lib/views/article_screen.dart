import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';

import '../models/article.dart';
import '../models/game_category.dart';
import '../providers/app_providers.dart';
import '../theme/source_style.dart';
import '../widgets/article_card.dart';
import '../widgets/article_html.dart';
import '../widgets/banner_ad_slot.dart';
import '../widgets/bookmark_button.dart';
import '../widgets/network_images.dart';

class ArticleScreen extends ConsumerWidget {
  const ArticleScreen({super.key, required this.article});

  final Article article;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The article body is set in the look of the site it was published on.
    final style = article.source.style;
    final theme = style.theme(Theme.of(context).brightness);
    final palette = style.palette(theme.brightness);
    final category = GameCategory.of(article);
    final content = ref.watch(articleContentProvider(article.id));
    final relatedAsync = ref.watch(relatedArticlesProvider(article.id));
    final related = relatedAsync.valueOrNull ?? const [];

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            BookmarkButton(articleId: article.id, size: 26),
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: 'Share',
                icon: const Icon(Icons.ios_share),
                onPressed: () => _share(buttonContext),
              ),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            if (article.imageUrl.isNotEmpty)
              SliverToBoxAdapter(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: NetworkPhoto(
                    url: article.imageUrl,
                    decodeWidth: 1080,
                    placeholderHeight: 240,
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(article.title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        children: [
                          if (category != null)
                            TextSpan(
                              text: category.label.toUpperCase(),
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: palette.link,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          TextSpan(
                            text: category == null
                                ? timeAgo(article.pubDate)
                                : '  ${timeAgo(article.pubDate)}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: palette.caption,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...content.when(
              loading: () => const [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],
              error: (_, _) => [_notice('Could not load this story.')],
              data: (html) => html.isEmpty
                  ? [
                      _notice(
                        'The full text is not available offline for this story.',
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: ArticleHtml(html: html, source: article.source),
                      ),
                    ],
            ),
            if (relatedAsync.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox.square(
                      dimension: 28,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    ),
                  ),
                ),
              ),
            if (related.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Keep reading',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              SliverFixedExtentList(
                itemExtent: kFeedItemExtent,
                delegate: SliverChildBuilderDelegate(
                  childCount: related.length,
                  (context, index) => ArticleCard(article: related[index]),
                ),
              ),
            ],
            const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
          ],
        ),
        bottomNavigationBar: const BannerAdSlot(
          size: AdSize.banner,
          height: 56,
        ),
      ),
    );
  }

  Widget _notice(String message) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );

  /// `sharePositionOrigin` is required for the share sheet popover on iPad.
  Future<void> _share(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    return SharePlus.instance.share(
      ShareParams(
        text: '${article.title}\n${article.link}',
        subject: article.title,
        sharePositionOrigin: origin,
      ),
    );
  }
}
