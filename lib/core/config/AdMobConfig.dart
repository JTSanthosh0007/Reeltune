import 'dart:io';
import 'BuildConfig.dart';

class AdMobConfig {
  AdMobConfig._();

  // Standard Google Test Ad Unit IDs
  static const String _androidTestBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _androidTestInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String _androidTestRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const String _androidTestRewardedInterstitial = 'ca-app-pub-3940256099942544/5354046379';
  static const String _androidTestNative = 'ca-app-pub-3940256099942544/2247696110';
  static const String _androidTestAppOpen = 'ca-app-pub-3940256099942544/9257395921';

  static const String _iosTestBanner = 'ca-app-pub-3940256099942544/2934735716';
  static const String _iosTestInterstitial = 'ca-app-pub-3940256099942544/4411468910';
  static const String _iosTestRewarded = 'ca-app-pub-3940256099942544/1712485313';
  static const String _iosTestRewardedInterstitial = 'ca-app-pub-3940256099942544/6978759866';
  static const String _iosTestNative = 'ca-app-pub-3940256099942544/3986693107';
  static const String _iosTestAppOpen = 'ca-app-pub-3940256099942544/5575462274';

  // Loaded at runtime from environment-specific .env file
  static Map<String, String> _envKeys = {};

  static void load(Map<String, String> keys) {
    _envKeys = keys;
  }

  static String get bannerAdUnitId {
    if (BuildConfig.useTestAds) {
      return Platform.isAndroid ? _androidTestBanner : _iosTestBanner;
    }
    final key = Platform.isAndroid ? 'ADMOB_BANNER_ID_ANDROID' : 'ADMOB_BANNER_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : (Platform.isAndroid ? _androidTestBanner : _iosTestBanner);
  }

  static String get interstitialAdUnitId {
    if (BuildConfig.useTestAds) {
      return Platform.isAndroid ? _androidTestInterstitial : _iosTestInterstitial;
    }
    final key = Platform.isAndroid ? 'ADMOB_INTERSTITIAL_ID_ANDROID' : 'ADMOB_INTERSTITIAL_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : (Platform.isAndroid ? _androidTestInterstitial : _iosTestInterstitial);
  }

  static String get rewardedAdUnitId {
    if (BuildConfig.useTestAds) {
      return Platform.isAndroid ? _androidTestRewarded : _iosTestRewarded;
    }
    final key = Platform.isAndroid ? 'ADMOB_REWARDED_ID_ANDROID' : 'ADMOB_REWARDED_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : (Platform.isAndroid ? _androidTestRewarded : _iosTestRewarded);
  }

  static String get rewardedInterstitialAdUnitId {
    if (BuildConfig.useTestAds) {
      return Platform.isAndroid ? _androidTestRewardedInterstitial : _iosTestRewardedInterstitial;
    }
    final key = Platform.isAndroid ? 'ADMOB_REWARDED_INTERSTITIAL_ID_ANDROID' : 'ADMOB_REWARDED_INTERSTITIAL_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : (Platform.isAndroid ? _androidTestRewardedInterstitial : _iosTestRewardedInterstitial);
  }

  static String get nativeAdUnitId {
    if (BuildConfig.useTestAds) {
      return Platform.isAndroid ? _androidTestNative : _iosTestNative;
    }
    final key = Platform.isAndroid ? 'ADMOB_NATIVE_ID_ANDROID' : 'ADMOB_NATIVE_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : (Platform.isAndroid ? _androidTestNative : _iosTestNative);
  }

  static String get appOpenAdUnitId {
    if (BuildConfig.useTestAds) {
      return Platform.isAndroid ? _androidTestAppOpen : _iosTestAppOpen;
    }
    final key = Platform.isAndroid ? 'ADMOB_APP_OPEN_ID_ANDROID' : 'ADMOB_APP_OPEN_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : (Platform.isAndroid ? _androidTestAppOpen : _iosTestAppOpen);
  }

  static String get appId {
    final key = Platform.isAndroid ? 'ADMOB_APP_ID_ANDROID' : 'ADMOB_APP_ID_IOS';
    final val = _envKeys[key] ?? '';
    return val.isNotEmpty ? val : 'ca-app-pub-2811908516993554~7577319258';
  }

  static List<String> get testDeviceIds {
    final idsStr = _envKeys['TEST_DEVICE_IDS'] ?? '';
    if (idsStr.trim().isEmpty) return [];
    return idsStr.split(',').map((id) => id.trim()).toList();
  }
}
