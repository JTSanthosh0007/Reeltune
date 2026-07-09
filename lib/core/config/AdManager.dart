import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'AdMobConfig.dart';
import 'BuildConfig.dart';

class AdManager {
  AdManager._();

  static bool _initialized = false;
  static int _interstitialRetryAttempts = 0;
  static int _rewardedRetryAttempts = 0;
  static int _appOpenRetryAttempts = 0;

  static InterstitialAd? _interstitialAd;
  static RewardedAd? _rewardedAd;
  static AppOpenAd? _appOpenAd;

  static bool _isPreloadingInterstitial = false;
  static bool _isPreloadingRewarded = false;
  static bool _isPreloadingAppOpen = false;

  /// Initialize Mobile Ads and log status
  static Future<void> initialize() async {
    if (_initialized) return;

    final testDevices = AdMobConfig.testDeviceIds;
    
    // Log setup status
    if (BuildConfig.useTestAds) {
      debugPrint('---------------------------------');
      debugPrint('TEST ADS ENABLED');
      debugPrint('App Environment: ${BuildConfig.environment.name.toUpperCase()}');
      debugPrint('Ad Environment: TEST ADS');
      debugPrint('App ID: ${AdMobConfig.appId}');
      if (testDevices.isNotEmpty) {
        debugPrint('TEST DEVICE REGISTERED');
        debugPrint('Configured Device IDs: $testDevices');
        debugPrint('Showing Test Ads');
      } else {
        debugPrint('THIS DEVICE IS NOT A TEST DEVICE.');
        debugPrint('Copy the following Test Device ID printed by Google Mobile Ads SDK in Logcat:');
        debugPrint('Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("xxxxxxxx"))');
        debugPrint('Add it into TEST_DEVICE_IDS in your env file.');
      }
      debugPrint('---------------------------------');
    } else {
      debugPrint('---------------------------------');
      debugPrint('PRODUCTION ADS ENABLED');
      debugPrint('App Environment: ${BuildConfig.environment.name.toUpperCase()}');
      debugPrint('Ad Environment: REAL PRODUCTION ADS');
      debugPrint('App ID: ${AdMobConfig.appId}');
      debugPrint('---------------------------------');
    }

    final requestConfiguration = RequestConfiguration(
      testDeviceIds: testDevices,
    );
    await MobileAds.instance.updateRequestConfiguration(requestConfiguration);
    await MobileAds.instance.initialize();

    _initialized = true;

    // Preload ads immediately after initialization
    preloadInterstitial();
    preloadRewarded();
    preloadAppOpen();
  }

  // --- Preloading & Retry Logic ---

  static Future<void> preloadInterstitial() async {
    if (_isPreloadingInterstitial || _interstitialAd != null) return;
    _isPreloadingInterstitial = true;

    final adUnitId = AdMobConfig.interstitialAdUnitId;
    debugPrint('[AdManager] Preloading Interstitial Ad: $adUnitId');

    await InterstitialAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdManager] Interstitial Loaded Successfully.');
          _interstitialAd = ad;
          _interstitialRetryAttempts = 0;
          _isPreloadingInterstitial = false;
          
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('[AdManager] Interstitial dismissed. Disposing and preloading next.');
              ad.dispose();
              _interstitialAd = null;
              preloadInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdManager] Interstitial failed to show: $error. Disposing and preloading next.');
              ad.dispose();
              _interstitialAd = null;
              preloadInterstitial();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isPreloadingInterstitial = false;
          _interstitialAd = null;
          debugPrint('[AdManager] Interstitial Failed to Load. Code: ${error.code}. Message: ${error.message}');
          _handleLoadFailure(
            adUnitType: 'Interstitial',
            errorCode: error.code,
            retryAttempts: _interstitialRetryAttempts++,
            retryAction: preloadInterstitial,
          );
        },
      ),
    );
  }

  static Future<void> preloadRewarded() async {
    if (_isPreloadingRewarded || _rewardedAd != null) return;
    _isPreloadingRewarded = true;

    final adUnitId = AdMobConfig.rewardedAdUnitId;
    debugPrint('[AdManager] Preloading Rewarded Ad: $adUnitId');

    await RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdManager] Rewarded Ad Loaded Successfully.');
          _rewardedAd = ad;
          _rewardedRetryAttempts = 0;
          _isPreloadingRewarded = false;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('[AdManager] Rewarded ad dismissed. Disposing and preloading next.');
              ad.dispose();
              _rewardedAd = null;
              preloadRewarded();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdManager] Rewarded ad failed to show: $error. Disposing and preloading next.');
              ad.dispose();
              _rewardedAd = null;
              preloadRewarded();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isPreloadingRewarded = false;
          _rewardedAd = null;
          debugPrint('[AdManager] Rewarded Ad Failed to Load. Code: ${error.code}. Message: ${error.message}');
          _handleLoadFailure(
            adUnitType: 'Rewarded',
            errorCode: error.code,
            retryAttempts: _rewardedRetryAttempts++,
            retryAction: preloadRewarded,
          );
        },
      ),
    );
  }

  static Future<void> preloadAppOpen() async {
    if (_isPreloadingAppOpen || _appOpenAd != null) return;
    _isPreloadingAppOpen = true;

    final adUnitId = AdMobConfig.appOpenAdUnitId;
    debugPrint('[AdManager] Preloading App Open Ad: $adUnitId');

    await AppOpenAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      appOpenAdLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          debugPrint('[AdManager] App Open Loaded Successfully.');
          _appOpenAd = ad;
          _appOpenRetryAttempts = 0;
          _isPreloadingAppOpen = false;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              debugPrint('[AdManager] App Open ad dismissed. Disposing and preloading next.');
              ad.dispose();
              _appOpenAd = null;
              preloadAppOpen();
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              debugPrint('[AdManager] App Open ad failed to show: $error. Disposing and preloading next.');
              ad.dispose();
              _appOpenAd = null;
              preloadAppOpen();
            },
          );
        },
        onAdFailedToLoad: (error) {
          _isPreloadingAppOpen = false;
          _appOpenAd = null;
          debugPrint('[AdManager] App Open Failed to Load. Code: ${error.code}. Message: ${error.message}');
          _handleLoadFailure(
            adUnitType: 'AppOpen',
            errorCode: error.code,
            retryAttempts: _appOpenRetryAttempts++,
            retryAction: preloadAppOpen,
          );
        },
      ),
    );
  }

  // --- Show Methods ---

  static Future<bool> showInterstitial(BuildContext context) async {
    if (_interstitialAd == null) {
      debugPrint('[AdManager] Interstitial ad not ready. Triggering load and returning false.');
      preloadInterstitial();
      return false;
    }
    await _interstitialAd!.show();
    return true;
  }

  static Future<bool> showRewarded(BuildContext context, {required OnUserEarnedRewardListener onUserEarnedReward}) async {
    if (_rewardedAd == null) {
      debugPrint('[AdManager] Rewarded ad not ready. Triggering load and returning false.');
      preloadRewarded();
      return false;
    }
    await _rewardedAd!.show(onUserEarnedReward: onUserEarnedReward);
    return true;
  }

  static Future<bool> showAppOpen() async {
    if (_appOpenAd == null) {
      debugPrint('[AdManager] App Open ad not ready. Triggering load and returning false.');
      preloadAppOpen();
      return false;
    }
    await _appOpenAd!.show();
    return true;
  }

  // Helper retry scheduler with backoff
  static void _handleLoadFailure({
    required String adUnitType,
    required int errorCode,
    required int retryAttempts,
    required VoidCallback retryAction,
  }) {
    if (errorCode == 3) {
      debugPrint('[AdManager] Ad failed to fill ($adUnitType). Waiting for queue refresh.');
      return;
    }

    if (retryAttempts >= 5) {
      debugPrint('[AdManager] Max retry limit reached for $adUnitType. Stopping automatic retry.');
      return;
    }

    final delaySeconds = (1 << retryAttempts) * 5; // 5s, 10s, 20s, 40s, 80s
    debugPrint('[AdManager] Scheduling retry for $adUnitType in $delaySeconds seconds (Attempt ${retryAttempts + 1}/5).');
    Timer(Duration(seconds: delaySeconds), retryAction);
  }
}
