import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/image_cache_service.dart';

/// Square list thumbnail. Rounded corners come from `BoxDecoration`, which
/// clips while painting the image — no `ClipRRect` and no offscreen layer.
class Thumbnail extends StatelessWidget {
  const Thumbnail({super.key, required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: placeholder,
          borderRadius: BorderRadius.circular(12),
          image: url.isEmpty
              ? null
              : DecorationImage(
                  image: ImageCacheService.provider(
                    url,
                    width: AppConfig.thumbnailDecodeSize,
                    height: AppConfig.thumbnailDecodeSize,
                  ),
                  fit: BoxFit.cover,
                  onError: (_, _) {},
                ),
        ),
      ),
    );
  }
}

/// Full-width image whose height follows the source aspect ratio.
class NetworkPhoto extends StatelessWidget {
  const NetworkPhoto({
    super.key,
    required this.url,
    this.decodeWidth = 900,
    this.placeholderHeight = 220,
  });

  final String url;
  final int decodeWidth;
  final double placeholderHeight;

  @override
  Widget build(BuildContext context) {
    final placeholder = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Image(
      image: ImageCacheService.provider(url, width: decodeWidth),
      width: double.infinity,
      fit: BoxFit.fitWidth,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
          frame == null && !wasSynchronouslyLoaded
          ? ColoredBox(
              color: placeholder,
              child: SizedBox(
                height: placeholderHeight,
                width: double.infinity,
                child: const Center(
                  child: SizedBox.square(
                    dimension: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                ),
              ),
            )
          : child,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
