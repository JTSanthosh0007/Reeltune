import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:audio_service/audio_service.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'features/onboarding/onboarding_provider.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/home/main_navigation_screen.dart';
import 'features/share_intent/share_intent_handler.dart';
import 'features/settings/theme_provider.dart';

import 'core/config/env_config.dart';
import 'core/config/AdManager.dart';
import 'core/ads/AppOpenService.dart';
import 'core/ads/InterstitialService.dart';
import 'core/ads/RewardedService.dart';
import 'features/player/audio_handler.dart';
import 'core/db/album_repository.dart';
import 'core/db/clip_repository.dart';
import 'core/db/demo_data_initializer.dart';
import 'main.dart'; // import global audioHandler

class ReelTuneApp extends ConsumerWidget {
  const ReelTuneApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'ReelTune',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const _AppEntryPoint(),
    );
  }
}

class _AppEntryPoint extends ConsumerStatefulWidget {
  const _AppEntryPoint();

  @override
  ConsumerState<_AppEntryPoint> createState() => _AppEntryPointState();
}

class _AppEntryPointState extends ConsumerState<_AppEntryPoint> {
  bool _isInitializing = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Initialize environment configuration
      await EnvConfig.initialize();

      // 2. Initialize Audio Handler and AdManager concurrently in the background
      final results = await Future.wait<dynamic>([
        AdManager.initialize(),
        initAudioHandler(),
      ]);

      audioHandler = results[1] as AudioHandler;

      // 3. Post-frame initialization (Intent listener, preloading ads, demo data)
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (mounted) {
          ref.read(shareIntentHandlerProvider.notifier).initialize(context);
        }
        
        // Trigger ad service preloading
        ref.read(appOpenServiceProvider);
        ref.read(interstitialServiceProvider);
        ref.read(rewardedServiceProvider);

        // Initialize demo data in Development/Debug Mode
        final albumRepo = ref.read(albumRepositoryProvider);
        final clipRepo = ref.read(clipRepositoryProvider);
        await DemoDataInitializer.initialize(albumRepo, clipRepo);
      });

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() {
          _initError = e.toString();
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const _SplashLoadingScreen();
    }

    if (_initError != null) {
      return Scaffold(
        backgroundColor: Theme.of(context).brightness == Brightness.dark 
            ? AppColors.darkBackground 
            : AppColors.cream,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Initialization Failed',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _isInitializing = true;
                      _initError = null;
                    });
                    _initializeApp();
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final onboardingComplete = ref.watch(onboardingCompleteProvider);

    return onboardingComplete.when(
      data: (complete) {
        if (!complete) {
          return const OnboardingScreen();
        }
        return const MainNavigationScreen();
      },
      loading: () => const _SplashLoadingScreen(),
      error: (_, __) => const MainNavigationScreen(),
    );
  }
}

class _SplashLoadingScreen extends StatelessWidget {
  const _SplashLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.cream;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo inside circular container with shadow
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? AppColors.darkCard : Colors.white,
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.08),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(65),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.primary,
                      child: const Icon(
                        Icons.music_note_rounded,
                        color: Colors.white,
                        size: 56,
                      ),
                    ),
                  ),
                ),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.05, 1.05),
                  duration: 1500.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 32),
            // Loading indicator
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
