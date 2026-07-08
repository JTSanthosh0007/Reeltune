import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import 'player_provider.dart';

class FullPlayerScreen extends ConsumerWidget {
  const FullPlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final clip = playerState.currentClip;

    if (clip == null) {
      return const SizedBox.shrink();
    }

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            Theme.of(context).scaffoldBackgroundColor,
            Theme.of(context).scaffoldBackgroundColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppColors.getAdaptiveSurfaceBorder(context)),
          left: BorderSide(color: AppColors.getAdaptiveSurfaceBorder(context)),
          right: BorderSide(color: AppColors.getAdaptiveSurfaceBorder(context)),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          const SizedBox(height: 32),

          // Album art placeholder
          Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.3),
                  AppColors.skyBlue.withValues(alpha: 0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.music_note_rounded,
              color: AppColors.primaryLight,
              size: 80,
            ),
          )
              .animate(
                onPlay: (controller) => controller.repeat(reverse: true),
              )
              .scale(
                begin: const Offset(1, 1),
                end: const Offset(1.03, 1.03),
                duration: 3000.ms,
                curve: Curves.easeInOut,
              ),

          const SizedBox(height: 24),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              clip.title,
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          const SizedBox(height: 8),

          // Platform badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.glassBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(clip.platformIcon, style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  clip.sourcePlatform ?? 'Local',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Seek bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: playerState.progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      final position = Duration(
                        milliseconds:
                            (value * playerState.duration.inMilliseconds)
                                .round(),
                      );
                      ref.read(playerProvider.notifier).seek(position);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(playerState.position),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _formatDuration(playerState.duration),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Quick Adjustments Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Speed Selector
                TextButton.icon(
                  onPressed: () => _showSpeedMenu(context, ref, playerState.speed),
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: Text('${playerState.speed.toStringAsFixed(1)}x'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Sleep Timer
                TextButton.icon(
                  onPressed: () => _showSleepTimerMenu(context, ref, playerState.sleepTimerRemaining),
                  icon: Icon(
                    Icons.timer_outlined,
                    size: 18,
                    color: playerState.sleepTimerRemaining != null ? AppColors.primary : AppColors.textTertiary,
                  ),
                  label: Text(
                    playerState.sleepTimerRemaining != null
                        ? _formatSleepTimer(playerState.sleepTimerRemaining!)
                        : 'Sleep',
                    style: TextStyle(
                      color: playerState.sleepTimerRemaining != null ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                // Audio Enhancements Dialog Trigger
                IconButton(
                  onPressed: () => _showEnhancementsMenu(context, ref, playerState),
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  color: AppColors.primary,
                  style: IconButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Loop
              IconButton(
                onPressed: () {
                  ref.read(playerProvider.notifier).toggleLoop();
                },
                icon: Icon(
                  Icons.repeat_rounded,
                  color: playerState.isLooping
                      ? AppColors.primary
                      : AppColors.textTertiary,
                  size: 24,
                ),
              ),

              const SizedBox(width: 16),

              // Rewind 10s
              IconButton(
                onPressed: () {
                  ref
                      .read(playerProvider.notifier)
                      .seekRelative(const Duration(seconds: -10));
                },
                icon: const Icon(
                  Icons.replay_10_rounded,
                  color: AppColors.textPrimary,
                  size: 32,
                ),
              ),

              const SizedBox(width: 16),

              // Play/Pause (large)
              GestureDetector(
                onTap: () {
                  ref.read(playerProvider.notifier).togglePlayPause();
                },
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: playerState.isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          )
                        : Icon(
                            playerState.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                            key: ValueKey(playerState.isPlaying),
                          ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Forward 10s
              IconButton(
                onPressed: () {
                  ref
                      .read(playerProvider.notifier)
                      .seekRelative(const Duration(seconds: 10));
                },
                icon: const Icon(
                  Icons.forward_10_rounded,
                  color: AppColors.textPrimary,
                  size: 32,
                ),
              ),

              const SizedBox(width: 16),

              // Stop
              IconButton(
                onPressed: () {
                  ref.read(playerProvider.notifier).stop();
                  Navigator.of(context).pop();
                },
                icon: const Icon(
                  Icons.stop_rounded,
                  color: AppColors.textTertiary,
                  size: 24,
                ),
              ),
            ],
          ),

          const SizedBox(height: 48),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatSleepTimer(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _showSpeedMenu(BuildContext context, WidgetRef ref, double currentSpeed) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Playback Speed', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
                final isSelected = speed == currentSpeed;
                return ChoiceChip(
                  label: Text('${speed.toStringAsFixed(2)}x'),
                  selected: isSelected,
                  selectedColor: AppColors.primary.withValues(alpha: 0.2),
                  checkmarkColor: AppColors.primary,
                  onSelected: (selected) {
                    if (selected) {
                      ref.read(playerProvider.notifier).setPlaybackSpeed(speed);
                      Navigator.of(context).pop();
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimerMenu(BuildContext context, WidgetRef ref, Duration? remainingTime) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sleep Timer', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.timer_off_rounded),
              title: const Text('Turn Off'),
              trailing: remainingTime == null ? const Icon(Icons.check, color: AppColors.primary) : null,
              onTap: () {
                ref.read(playerProvider.notifier).cancelSleepTimer();
                Navigator.of(context).pop();
              },
            ),
            ...[5, 15, 30, 45, 60].map((mins) {
              return ListTile(
                leading: const Icon(Icons.snooze_rounded),
                title: Text('$mins Minutes'),
                onTap: () {
                  ref.read(playerProvider.notifier).setSleepTimer(Duration(minutes: mins));
                  Navigator.of(context).pop();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showEnhancementsMenu(BuildContext context, WidgetRef ref, PlayerState state) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Audio Enhancements', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Customize EQ presets for standard inputs.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Bass Boost'),
                    subtitle: const Text('Enhanced low-end frequencies'),
                    value: state.isBassBoostEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      ref.read(playerProvider.notifier).toggleBassBoost(val);
                      setModalState(() {
                        state = state.copyWith(isBassBoostEnabled: val);
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Treble Boost'),
                    subtitle: const Text('Enhanced clarity and highs'),
                    value: state.isTrebleBoostEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      ref.read(playerProvider.notifier).toggleTrebleBoost(val);
                      setModalState(() {
                        state = state.copyWith(isTrebleBoostEnabled: val);
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Vocal Booster'),
                    subtitle: const Text('Highlight vocal track clarity'),
                    value: state.isVocalEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      ref.read(playerProvider.notifier).toggleVocalEnhancement(val);
                      setModalState(() {
                        state = state.copyWith(isVocalEnabled: val);
                      });
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Loudness Normalizer'),
                    subtitle: const Text('Maintain consistent playback volume'),
                    value: state.isLoudnessNormalizerEnabled,
                    activeColor: AppColors.primary,
                    onChanged: (val) {
                      ref.read(playerProvider.notifier).toggleLoudnessNormalization(val);
                      setModalState(() {
                        state = state.copyWith(isLoudnessNormalizerEnabled: val);
                      });
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
