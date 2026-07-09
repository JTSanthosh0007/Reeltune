import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import '../albums/album_providers.dart';
import '../player/player_provider.dart';

class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albums = ref.watch(albumsProvider).value ?? [];
    final favoritesAsync = ref.watch(favoriteClipsProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: favoritesAsync.when(
            data: (clips) {
              // Filter clips locally by search query
              final filteredClips = clips.where((clip) {
                if (_searchQuery.isEmpty) return true;
                final query = _searchQuery.toLowerCase();
                return clip.title.toLowerCase().contains(query) ||
                    (clip.artist?.toLowerCase().contains(query) ?? false) ||
                    (clip.albumName?.toLowerCase().contains(query) ?? false) ||
                    (clip.genre?.toLowerCase().contains(query) ?? false);
              }).toList();

              return CustomScrollView(
                slivers: [
                  // Spotify-Style Header
                  SliverAppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    pinned: true,
                    expandedHeight: 220,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [AppColors.primaryDark.withValues(alpha: 0.6), Colors.transparent]
                                : [AppColors.green50, Colors.transparent],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Icon(
                              Icons.favorite_rounded,
                              color: AppColors.coral,
                              size: 56,
                            ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
                            const SizedBox(height: 12),
                            Text(
                              'Liked Songs',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${clips.length} song${clips.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Search Bar and Controls Row
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          // Custom Search Input
                          Container(
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded, color: AppColors.textTertiary, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (val) {
                                      setState(() {
                                        _searchQuery = val;
                                      });
                                    },
                                    style: Theme.of(context).textTheme.bodyMedium,
                                    decoration: InputDecoration(
                                      hintText: 'Search liked songs...',
                                      hintStyle: TextStyle(
                                        color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.6) : AppColors.textTertiary,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                if (_searchQuery.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {
                                        _searchQuery = '';
                                      });
                                    },
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Play and Shuffle row
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: filteredClips.isEmpty
                                      ? null
                                      : () {
                                          ref.read(playerProvider.notifier).playQueue(filteredClips, 0);
                                        },
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: const Text('Play'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: filteredClips.isEmpty
                                      ? null
                                      : () {
                                          final list = List<Clip>.from(filteredClips)..shuffle();
                                          ref.read(playerProvider.notifier).playQueue(list, 0);
                                        },
                                  icon: const Icon(Icons.shuffle_rounded),
                                  label: const Text('Shuffle'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(color: AppColors.primary),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Favorites List
                  if (filteredClips.isEmpty)
                    SliverFillRemaining(
                      child: Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No results match your search.'
                              : 'No liked songs yet.',
                          style: const TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final clip = filteredClips[index];

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

                                    // Details
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

                                    // Like Toggle Button
                                    IconButton(
                                      icon: const Icon(
                                        Icons.favorite_rounded,
                                        color: AppColors.coral,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        ref.read(favoriteClipsProvider.notifier).toggleFavorite(clip.id, false);
                                      },
                                    ),

                                    // Play Action Button
                                    GestureDetector(
                                      onTap: () {
                                        if (isCurrent) {
                                          ref.read(playerProvider.notifier).togglePlayPause();
                                        } else {
                                          ref.read(playerProvider.notifier).playQueue(filteredClips, index);
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
                          childCount: filteredClips.length,
                        ),
                      ),
                    ),
                ],
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (err, _) => Center(
              child: Text('Error: $err'),
            ),
          ),
        ),
      ),
    );
  }
}
