import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/album.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import '../albums/album_providers.dart';
import 'player_provider.dart';
import 'full_player_screen.dart';
import '../../main.dart'; // import global audioHandler
import 'audio_handler.dart'; // import ReelTuneAudioHandler

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;
  bool _hasAnimated = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playerState = ref.watch(playerProvider);
    final albums = ref.watch(albumsProvider).value ?? [];
    Album? album;
    if (playerState.currentClip != null) {
      try {
        album = albums.firstWhere((a) => a.id == playerState.currentClip!.albumId);
      } catch (_) {}
    }

    if (!playerState.hasClip) {
      _hasAnimated = false;
      return const SizedBox.shrink();
    }

    if (!_hasAnimated) {
      _hasAnimated = true;
      _slideController.forward(from: 0);
    }

    final coverColor = album != null
        ? AppColors.parseHexColor(album.coverColor)
        : AppColors.primary;

    return SlideTransition(
      position: _slideAnimation,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Dismissible(
          key: const ValueKey('reeltune_mini_player_dismiss'),
          direction: DismissDirection.down,
          onDismissed: (direction) {
            ref.read(playerProvider.notifier).stop();
          },
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).push(FullPlayerRoute());
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  height: 74.0, // Floating card height
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF171717) : Colors.white)
                        .withValues(alpha: isDark ? 0.75 : 0.85),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: isDark ? 0.08 : 0.05),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Content Row
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                          child: Row(
                            children: [
                              // Artwork with 16dp rounded corners and 56x56 size
                              CachedArtworkImage(
                                imagePath: album?.coverImagePath,
                                size: 56,
                                borderRadius: BorderRadius.circular(16),
                                fallbackColor: coverColor,
                                fallbackIcon: Icons.music_note_rounded,
                                fallbackIconSize: 26,
                              ),
                              const SizedBox(width: 12),

                              // Clip details (truncated on a single line, metadata below)
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      playerState.currentClip!.title,
                                      style: TextStyle(
                                        color: isDark ? Colors.white : AppColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      playerState.currentClip!.artist != null &&
                                              playerState.currentClip!.artist!.isNotEmpty &&
                                              playerState.currentClip!.artist != 'Unknown Artist'
                                          ? playerState.currentClip!.artist!
                                          : '${playerState.currentClip!.platformIcon} Saved Sound',
                                      style: TextStyle(
                                        color: isDark ? const Color(0xFFA0A0A0) : AppColors.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Animated Waveform Indicator
                              AnimatedWaveform(isPlaying: playerState.isPlaying),
                              const SizedBox(width: 4),

                              // Play/Pause button
                              IconButton(
                                onPressed: () {
                                  ref.read(playerProvider.notifier).togglePlayPause();
                                },
                                icon: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: playerState.isLoading
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.0,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : Icon(
                                          playerState.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: isDark ? Colors.white : AppColors.textPrimary,
                                          size: 28,
                                          key: ValueKey(playerState.isPlaying),
                                        ),
                                ),
                              ),

                              // Close button
                              IconButton(
                                onPressed: () {
                                  ref.read(playerProvider.notifier).stop();
                                },
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: isDark ? Colors.white54 : AppColors.textTertiary,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Progress Bar at the bottom edge
                      RepaintBoundary(
                        child: SizedBox(
                          height: 3.0,
                          child: StreamBuilder<Duration>(
                            stream: (audioHandler as ReelTuneAudioHandler).player.positionStream,
                            builder: (context, snapshot) {
                              final position = snapshot.data ?? Duration.zero;
                              final duration = playerState.duration;
                              final progress = duration.inMilliseconds > 0
                                  ? position.inMilliseconds / duration.inMilliseconds
                                  : 0.0;
                              return LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                backgroundColor: isDark ? Colors.white12 : AppColors.surfaceBorder,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  AppColors.primary,
                                ),
                                minHeight: 3.0,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AnimatedWaveform extends StatefulWidget {
  final bool isPlaying;
  const AnimatedWaveform({super.key, required this.isPlaying});

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(4, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            double value = 0.2;
            if (widget.isPlaying) {
              final radians = (_controller.value * 2 * math.pi) + (index * 0.8);
              value = 0.3 + (0.6 * (0.5 + 0.5 * math.sin(radians)));
            }
            return Container(
              width: 3.0,
              height: 16.0 * value,
              margin: const EdgeInsets.symmetric(horizontal: 1.0),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          },
        );
      }),
    );
  }
}
