import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';
import '../providers/app_providers.dart';
import '../services/ads_service.dart';

/// One AdMob banner. Renders nothing when ads are disabled (web/desktop) and
/// owns the `BannerAd` lifecycle: created once the SDK is ready and disposed
/// with the widget. Used on the article detail screen only.
class BannerAdSlot extends ConsumerStatefulWidget {
  const BannerAdSlot({super.key, required this.size, this.height});

  final AdSize size;

  /// Total height of the slot; when null it wraps the banner.
  final double? height;

  @override
  ConsumerState<BannerAdSlot> createState() => _BannerAdSlotState();
}

class _BannerAdSlotState extends ConsumerState<BannerAdSlot> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    if (!AppConfig.adsEnabled) return;
    ref.listenManual(adsReadyProvider, (_, next) {
      if (next.hasValue) _load();
    }, fireImmediately: true);
  }

  void _load() {
    if (_ad != null || !mounted) return;
    _ad = BannerAd(
      adUnitId: AdsService.bannerUnitId,
      size: widget.size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.adsEnabled) return const SizedBox.shrink();

    final ad = _ad;
    final theme = Theme.of(context);
    return SizedBox(
      height: widget.height,
      child: Center(
        child: SizedBox(
          width: widget.size.width.toDouble(),
          height: widget.size.height.toDouble(),
          child: ad != null && _loaded
              ? AdWidget(ad: ad)
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      'Advertisement',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
