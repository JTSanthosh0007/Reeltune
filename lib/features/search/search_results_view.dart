import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/models/playlist.dart';
import '../../core/models/queue_item.dart';
import '../../shared/widgets/cached_artwork_image.dart';

import '../albums/album_providers.dart';
import '../albums/album_detail_screen.dart';
import '../library/PlaylistsProvider.dart';
import '../library/playlist_detail_screen.dart';
import '../player/player_provider.dart';
import 'search_provider.dart';

class SearchResultsView extends ConsumerWidget {
  final String query;
  final Function(String) onSearchHistorySelect;

  const SearchResultsView({
    super.key,
    required this.query,
    required this.onSearchHistorySelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchState = ref.watch(searchProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (query.trim().isEmpty) {
      return _buildHistoryView(context, ref, searchState, isDark);
    }

    if (searchState.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final hasSongs = searchState.songs.isNotEmpty;
    final hasAlbums = searchState.albums.isNotEmpty;
    final hasPlaylists = searchState.playlists.isNotEmpty;
    final hasArtists = searchState.artists.isNotEmpty;
    final hasQueue = searchState.queue.isNotEmpty;

    if (!hasSongs && !hasAlbums && !hasPlaylists && !hasArtists && !hasQueue) {
      return _buildNoResultsView(context, isDark);
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        if (hasQueue) _buildQueueSection(context, ref, searchState.queue, isDark),
        if (hasSongs) _buildSongsSection(context, ref, searchState.songs, isDark),
        if (hasAlbums) _buildAlbumsSection(context, ref, searchState.albums, isDark),
        if (hasPlaylists) _buildPlaylistsSection(context, ref, searchState.playlists, isDark),
        if (hasArtists) _buildArtistsSection(context, ref, searchState.artists, isDark),
      ],
    );
  }

  Widget _buildHistoryView(
    BuildContext context,
    WidgetRef ref,
    SearchState state,
    bool isDark,
  ) {
    if (state.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_rounded,
              size: 64,
              color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.3) : AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            Text(
              'Search for your favorite tracks',
              style: TextStyle(
                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Searches',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(searchProvider.notifier).clearAllHistory();
                },
                child: const Text(
                  'Clear All',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            physics: const BouncingScrollPhysics(),
            itemCount: state.history.length,
            itemBuilder: (context, index) {
              final item = state.history[index];
              return ListTile(
                leading: Icon(
                  Icons.history_rounded,
                  color: isDark ? AppColors.darkSubtitle : AppColors.textTertiary,
                ),
                title: Text(
                  item,
                  style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary),
                ),
                trailing: IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: isDark ? AppColors.darkSubtitle : AppColors.textTertiary,
                  ),
                  onPressed: () {
                    ref.read(searchProvider.notifier).removeFromHistory(item);
                  },
                ),
                onTap: () {
                  onSearchHistorySelect(item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNoResultsView(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.3) : AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No matching songs found.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try checking the spelling or searching for a different song name, artist, or album.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQueueSection(BuildContext context, WidgetRef ref, List<QueueItem> items, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Downloading / Queue', isDark),
        ...items.map((item) {
          return ListTile(
            leading: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.downloading_rounded, color: AppColors.primary),
                ),
              ],
            ),
            title: Text(
              item.title ?? 'Queue item',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
            ),
            subtitle: Text(
              '${item.artist} • ${item.status.toUpperCase()} (${(item.progress * 100).toStringAsFixed(0)}%)',
              style: const TextStyle(fontSize: 12),
            ),
          );
        }),
        const Divider(height: 24, indent: 20, endIndent: 20),
      ],
    );
  }

  Widget _buildSongsSection(BuildContext context, WidgetRef ref, List<Clip> songs, bool isDark) {
    final recentClips = ref.watch(recentClipsProvider).value ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Songs', isDark),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: songs.length,
          itemBuilder: (context, index) {
            final song = songs[index];
            final albums = ref.watch(albumsProvider).value ?? [];
            Album? album;
            try {
              album = albums.firstWhere((a) => a.id == song.albumId);
            } catch (_) {}

            final coverColor = album != null
                ? AppColors.parseHexColor(album.coverColor)
                : AppColors.primary;

            final playerState = ref.watch(playerProvider);
            final isCurrent = playerState.currentClip?.id == song.id;
            final isPlaying = isCurrent && playerState.isPlaying;

            return ListTile(
              leading: CachedArtworkImage(
                imagePath: album?.coverImagePath,
                size: 48,
                borderRadius: BorderRadius.circular(8),
                fallbackColor: coverColor,
                fallbackIcon: Icons.music_note_rounded,
                fallbackIconSize: 22,
              ),
              title: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrent ? AppColors.primary : (isDark ? Colors.white : AppColors.textPrimary),
                ),
              ),
              subtitle: Text(
                '${song.artist ?? "ReelTune"} • ${song.formattedDuration}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: song.isFavorite ? AppColors.coral : AppColors.textTertiary,
                      size: 20,
                    ),
                    onPressed: () {
                      ref.read(recentClipsProvider.notifier).toggleFavorite(song.id, !song.isFavorite);
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                      color: AppColors.primary,
                      size: 32,
                    ),
                    onPressed: () {
                      ref.read(searchProvider.notifier).addToHistory(query);
                      if (isCurrent) {
                        ref.read(playerProvider.notifier).togglePlayPause();
                      } else {
                        ref.read(playerProvider.notifier).playQueue(songs, index);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
        const Divider(height: 24, indent: 20, endIndent: 20),
      ],
    );
  }

  Widget _buildAlbumsSection(BuildContext context, WidgetRef ref, List<Album> albums, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Albums', isDark),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length,
            itemBuilder: (context, index) {
              final album = albums[index];
              final coverColor = AppColors.parseHexColor(
                album.coverColor,
                fallback: AppColors.albumColors[index % AppColors.albumColors.length],
              );

              return GestureDetector(
                onTap: () {
                  ref.read(searchProvider.notifier).addToHistory(query);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailScreen(albumId: album.id),
                    ),
                  );
                },
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedArtworkImage(
                        imagePath: album.coverImagePath,
                        size: 110,
                        borderRadius: BorderRadius.circular(12),
                        fallbackColor: coverColor,
                        fallbackIcon: Icons.album_rounded,
                        fallbackIconSize: 36,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        '${album.clipCount} track${album.clipCount == 1 ? "" : "s"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 24, indent: 20, endIndent: 20),
      ],
    );
  }

  Widget _buildPlaylistsSection(BuildContext context, WidgetRef ref, List<Playlist> playlists, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Playlists', isDark),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final playlist = playlists[index];

              return GestureDetector(
                onTap: () {
                  ref.read(searchProvider.notifier).addToHistory(query);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PlaylistDetailScreen(playlistId: playlist.id),
                    ),
                  );
                },
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CachedArtworkImage(
                        imagePath: playlist.coverImagePath,
                        size: 110,
                        borderRadius: BorderRadius.circular(12),
                        fallbackColor: AppColors.primary,
                        fallbackIcon: Icons.playlist_play_rounded,
                        fallbackIconSize: 40,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        playlist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        'Playlist',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 24, indent: 20, endIndent: 20),
      ],
    );
  }

  Widget _buildArtistsSection(BuildContext context, WidgetRef ref, List<String> artists, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, 'Artists', isDark),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              final artist = artists[index];
              final char = artist.isNotEmpty ? artist[0].toUpperCase() : '?';

              return GestureDetector(
                onTap: () {
                  ref.read(searchProvider.notifier).addToHistory(query);
                  // Quick search filter action
                  onSearchHistorySelect(artist);
                },
                child: Container(
                  width: 90,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: AppColors.albumColors[index % AppColors.albumColors.length],
                        child: Text(
                          char,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
            ),
      ),
    );
  }
}
