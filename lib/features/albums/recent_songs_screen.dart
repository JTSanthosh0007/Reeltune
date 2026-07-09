import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/db/clip_repository.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import 'album_providers.dart';
import '../player/player_provider.dart';

class RecentSongsScreen extends ConsumerWidget {
  const RecentSongsScreen({super.key});

  String _formatLastPlayed(int? timestamp) {
    if (timestamp == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = DateTime.now().difference(dt);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays}d ago';
  }

  String _getSourceLabel(String? platform) {
    if (platform == null || platform.isEmpty) return 'Imported';
    switch (platform.toLowerCase()) {
      case 'youtube':
      case 'instagram':
      case 'tiktok':
        return 'Extracted';
      case 'download':
        return 'Downloaded';
      case 'device':
      default:
        return 'Imported';
    }
  }

  Color _getSourceColor(String label) {
    switch (label) {
      case 'Extracted':
        return AppColors.primary;
      case 'Downloaded':
        return AppColors.skyBlue;
      case 'Imported':
      default:
        return AppColors.gold;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albums = ref.watch(albumsProvider).value ?? [];
    final recentClipsAsync = ref.watch(recentClipsProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Sticky App Bar
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_rounded),
                  color: isDark ? Colors.white : AppColors.textPrimary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
                title: Text(
                  'Recently Played',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.history_rounded),
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                    onPressed: () => ref.invalidate(recentClipsProvider),
                  ),
                ],
              ),

              // Songs List
              recentClipsAsync.when(
                data: (clips) {
                  if (clips.isEmpty) {
                    return const SliverFillRemaining(
                      child: Center(
                        child: Text(
                          'No recently played songs.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }

                  return SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final clip = clips[index];
                          
                          // Find album details
                          Album? album;
                          try {
                            album = albums.firstWhere((a) => a.id == clip.albumId);
                          } catch (_) {
                            album = null;
                          }

                          final coverColor = album != null
                              ? AppColors.parseHexColor(album.coverColor)
                              : AppColors.primary;

                          final playerState = ref.watch(playerProvider);
                          final isCurrent = playerState.currentClip?.id == clip.id;
                          final isPlaying = isCurrent && playerState.isPlaying;
                          final isLoading = isCurrent && playerState.isLoading;

                          final sourceLabel = _getSourceLabel(clip.sourcePlatform);
                          final sourceColor = _getSourceColor(sourceLabel);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.darkCard : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isCurrent
                                      ? AppColors.primary
                                      : (isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
                                  width: isCurrent ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Artwork Thumbnail
                                  CachedArtworkImage(
                                    imagePath: album?.coverImagePath,
                                    size: 52,
                                    borderRadius: BorderRadius.circular(12),
                                    fallbackColor: coverColor,
                                    fallbackIcon: Icons.music_note_rounded,
                                    fallbackIconSize: 24,
                                  ),
                                  const SizedBox(width: 14),

                                  // Titles & Source Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          clip.title,
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: isCurrent
                                                    ? AppColors.primary
                                                    : (isDark ? Colors.white : AppColors.textPrimary),
                                              ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            // Source badge
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: sourceColor.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                sourceLabel,
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: sourceColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                clip.artist != null && clip.artist!.isNotEmpty && clip.artist != 'Unknown Artist'
                                                    ? '${clip.artist} • ${clip.formattedDuration}'
                                                    : '${clip.platformIcon} ${clip.formattedDuration}',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                      fontSize: 11,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (clip.lastPlayedAt != null) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            'Played ${_formatLastPlayed(clip.lastPlayedAt)}',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  fontSize: 10,
                                                  color: AppColors.textTertiary,
                                                ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),

                                  // Favorite / Heart button
                                  IconButton(
                                    icon: Icon(
                                      clip.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                      color: clip.isFavorite ? AppColors.coral : AppColors.textTertiary,
                                      size: 20,
                                    ),
                                    onPressed: () {
                                      ref.read(recentClipsProvider.notifier).toggleFavorite(clip.id, !clip.isFavorite);
                                    },
                                  ),

                                  // Inline Play/Pause Action Spinner
                                  GestureDetector(
                                    onTap: () {
                                      if (isCurrent) {
                                        ref.read(playerProvider.notifier).togglePlayPause();
                                      } else {
                                        ref.read(playerProvider.notifier).playQueue(clips, index);
                                      }
                                    },
                                    child: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.gray100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: isLoading
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: AppColors.primary,
                                                ),
                                              )
                                            : Icon(
                                                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                                color: AppColors.primary,
                                                size: 20,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        childCount: clips.length,
                      ),
                    ),
                  );
                },
                loading: () => const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
                error: (error, _) => SliverFillRemaining(
                  child: Center(
                    child: Text('Failed to load recent clips: $error'),
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
