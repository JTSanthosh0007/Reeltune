import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/app_colors.dart';
import 'AdManager.dart';
import 'ConsentService.dart';
import 'AdFreeService.dart';

final bannerAdHeightProvider = StateProvider<double>((ref) => 0.0);

class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({super.key});

  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  int _retryAttempt = 0;
  AdSize? _adSize;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // Recalculate adaptive size when dependencies change (e.g. orientation, screen size)
    _loadAdaptiveBanner();
  }

  Future<void> _loadAdaptiveBanner() async {
    final consentReady = ref.read(adConsentProvider);
    final isAdFree = ref.read(adFreeProvider);
    if (!consentReady || isAdFree || _isLoading) return;

    final width = MediaQuery.of(context).size.width.truncate();
    final AnchoredAdaptiveBannerAdSize? size =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);

    if (size == null) {
      debugPrint('Unable to get adaptive banner size.');
      return;
    }

    setState(() {
      _adSize = size;
    });

    _loadAd();
  }

  void _loadAd() {
    if (_adSize == null || _isLoading) return;

    // Dispose previous ad if it exists
    _bannerAd?.dispose();
    _bannerAd = null;

    setState(() {
      _isLoaded = false;
      _isLoading = true;
    });

    _bannerAd = BannerAd(
      adUnitId: AdManager.bannerAdUnitId,
      size: _adSize!,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isLoaded = true;
            _isLoading = false;
            _retryAttempt = 0; // Reset retry counter on success
          });
          ref.read(bannerAdHeightProvider.notifier).state = _adSize?.height.toDouble() ?? 50.0;
          debugPrint('BannerAd loaded successfully.');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('BannerAd failed to load (code: ${error.code}): ${error.message}');
          ad.dispose();
          if (!mounted) return;

          setState(() {
            _bannerAd = null;
            _isLoaded = false;
            _isLoading = false;
          });
          ref.read(bannerAdHeightProvider.notifier).state = 0.0;

          // Exponential backoff retry (cap at 64 seconds)
          _retryAttempt++;
          final retryDelay = Duration(seconds: min(pow(2, _retryAttempt).toInt(), 64));
          debugPrint('Retrying banner load in ${retryDelay.inSeconds} seconds...');
          Future.delayed(retryDelay, () {
            if (mounted) {
              _loadAd();
            }
          });
        },
      ),
    );

    _bannerAd!.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    Future.microtask(() {
      ref.read(bannerAdHeightProvider.notifier).state = 0.0;
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdFree = ref.watch(adFreeProvider);

    if (isAdFree) {
      if (_bannerAd != null || _isLoaded || _isLoading) {
        _bannerAd?.dispose();
        _bannerAd = null;
        _isLoaded = false;
        _isLoading = false;
        Future.microtask(() {
          ref.read(bannerAdHeightProvider.notifier).state = 0.0;
        });
      }
    }

    // Listen for consent readiness to trigger the load
    ref.listen<bool>(adConsentProvider, (prev, next) {
      if (next && !isAdFree && !_isLoaded && !_isLoading) {
        _loadAdaptiveBanner();
      }
    });

    // Listen for ad-free state changes
    ref.listen<bool>(adFreeProvider, (prev, next) {
      if (next) {
        _bannerAd?.dispose();
        setState(() {
          _bannerAd = null;
          _isLoaded = false;
          _isLoading = false;
        });
        ref.read(bannerAdHeightProvider.notifier).state = 0.0;
      } else {
        _loadAdaptiveBanner();
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? AppColors.darkCard : AppColors.gray100;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.surfaceBorder;

    if (isAdFree || !_isLoaded || _bannerAd == null || _adSize == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: _adSize!.width.toDouble(),
      height: _adSize!.height.toDouble(),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: placeholderColor,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
