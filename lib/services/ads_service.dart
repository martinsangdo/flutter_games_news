import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../config/app_config.dart';

class AdsService {
  const AdsService._();

  static Future<void> initialize() async {
    if (!AppConfig.adsEnabled) return;
    await MobileAds.instance.initialize();
  }

  static String get bannerUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? AdUnits.iosBanner
      : AdUnits.androidBanner;
}
