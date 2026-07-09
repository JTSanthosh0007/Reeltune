import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../albums/album_providers.dart';
import 'player_provider.dart';

class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final clip = playerState.currentClip;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (clip == null) {
      return const SizedBox.shrink();
    }

    // Play or stop rotation animation depending on player status
    if (playerState.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!playerState.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }

    // Get current album details for cover image resolution
    final albums = ref.watch(albumsProvider).value ?? [];
    final album = albums.firstWhere((a) => a.id == clip.albumId, orElse: () => null as dynamic);

    final coverColor = album != null && album.coverColor != null
        ? Color(int.parse(album.coverColor!, radix: 16) | 0xFF000000)
        : AppColors.primary;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : AppColors.cream,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
            width: 1.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // 1. Drag handle bar
          Container(
            width: 44,
            height: 4.5,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBorder : AppColors.textTertiary,
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),

          // 2. Custom App Bar / Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                  onPressed: () => Navigator.of(context).pop(),
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
                Text(
                  'Now Playing',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert_rounded),
                  onPressed: () {},
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ],
            ),
          ),

          const Spacer(),

          // 3. Spinning Vinyl Record Design
          Center(
            child: AnimatedBuilder(
              animation: _rotationController,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotationController.value * 2 * 3.14159,
                  child: child,
                );
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Vinyl Disc
                  Container(
                    width: 260,
                    height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF0F1210) : Colors.grey[850],
                      boxShadow: [
                        BoxShadow(
                          color: coverColor.withValues(alpha: 0.15),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  // Concentric grooves
                  ...List.generate(6, (index) {
                    final size = 260.0 - (index * 25.0);
                    return Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.04),
                          width: 1,
                        ),
                      ),
                    );
                  }),
                  // Center Album Cover
                  Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: coverColor.withValues(alpha: 0.2),
                      border: Border.all(
                        color: isDark ? AppColors.darkBackground : Colors.white,
                        width: 4,
                      ),
                      image: album != null && album.coverImagePath != null
                          ? DecorationImage(
                              image: FileImage(File(album.coverImagePath!)),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: album == null || album.coverImagePath == null
                        ? Icon(
                            Icons.music_note_rounded,
                            color: coverColor,
                            size: 40,
                          )
                        : null,
                  ),
                  // Center Spindle Hole
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? AppColors.darkBackground : Colors.white,
                      border: Border.all(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // 4. Song Details (Title + Album + Favorite)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        clip.title,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        album?.name ?? 'Single Clip',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _isFavorited = !_isFavorited;
                    });
                  },
                  icon: Icon(
                    _isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isFavorited ? AppColors.primary : (isDark ? Colors.white70 : AppColors.textSecondary),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 5. Seek Bar / Progress Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                    thumbColor: AppColors.primary,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayColor: AppColors.primary.withValues(alpha: 0.15),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: playerState.progress.clamp(0.0, 1.0),
                    onChanged: (value) {
                      final position = Duration(
                        milliseconds: (value * playerState.duration.inMilliseconds).round(),
                      );
                      ref.read(playerProvider.notifier).seek(position);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(playerState.position),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                            ),
                      ),
                      Text(
                        _formatDuration(playerState.duration),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 6. Playback controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Shuffle
                IconButton(
                  onPressed: () {
                    ref.read(playerProvider.notifier).toggleShuffle();
                  },
                  icon: Icon(
                    Icons.shuffle_rounded,
                    color: playerState.isShuffleEnabled ? AppColors.primary : AppColors.textTertiary,
                    size: 24,
                  ),
                ),

                // Skip Previous
                IconButton(
                  onPressed: () {
                    ref.read(playerProvider.notifier).skipToPrevious();
                  },
                  icon: Icon(
                    Icons.skip_previous_rounded,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    size: 36,
                  ),
                ),

                // Play / Pause Circle
                GestureDetector(
                  onTap: () {
                    ref.read(playerProvider.notifier).togglePlayPause();
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: playerState.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Icon(
                              playerState.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 40,
                            ),
                    ),
                  ),
                ),

                // Skip Next
                IconButton(
                  onPressed: () {
                    ref.read(playerProvider.notifier).skipToNext();
                  },
                  icon: Icon(
                    Icons.skip_next_rounded,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    size: 36,
                  ),
                ),

                // Repeat
                IconButton(
                  onPressed: () {
                    ref.read(playerProvider.notifier).toggleLoop();
                  },
                  icon: Icon(
                    Icons.repeat_rounded,
                    color: playerState.isLooping ? AppColors.primary : AppColors.textTertiary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // 7. Footer controls (Equalizer/Waves, Share/Download, Playlist)
          Padding(
            padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Equalizer / Audio Enhancements Dialog
                IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  color: isDark ? Colors.white70 : AppColors.textSecondary,
                  onPressed: () => _showEnhancementsMenu(context, ref, playerState),
                ),
                // Sleep Timer
                IconButton(
                  icon: Icon(
                    Icons.timer_outlined,
                    color: playerState.sleepTimerRemaining != null
                        ? AppColors.primary
                        : (isDark ? Colors.white70 : AppColors.textSecondary),
                  ),
                  onPressed: () => _showSleepTimerMenu(context, ref, playerState.sleepTimerRemaining),
                ),
                // Play Speed
                TextButton(
                  onPressed: () => _showSpeedMenu(context, ref, playerState.speed),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark ? Colors.white70 : AppColors.textSecondary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 40),
                  ),
                  child: Text(
                    '${playerState.speed.toStringAsFixed(1)}x',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
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
