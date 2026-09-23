import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';

/// Disk-capped image cache. `flutter_cache_manager` only limits the number of
/// files, so [trim] enforces [AppConfig.imageDiskCacheBytes] by evicting the
/// oldest files. The cache store tolerates files disappearing from disk.
class ImageCacheService {
  const ImageCacheService._();

  static const _cacheKey = 'gamesNewsImages';

  static final CacheManager? _manager = kIsWeb
      ? null
      : CacheManager(
          Config(
            _cacheKey,
            stalePeriod: const Duration(days: 14),
            maxNrOfCacheObjects: 400,
          ),
        );

  /// Decodes at no more than [width] x [height] in memory while keeping the
  /// source aspect ratio. Passing both `memCacheWidth` and `memCacheHeight` to
  /// `CachedNetworkImage` would stretch non-square images to the exact box, so
  /// the resize is applied here with [ResizeImagePolicy.fit].
  static ImageProvider provider(String url, {int? width, int? height}) {
    final source = CachedNetworkImageProvider(url, cacheManager: _manager);
    if (width == null && height == null) return source;
    return ResizeImage(
      source,
      width: width,
      height: height,
      policy: ResizeImagePolicy.fit,
    );
  }

  static Future<void> trim() async {
    if (kIsWeb) return;
    try {
      final dir = Directory(
        p.join((await getTemporaryDirectory()).path, _cacheKey),
      );
      if (!await dir.exists()) return;

      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        total += stat.size;
        files.add((entity, stat));
      }
      if (total <= AppConfig.imageDiskCacheBytes) return;

      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in files) {
        if (total <= AppConfig.imageDiskCacheBytes) break;
        await file.delete();
        total -= stat.size;
      }
    } catch (_) {
      // Best effort: a vanished/locked file (or an unavailable plugin) is
      // simply retried on the next trim.
    }
  }
}
