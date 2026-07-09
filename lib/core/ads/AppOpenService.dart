import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../features/player/player_provider.dart';
import '../../features/share_intent/share_intent_provider.dart';
import 'AdManager.dart';
import 'ConsentService.dart';
import 'InterstitialService.dart';

final appOpenServiceProvider = Provider<AppOpenService>((ref) {
  return AppOpenService(ref);
});

class AppOpenService with WidgetsBindingObserver {
  final Ref _ref;
  AppOpenAd? _appOpenAd;
  bool _isLoading = false;
  DateTime? _pausedTime;
  bool _isFirstLaunch = true;

  // 4-hour background resume threshold to display App Open Ad
  static const Duration _resumeThreshold = Duration(hours: 4);

  AppOpenService(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    
    _ref.listen<bool>(adConsentProvider, (prev, next) {
      if (next) {
        preloadAppOpenAd();
      }
    });
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _handleAppResume();
    }
  }

  void preloadAppOpenAd() {
    if (_appOpenAd != null || _isLoading) return;

    final isConsentGranted = _ref.read(adConsentProvider);
    final isAdFree = _ref.read(adFreeProvider);
    if (!isConsentGranted || isAdFree) return;

    _isLoading = true;
    AppOpenAd.load(
      adUnitId: AdManager.appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isLoading = false;
          debugPrint('AppOpenAd loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('AppOpenAd failed to load: $error');
          _appOpenAd = null;
          _isLoading = false;
          // Retry loading after a delay of 60 seconds
          Future.delayed(const Duration(seconds: 60), () {
            preloadAppOpenAd();
          });
        },
      ),
    );
  }

  void _handleAppResume() {
    // 1. Skip on initial launch
    if (_isFirstLaunch) {
      _isFirstLaunch = false;
      preloadAppOpenAd();
      return;
    }

    final isAdFree = _ref.read(adFreeProvider);
    if (isAdFree) return;

    final now = DateTime.now();
    
    // 2. Check if background duration threshold has elapsed
    if (_pausedTime == null || now.difference(_pausedTime!) < _resumeThreshold) {
      debugPrint('AppOpenAd skipped: Resume threshold of 4 hours not reached.');
      return;
    }

    // 3. Skip if music is playing to avoid disruption
    final isPlaying = _ref.read(playerProvider).isPlaying;
    if (isPlaying) {
      debugPrint('AppOpenAd skipped: Audio currently playing.');
      return;
    }

    // 4. Skip if extraction is running
    final extractionStep = _ref.read(extractionFlowProvider).step;
    final isExtracting = extractionStep == ExtractionStep.submitting ||
        extractionStep == ExtractionStep.extracting ||
        extractionStep == ExtractionStep.downloading ||
        extractionStep == ExtractionStep.saving;
    if (isExtracting) {
      debugPrint('AppOpenAd skipped: Extraction flow in progress.');
      return;
    }

    // 5. Show ad if available
    if (_appOpenAd == null) {
      debugPrint('AppOpenAd not preloaded. Fetching now.');
      preloadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _appOpenAd = null;
        preloadAppOpenAd(); // Load next
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('AppOpenAd failed to show: $error');
        ad.dispose();
        _appOpenAd = null;
        preloadAppOpenAd(); // Load next
      },
    );

    debugPrint('Displaying AppOpenAd.');
    _appOpenAd!.show();
  }
}
