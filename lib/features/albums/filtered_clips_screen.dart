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
import '../player/full_player_screen.dart';

final filteredClipsProvider = FutureProvider.family<List<Clip>, String>((ref, filter) async {
  // Re-fetch when albums or recent clips change (reactive updates)
  ref.watch(albumsProvider);
  ref.watch(recentClipsProvider);

  final repo = ref.watch(clipRepositoryProvider);
  final allClips = await repo.getAllClips();

  switch (filter) {
    case 'imported':
      return allClips.where((c) => c.sourcePlatform == 'local').toList();
    case 'downloaded':
      return allClips.where((c) => c.sourcePlatform != 'local').toList();
    case 'recently_added':
      return allClips;
    case 'most_played':
      final played = allClips.where((c) => c.lastPlayedAt != null).toList();
      return played.isNotEmpty ? played : allClips;
    case 'history':
      final historyList = allClips.where((c) => c.lastPlayedAt != null).toList();
      historyList.sort((a, b) => (b.lastPlayedAt ?? 0).compareTo(a.lastPlayedAt ?? 0));
      return historyList;
    default:
      return allClips;
  }
});

class FilteredClipsScreen extends ConsumerWidget {
  final String title;
  final String filter;

  const FilteredClipsScreen({
    super.key,
    required this.title,
    required this.filter,
  });

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
    final clipsAsync = ref.watch(filteredClipsProvider(filter));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
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
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    color: isDark ? Colors.white70 : AppColors.textSecondary,
                    onPressed: () => ref.invalidate(filteredClipsProvider(filter)),
                  ),
                ],
              ),
              clipsAsync.when(
                data: (clips) {
                  if (clips.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.music_note_rounded,
                              color: AppColors.textTertiary,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No songs found in this category.',
                              style: TextStyle(
                                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                              ),
                            ),
                          ],
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
                            child: GestureDetector(
                              onTap: () {
                                if (!isCurrent) {
                                  ref.read(playerProvider.notifier).playQueue(clips, index);
                                }
                                Navigator.of(context).push(FullPlayerRoute());
                              },
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
                                    CachedArtworkImage(
                                      imagePath: album?.coverImagePath,
                                      size: 52,
                                      borderRadius: BorderRadius.circular(12),
                                      fallbackColor: coverColor,
                                      fallbackIcon: Icons.music_note_rounded,
                                      fallbackIconSize: 24,
                                    ),
                                    const SizedBox(width: 14),
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
                                      ],
                                    ),
                                  ),
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
                    child: Text('Error: $error'),
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
