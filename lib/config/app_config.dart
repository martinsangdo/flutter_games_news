import 'package:flutter/foundation.dart';

class AppConfig {
  const AppConfig._();

  /// Cached, unbookmarked articles kept per news source.
  static const maxUnbookmarkedArticles = 60;

  /// Infinite scroll stops here so a long session cannot grow the database
  /// or the in-memory list without bound. The next refresh purges back to
  /// [maxUnbookmarkedArticles].
  static const maxScrollArticles = 150;
  static const requestTimeout = Duration(seconds: 15);

  static const imageDiskCacheBytes = 50 * 1024 * 1024;
  static const thumbnailDecodeSize = 400;

  /// AdMob only exists on Android and iOS; never on web or desktop.
  static bool get adsEnabled =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
}

/// Google's public test ad units. Replace with production IDs before release
/// (and the app IDs in AndroidManifest.xml / Info.plist).
class AdUnits {
  const AdUnits._();

  static const androidBanner = 'ca-app-pub-8762959223087619/8103310085';
  static const iosBanner = 'ca-app-pub-3940256099942544/2934735716';
}
