import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database.dart';
import '../models/article.dart';
import '../services/ads_service.dart';
import '../services/article_repository.dart';
import '../services/wordpress_service.dart';

/// Opened in `main()` before `runApp` and injected through provider overrides,
/// so no widget ever has to handle an async "database not ready" state.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError(),
);

final wordPressServiceProvider = Provider<WordPressService>((ref) {
  final service = WordPressService();
  ref.onDispose(service.dispose);
  return service;
});

final articleRepositoryProvider = Provider<ArticleRepository>(
  (ref) => ArticleRepository(
    ref.watch(databaseProvider),
    ref.watch(wordPressServiceProvider),
  ),
);

/// Completes when the Mobile Ads SDK is initialised; startup never waits on it.
final adsReadyProvider = FutureProvider<void>((ref) => AdsService.initialize());

final relatedArticlesProvider = FutureProvider.autoDispose
    .family<List<Article>, String>(
      (ref, id) => ref.watch(articleRepositoryProvider).related(id),
    );

final articleContentProvider = FutureProvider.autoDispose
    .family<String, String>(
      (ref, id) => ref.watch(articleRepositoryProvider).contentHtml(id),
    );
