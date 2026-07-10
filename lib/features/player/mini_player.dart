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
          height: 78.0, // Fixed premium height
          decoration: BoxDecoration(
            color: AppColors.getAdaptiveSurfaceCard(context).withValues(alpha: 0.98),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
            border: Border(
              top: BorderSide(
                color: AppColors.getAdaptiveSurfaceBorder(context),
                width: 1.2,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, -6),
              ),
            ],
          ),
          child: Column(
            children: [
              // 4dp Smooth Rounded Progress Bar
              RepaintBoundary(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  child: SizedBox(
                    height: 4.0,
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
                          backgroundColor: isDark ? Colors.white10 : AppColors.surfaceBorder,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary,
                          ),
                          minHeight: 4.0,
                        );
                      },
                    ),
                  ),
                ),
              ),

              // Content Row
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Artwork with 12dp rounded corners and 52dp size
                      CachedArtworkImage(
                        imagePath: album?.coverImagePath,
                        size: 52,
                        borderRadius: BorderRadius.circular(12),
                        fallbackColor: coverColor,
                        fallbackIcon: Icons.music_note_rounded,
                        fallbackIconSize: 26,
                      ),
                      const SizedBox(width: 14),

                      // Clip details (truncated on a single line, metadata below)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              playerState.currentClip!.title,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              playerState.currentClip!.artist != null &&
                                      playerState.currentClip!.artist!.isNotEmpty &&
                                      playerState.currentClip!.artist != 'Unknown Artist'
                                  ? playerState.currentClip!.artist!
                                  : '${playerState.currentClip!.platformIcon} Saved Sound',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Play/Pause button
                      IconButton(
                        onPressed: () {
                          ref.read(playerProvider.notifier).togglePlayPause();
                        },
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: playerState.isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : Icon(
                                  playerState.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                  size: 32,
                                  key: ValueKey(playerState.isPlaying),
                                ),
                        ),
                      ),

                      // Close button (Stop & Dismiss)
                      IconButton(
                        onPressed: () {
                          ref.read(playerProvider.notifier).stop();
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white54 : AppColors.textTertiary,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
