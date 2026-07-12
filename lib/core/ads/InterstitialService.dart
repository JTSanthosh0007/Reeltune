import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../features/player/player_provider.dart';
import '../../features/share_intent/share_intent_provider.dart';
import 'AdManager.dart';
import 'AdFreeService.dart';
import 'ConsentService.dart';

final interstitialServiceProvider = Provider<InterstitialService>((ref) {
  return InterstitialService(ref);
});

class InterstitialService {
  final Ref _ref;
  InterstitialAd? _interstitialAd;
  bool _isLoading = false;
  DateTime? _lastShownTime;

  // 3-minute cooldown between interstitial ads to protect UX
  static const Duration _cooldownDuration = Duration(minutes: 3);

  InterstitialService(this._ref) {
    _ref.listen<bool>(adConsentProvider, (prev, next) {
      if (next) {
        preloadInterstitial();
      }
    });
  }

  void preloadInterstitial() {
    if (_interstitialAd != null || _isLoading) return;

    final isConsentGranted = _ref.read(adConsentProvider);
    final isAdFree = _ref.read(adFreeProvider);
    if (!isConsentGranted || isAdFree) return;

    _isLoading = true;
    InterstitialAd.load(
      adUnitId: AdManager.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isLoading = false;
          debugPrint('InterstitialAd loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('InterstitialAd failed to load: $error');
          _interstitialAd = null;
          _isLoading = false;
          // Retry loading after a delay of 30 seconds
          Future.delayed(const Duration(seconds: 30), () {
            preloadInterstitial();
          });
        },
      ),
    );
  }

  void showInterstitialIfAllowed({required VoidCallback onAdDismissed}) {
    final now = DateTime.now();
    final isAdFree = _ref.read(adFreeProvider);
    
    // 1. Check if user is ad-free
    if (isAdFree) {
      onAdDismissed();
      return;
    }

    // 2. Check if ad is preloaded
    if (_interstitialAd == null) {
      debugPrint('No preloaded InterstitialAd available. Preloading now.');
      preloadInterstitial();
      onAdDismissed();
      return;
    }

    // 3. Frequency capping checks
    if (_lastShownTime != null && now.difference(_lastShownTime!) < _cooldownDuration) {
      debugPrint('InterstitialAd display skipped: Cooldown active.');
      onAdDismissed();
      return;
    }

    // 4. Do not interrupt active music playback
    final isPlaying = _ref.read(playerProvider).isPlaying;
    if (isPlaying) {
      debugPrint('InterstitialAd display skipped: Audio currently playing.');
      onAdDismissed();
      return;
    }

    // 5. Do not show during active background extractions
    final extractionStep = _ref.read(extractionFlowProvider).step;
    final isExtracting = extractionStep == ExtractionStep.submitting ||
        extractionStep == ExtractionStep.extracting ||
        extractionStep == ExtractionStep.downloading ||
        extractionStep == ExtractionStep.saving;
    if (isExtracting) {
      debugPrint('InterstitialAd display skipped: Extraction flow in progress.');
      onAdDismissed();
      return;
    }

    // Set ad listener events
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        _lastShownTime = DateTime.now();
        preloadInterstitial(); // preload next
        onAdDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('InterstitialAd failed to show: $error');
        ad.dispose();
        _interstitialAd = null;
        preloadInterstitial(); // preload next
        onAdDismissed();
      },
    );

    debugPrint('Displaying InterstitialAd.');
    _interstitialAd!.show();
  }
}
