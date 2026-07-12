import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/app_colors.dart';
import 'AdManager.dart';
import 'ConsentService.dart';
import 'InterstitialService.dart';
import 'AdFreeService.dart';

class NativeAdWidget extends ConsumerStatefulWidget {
  const NativeAdWidget({super.key});

  @override
  ConsumerState<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends ConsumerState<NativeAdWidget> {
  NativeAd? _nativeAd;
  bool _isLoaded = false;
  bool _isLoading = false;
  int _retryAttempt = 0;

  @override
  void initState() {
    super.initState();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    final consentReady = ref.read(adConsentProvider);
    final isAdFree = ref.read(adFreeProvider);

    if (!consentReady || isAdFree || _isLoading) return;

    setState(() {
      _isLoaded = false;
      _isLoading = true;
    });

    _nativeAd = NativeAd(
      adUnitId: AdManager.nativeAdUnitId,
      factoryId: 'listTile',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _nativeAd = ad as NativeAd;
            _isLoaded = true;
            _isLoading = false;
            _retryAttempt = 0;
          });
          debugPrint('NativeAd loaded successfully.');
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('NativeAd failed to load: $error');
          ad.dispose();
          if (!mounted) return;

          setState(() {
            _nativeAd = null;
            _isLoaded = false;
            _isLoading = false;
          });

          // Retry with exponential backoff
          _retryAttempt++;
          final retryDelay = Duration(seconds: min(pow(2, _retryAttempt).toInt(), 64));
          Future.delayed(retryDelay, () {
            if (mounted) {
              _loadNativeAd();
            }
          });
        },
      ),
    );

    _nativeAd!.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide native ads completely if user is ad-free
    final isAdFree = ref.watch(adFreeProvider);
    if (isAdFree) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final placeholderColor = isDark ? AppColors.darkCard : AppColors.gray100;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.surfaceBorder;

    if (!_isLoaded || _nativeAd == null) {
      // Return a compact, zero-layout-shift placeholder matching standard clip list tile
      return Container(
        height: 76,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: placeholderColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.analytics_outlined,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 12,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white12 : Colors.black12,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black12.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 76,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: AdWidget(ad: _nativeAd!),
    );
  }
}
