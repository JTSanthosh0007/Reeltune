import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/onboarding/onboarding_provider.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/home/main_navigation_screen.dart';
import 'features/share_intent/share_intent_handler.dart';

import 'features/settings/theme_provider.dart';

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
  @override
  void initState() {
    super.initState();
    // Initialize share intent listener
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shareIntentHandlerProvider.notifier).initialize(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onboardingComplete = ref.watch(onboardingCompleteProvider);

    return onboardingComplete.when(
      data: (complete) {
        if (!complete) {
          return const OnboardingScreen();
        }
        return const MainNavigationScreen();
      },
      loading: () => const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      ),
      error: (_, __) => const MainNavigationScreen(),
    );
  }
}
