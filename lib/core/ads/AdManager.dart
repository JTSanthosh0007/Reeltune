import 'dart:io';
import 'package:flutter/foundation.dart';

class AdManager {
  AdManager._();

  // Test Ad Unit IDs (AdMob Defaults)
  static const String _androidTestBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _androidTestInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String _androidTestRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String _androidTestAppOpen = 'ca-app-pub-3940256099942544/9257395921';
  static const String _androidTestNative = 'ca-app-pub-3940256099942544/2247696110';

  static const String _iosTestBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const String _iosTestInterstitial = 'ca-app-pub-3940256099942544/4411468910';
  static const String _iosTestRewarded = 'ca-app-pub-3940256099942544/1712485313';
  static const String _iosTestAppOpen = 'ca-app-pub-3940256099942544/5575462274';
  static const String _iosTestNative = 'ca-app-pub-3940256099942544/3986693107';

  // Production Ad Unit IDs (Release mode)
  // Banner Ad unit successfully created by user: ca-app-pub-2811908516993554/9345696493
  static const String _androidProdBanner = 'ca-app-pub-2811908516993554/9345696493';
  static const String _androidProdInterstitial = ''; // TODO: Replace with production ID
  static const String _androidProdRewarded = ''; // TODO: Replace with production ID
  static const String _androidProdAppOpen = ''; // TODO: Replace with production ID
  static const String _androidProdNative = ''; // TODO: Replace with production ID

  static const String _iosProdBanner = ''; // TODO: Replace with production ID
  static const String _iosProdInterstitial = '';
  static const String _iosProdRewarded = '';
  static const String _iosProdAppOpen = '';
  static const String _iosProdNative = '';

  static String get bannerAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _androidTestBanner : _iosTestBanner;
    }
    if (Platform.isAndroid) {
      return _androidProdBanner.isNotEmpty ? _androidProdBanner : _androidTestBanner;
    } else {
      return _iosProdBanner.isNotEmpty ? _iosProdBanner : _iosTestBanner;
    }
  }

  static String get interstitialAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _androidTestInterstitial : _iosTestInterstitial;
    }
    if (Platform.isAndroid) {
      return _androidProdInterstitial.isNotEmpty ? _androidProdInterstitial : _androidTestInterstitial;
    } else {
      return _iosProdInterstitial.isNotEmpty ? _iosProdInterstitial : _iosTestInterstitial;
    }
  }

  static String get rewardedAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _androidTestRewarded : _iosTestRewarded;
    }
    if (Platform.isAndroid) {
      return _androidProdRewarded.isNotEmpty ? _androidProdRewarded : _androidTestRewarded;
    } else {
      return _iosProdRewarded.isNotEmpty ? _iosProdRewarded : _iosTestRewarded;
    }
  }

  static String get appOpenAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _androidTestAppOpen : _iosTestAppOpen;
    }
    if (Platform.isAndroid) {
      return _androidProdAppOpen.isNotEmpty ? _androidProdAppOpen : _androidTestAppOpen;
    } else {
      return _iosProdAppOpen.isNotEmpty ? _iosProdAppOpen : _iosTestAppOpen;
    }
  }

  static String get nativeAdUnitId {
    if (kDebugMode) {
      return Platform.isAndroid ? _androidTestNative : _iosTestNative;
    }
    if (Platform.isAndroid) {
      return _androidProdNative.isNotEmpty ? _androidProdNative : _androidTestNative;
    } else {
      return _iosProdNative.isNotEmpty ? _iosProdNative : _iosTestNative;
    }
  }
}
