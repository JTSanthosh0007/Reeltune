import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../settings/legal_dialog.dart';
import 'onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Skip button
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      _currentPage == 1 ? '' : 'Skip',
                      style: const TextStyle(color: AppColors.textTertiary),
                    ),
                  ),
                ),
              ),

              // Pages
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (page) =>
                      setState(() => _currentPage = page),
                  children: const [
                    _OnboardingPage1(),
                    _OnboardingPage2(),
                  ],
                ),
              ),

              // Page indicator + button
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  children: [
                    // Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(2, (index) {
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: _currentPage == index ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? AppColors.primary
                                : AppColors.surfaceBorder,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      }),
                    ),

                    const SizedBox(height: 32),

                    // Action button
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: FilledButton(
                        onPressed: () {
                          if (_currentPage < 1) {
                            _pageController.nextPage(
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOutCubic,
                            );
                          } else {
                            _completeOnboarding();
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          _currentPage == 1 ? 'Get Started' : 'Next',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    // Show legal dialog first
    if (mounted) {
      await LegalDialog.show(context, force: false);
    }
    // Mark onboarding as complete
    await ref.read(onboardingControllerProvider).completeOnboarding();
  }
}

class _OnboardingPage1 extends StatelessWidget {
  const _OnboardingPage1();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.skyBlue.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Share icon
                Positioned(
                  top: 30,
                  right: 35,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.skyBlue.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.share_rounded,
                      color: AppColors.skyBlue,
                      size: 24,
                    ),
                  ).animate(
                    onPlay: (c) => c.repeat(reverse: true),
                  ).scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1.1, 1.1),
                    duration: 2000.ms,
                  ),
                ),
                // Arrow
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: AppColors.textTertiary,
                  size: 32,
                ),
                // Music icon
                Positioned(
                  bottom: 30,
                  left: 35,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ).animate(
                    onPlay: (c) => c.repeat(reverse: true),
                  ).scale(
                    begin: const Offset(1.1, 1.1),
                    end: const Offset(0.9, 0.9),
                    duration: 2000.ms,
                  ),
                ),
              ],
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),

          const SizedBox(height: 48),

          Text(
            'Share Any Reel',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

          const SizedBox(height: 16),

          Text(
            'Open Instagram, TikTok, or YouTube.\nTap share on any reel and select ReelTune.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

          const SizedBox(height: 24),

          // Platform icons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PlatformBadge(icon: '📷', label: 'Instagram'),
              const SizedBox(width: 12),
              _PlatformBadge(icon: '🎵', label: 'TikTok'),
              const SizedBox(width: 12),
              _PlatformBadge(icon: '▶️', label: 'YouTube'),
            ],
          ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
        ],
      ),
    );
  }
}

class _OnboardingPage2 extends StatelessWidget {
  const _OnboardingPage2();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.coral.withValues(alpha: 0.15),
                  AppColors.primary.withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: AppColors.coral.withValues(alpha: 0.3),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mini album cards
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _MiniAlbumCard(color: AppColors.primary),
                    const SizedBox(width: 8),
                    _MiniAlbumCard(color: AppColors.skyBlue),
                    const SizedBox(width: 8),
                    _MiniAlbumCard(color: AppColors.coral),
                  ],
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .slideY(begin: -0.05, end: 0.05, duration: 3000.ms),
                const SizedBox(height: 12),
                const Icon(
                  Icons.headphones_rounded,
                  color: AppColors.textSecondary,
                  size: 36,
                ),
              ],
            ),
          ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),

          const SizedBox(height: 48),

          Text(
            'Build Your Library',
            style: Theme.of(context).textTheme.displayMedium,
            textAlign: TextAlign.center,
          ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

          const SizedBox(height: 16),

          Text(
            'Organize audio clips into custom albums.\nListen offline anytime, anywhere.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
          ).animate().fadeIn(delay: 400.ms, duration: 400.ms),

          const SizedBox(height: 24),

          // Features
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FeatureBadge(
                  icon: Icons.album_rounded, label: 'Albums'),
              const SizedBox(width: 12),
              _FeatureBadge(
                  icon: Icons.play_circle_rounded, label: 'Player'),
              const SizedBox(width: 12),
              _FeatureBadge(
                  icon: Icons.wifi_off_rounded, label: 'Offline'),
            ],
          ).animate().fadeIn(delay: 600.ms, duration: 400.ms),
        ],
      ),
    );
  }
}

class _MiniAlbumCard extends StatelessWidget {
  final Color color;

  const _MiniAlbumCard({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Icon(Icons.album_rounded, color: color, size: 16),
    );
  }
}

class _PlatformBadge extends StatelessWidget {
  final String icon;
  final String label;

  const _PlatformBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}

class _FeatureBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.glassBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
