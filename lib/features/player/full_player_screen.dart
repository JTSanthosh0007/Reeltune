import 'dart:io';
import 'dart:ui' as ui show Clip;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/album.dart';
import '../../core/models/clip.dart';
import '../../core/db/clip_repository.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import '../albums/album_providers.dart';
import '../../main.dart';
import 'audio_handler.dart';
import 'player_provider.dart';

class FullPlayerScreen extends ConsumerStatefulWidget {
  const FullPlayerScreen({super.key});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;
  double? _dragValue;

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
      // Show a styled loading placeholder instead of a blank white screen
      return Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.cream,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 4.5,
              margin: const EdgeInsets.only(top: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            const Spacer(),
            Icon(
              Icons.music_note_rounded,
              size: 80,
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading...',
              style: TextStyle(
                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2.5,
              ),
            ),
            const Spacer(),
          ],
        ),
      );
    }

    // Play or stop rotation animation depending on player status
    if (playerState.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!playerState.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }

    final isFavoriteAsync = ref.watch(playerClipFavoriteProvider(clip.id));
    final isFavorite = isFavoriteAsync.value ?? false;

    // Get current album details for cover image resolution — safely nullable
    final albums = ref.watch(albumsProvider).value ?? [];
    Album? album;
    try {
      album = albums.firstWhere((a) => a.id == clip.albumId);
    } catch (_) {
      album = null;
    }

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

          // 3. Spinning Vinyl Record Design with Interactive Gestures
          Center(
            child: GestureDetector(
              onTap: () => _showFullscreenArtwork(context, album, coverColor),
              onDoubleTap: () async {
                await ref.read(clipRepositoryProvider).toggleFavorite(clip.id, !isFavorite);
                ref.invalidate(playerClipFavoriteProvider(clip.id));
                ref.invalidate(recentClipsProvider);
                ref.invalidate(albumsProvider);
              },
              onLongPress: () => _showSongInfoBottomSheet(context, clip, album),
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
                      ),
                      clipBehavior: ui.Clip.antiAlias,
                      child: _buildArtwork(album, coverColor),
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
                  onPressed: () async {
                    await ref.read(clipRepositoryProvider).toggleFavorite(clip.id, !isFavorite);
                    ref.invalidate(playerClipFavoriteProvider(clip.id));
                    ref.invalidate(recentClipsProvider);
                    ref.invalidate(albumsProvider);
                  },
                  icon: Icon(
                    isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: isFavorite ? AppColors.coral : (isDark ? Colors.white70 : AppColors.textSecondary),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 5. Seek Bar / Progress Bar (StreamBuilder for smooth 60fps seek updates)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StreamBuilder<Duration>(
              stream: (audioHandler as ReelTuneAudioHandler).player.positionStream,
              builder: (context, snapshot) {
                final currentPosition = _dragValue != null
                    ? Duration(milliseconds: (_dragValue! * playerState.duration.inMilliseconds).round())
                    : (snapshot.data ?? playerState.position);
                final progress = playerState.duration.inMilliseconds > 0
                    ? currentPosition.inMilliseconds / playerState.duration.inMilliseconds
                    : 0.0;

                return Column(
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
                        value: progress.clamp(0.0, 1.0),
                        onChanged: (value) {
                          setState(() {
                            _dragValue = value;
                          });
                        },
                        onChangeEnd: (value) async {
                          final position = Duration(
                            milliseconds: (value * playerState.duration.inMilliseconds).round(),
                          );
                          await ref.read(playerProvider.notifier).seek(position);
                          setState(() {
                            _dragValue = null;
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(currentPosition),
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
                );
              },
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

  /// Builds the album artwork with proper error handling and fallback
  Widget _buildArtwork(Album? album, Color coverColor) {
    return CachedArtworkImage(
      imagePath: album?.coverImagePath,
      size: 100,
      borderRadius: BorderRadius.circular(50), // Circular center cover art for vinyl record
      fallbackColor: coverColor,
      fallbackIcon: Icons.music_note_rounded,
      fallbackIconSize: 40,
    );
  }

  void _showFullscreenArtwork(BuildContext context, Album? album, Color fallbackColor) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.9),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.zero,
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 3.0,
            child: Center(
              child: Hero(
                tag: 'album_artwork_fullscreen',
                child: CachedArtworkImage(
                  imagePath: album?.coverImagePath,
                  size: MediaQuery.of(context).size.width * 0.9,
                  borderRadius: BorderRadius.circular(24),
                  fallbackColor: fallbackColor,
                  fallbackIcon: Icons.album_rounded,
                  fallbackIconSize: 120,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSongInfoBottomSheet(BuildContext context, Clip clip, Album? album) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Song Information',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
              ),
              const SizedBox(height: 16),
              _infoRow(context, 'Title', clip.title),
              _infoRow(context, 'Artist', clip.artist ?? 'Unknown Artist'),
              _infoRow(context, 'Album', album?.name ?? 'Single Clip'),
              _infoRow(context, 'Duration', clip.formattedDuration),
              _infoRow(context, 'Platform', clip.sourcePlatform?.toUpperCase() ?? 'LOCAL'),
              _infoRow(context, 'File Path', clip.filePath, isPath: true),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, {bool isPath = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.textPrimary,
                fontSize: 13,
              ),
              maxLines: isPath ? 2 : 1,
              overflow: TextOverflow.ellipsis,
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

final playerClipFavoriteProvider = FutureProvider.family<bool, String>((ref, clipId) async {
  final clip = await ref.read(clipRepositoryProvider).getClip(clipId);
  return clip?.isFavorite ?? false;
});

