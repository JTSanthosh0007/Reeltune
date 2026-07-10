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
      begin: const Offset(0, 1),
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

    // Play the slide-in animation only once when the player first appears
    if (!_hasAnimated) {
      _hasAnimated = true;
      _slideController.forward(from: 0);
    }

    final coverColor = album != null
        ? AppColors.parseHexColor(album.coverColor)
        : AppColors.primary;

    return SlideTransition(
      position: _slideAnimation,
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(FullPlayerRoute());
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null && details.primaryVelocity! < -200) {
            // Swipe Up -> Open Full Player
            Navigator.of(context).push(FullPlayerRoute());
          } else if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
            // Swipe Down -> Dismiss Mini Player (Stop playback & clear state)
            ref.read(playerProvider.notifier).stop();
          }
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.getAdaptiveSurfaceCard(context).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.getAdaptiveSurfaceBorder(context)),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress bar wrapped in RepaintBoundary to isolate repaints
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
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
                        backgroundColor: AppColors.surfaceBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary,
                        ),
                        minHeight: 2.5,
                      );
                    },
                  ),
                ),
              ),

              // Controls
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    // Artwork
                    CachedArtworkImage(
                      imagePath: album?.coverImagePath,
                      size: 40,
                      borderRadius: BorderRadius.circular(8),
                      fallbackColor: coverColor,
                      fallbackIcon: Icons.music_note_rounded,
                      fallbackIconSize: 20,
                    ),
                    const SizedBox(width: 12),
                    // Clip info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            playerState.currentClip!.title,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            playerState.currentClip!.artist != null && playerState.currentClip!.artist!.isNotEmpty && playerState.currentClip!.artist != 'Unknown Artist'
                                ? playerState.currentClip!.artist!
                                : '${playerState.currentClip!.platformIcon} Saved Sound',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause
                    IconButton(
                      onPressed: () {
                        ref.read(playerProvider.notifier).togglePlayPause();
                      },
                      icon: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: playerState.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : Icon(
                                playerState.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                color: AppColors.textPrimary,
                                size: 28,
                                key: ValueKey(playerState.isPlaying),
                              ),
                      ),
                    ),

                    // Close
                    IconButton(
                      onPressed: () {
                        ref.read(playerProvider.notifier).stop();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
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
}
