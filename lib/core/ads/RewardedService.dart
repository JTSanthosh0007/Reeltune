import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'AdManager.dart';
import 'ConsentService.dart';
import 'InterstitialService.dart';
import 'AdFreeService.dart';

// Provider to manage premium unlock state (e.g. granted via Rewarded Ads)
final premiumFeaturesProvider = StateNotifierProvider<PremiumFeaturesNotifier, bool>((ref) {
  return PremiumFeaturesNotifier();
});

class PremiumFeaturesNotifier extends StateNotifier<bool> {
  PremiumFeaturesNotifier() : super(false);

  void unlockPremiumFeatures() {
    state = true;
  }

  void lockPremiumFeatures() {
    state = false;
  }
}

final rewardedServiceProvider = Provider<RewardedService>((ref) {
  return RewardedService(ref);
});

class RewardedService {
  final Ref _ref;
  RewardedAd? _rewardedAd;
  bool _isLoading = false;

  RewardedService(this._ref) {
    _ref.listen<bool>(adConsentProvider, (prev, next) {
      if (next) {
        preloadRewardedAd();
      }
    });
  }

  void preloadRewardedAd() {
    if (_rewardedAd != null || _isLoading) return;

    final isConsentGranted = _ref.read(adConsentProvider);
    if (!isConsentGranted) return;

    _isLoading = true;
    RewardedAd.load(
      adUnitId: AdManager.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isLoading = false;
          debugPrint('RewardedAd loaded successfully.');
        },
        onAdFailedToLoad: (error) {
          debugPrint('RewardedAd failed to load: $error');
          _rewardedAd = null;
          _isLoading = false;
          // Retry loading after a delay of 30 seconds
          Future.delayed(const Duration(seconds: 30), () {
            preloadRewardedAd();
          });
        },
      ),
    );
  }

  void showRewardedAd({
    required BuildContext context,
    required void Function(RewardItem reward) onRewardGranted,
    required VoidCallback onAdDismissed,
  }) {
    if (_rewardedAd == null) {
      debugPrint('No preloaded RewardedAd available. Preloading now.');
      preloadRewardedAd();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad is loading, please try again in a few seconds...')),
      );
      return;
    }

    bool rewardVerified = false;

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        preloadRewardedAd(); // Preload next
        if (!rewardVerified) {
          debugPrint('Ad dismissed before reward criteria was met.');
        }
        onAdDismissed();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('RewardedAd failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        preloadRewardedAd(); // Preload next
        onAdDismissed();
      },
    );

    debugPrint('Displaying RewardedAd.');
    _rewardedAd!.show(
      onUserEarnedReward: (adWithoutView, reward) {
        rewardVerified = true;
        debugPrint('User earned reward: ${reward.amount} ${reward.type}');
        _ref.read(adFreeProvider.notifier).grantAdFreeDuration(const Duration(hours: 24));
        onRewardGranted(reward);
      },
    );
  }
}
