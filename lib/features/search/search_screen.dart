import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/models/playlist.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import '../player/player_provider.dart';
import '../player/mini_player.dart';
import '../player/full_player_screen.dart';
import '../albums/album_providers.dart';
import '../albums/album_detail_screen.dart';
import '../library/PlaylistsProvider.dart';
import '../library/playlist_detail_screen.dart';

// --- Search query provider ---
final searchQueryProvider = StateProvider<String>((ref) => '');

// --- Search clips/songs provider ---
final searchResultsProvider = FutureProvider<List<Clip>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];
  return ref.watch(clipRepositoryProvider).searchClips(query);
});

class SearchScreen extends ConsumerStatefulWidget {
  final bool isTab;

  const SearchScreen({
    super.key,
    this.isTab = false,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final clipsAsync = ref.watch(searchResultsProvider);
    final albumsAsync = ref.watch(searchAlbumsProvider(query));
    final playlistsAsync = ref.watch(searchPlaylistsProvider(query));

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        if (!widget.isTab)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCard : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                const Icon(Icons.search_rounded, color: AppColors.textTertiary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    autofocus: true,
                                    onChanged: _onSearchChanged,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                    decoration: const InputDecoration(
                                      hintText: 'Search songs, albums, playlists...',
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                if (query.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _controller.clear();
                                      ref.read(searchQueryProvider.notifier).state = '';
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 300.ms),

                  // Results
                  Expanded(
                    child: query.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.search_rounded,
                                  color: AppColors.textTertiary,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Search your music library',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 120),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Songs Results
                                clipsAsync.when(
                                  data: (clips) {
                                    if (clips.isEmpty) return const SizedBox();
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                          child: Text(
                                            'Songs',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                                ),
                                          ),
                                        ),
                                        ListView.builder(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          padding: const EdgeInsets.symmetric(horizontal: 16),
                                          itemCount: clips.length,
                                          itemBuilder: (context, index) {
                                            final clip = clips[index];
                                            return _SearchResultTile(
                                              clip: clip,
                                              index: index,
                                              onTap: () {
                                                ref.read(playerProvider.notifier).playQueue(clips, index);
                                              },
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  },
                                  loading: () => const SizedBox(),
                                  error: (_, __) => const SizedBox(),
                                ),

                                // 2. Albums Results
                                albumsAsync.when(
                                  data: (albumsList) {
                                    if (albumsList.isEmpty) return const SizedBox();
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                                          child: Text(
                                            'Albums',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 146,
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            itemCount: albumsList.length,
                                            itemBuilder: (context, index) {
                                              final album = albumsList[index];
                                              final coverColor = AppColors.parseHexColor(album.coverColor);
                                              return GestureDetector(
                                                onTap: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => AlbumDetailScreen(album: album),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  width: 104,
                                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      CachedArtworkImage(
                                                        imagePath: album.coverImagePath,
                                                        size: 96,
                                                        borderRadius: BorderRadius.circular(16),
                                                        fallbackColor: coverColor,
                                                        fallbackIcon: Icons.library_music_rounded,
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        album.name,
                                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                              fontWeight: FontWeight.bold,
                                                              color: isDark ? Colors.white : AppColors.textPrimary,
                                                            ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        '${album.clipCount} song${album.clipCount == 1 ? '' : 's'}',
                                                        style: Theme.of(context).textTheme.bodySmall,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
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
                                  },
                                  loading: () => const SizedBox(),
                                  error: (_, __) => const SizedBox(),
                                ),

                                // 3. Playlists Results
                                playlistsAsync.when(
                                  data: (playlists) {
                                    if (playlists.isEmpty) return const SizedBox();
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                                          child: Text(
                                            'Playlists',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                                ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: 140,
                                          child: ListView.builder(
                                            scrollDirection: Axis.horizontal,
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            itemCount: playlists.length,
                                            itemBuilder: (context, index) {
                                              final playlist = playlists[index];
                                              return GestureDetector(
                                                onTap: () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute(
                                                      builder: (_) => PlaylistDetailScreen(playlist: playlist),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  width: 104,
                                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Container(
                                                        width: 96,
                                                        height: 96,
                                                        decoration: BoxDecoration(
                                                          gradient: LinearGradient(
                                                            colors: [
                                                              AppColors.primary.withValues(alpha: 0.3),
                                                              AppColors.primary.withValues(alpha: 0.1),
                                                            ],
                                                            begin: Alignment.topLeft,
                                                            end: Alignment.bottomRight,
                                                          ),
                                                          borderRadius: BorderRadius.circular(16),
                                                          border: Border.all(
                                                            color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                                                          ),
                                                        ),
                                                        child: const Center(
                                                          child: Icon(
                                                            Icons.playlist_play_rounded,
                                                            color: AppColors.primary,
                                                            size: 36,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        playlist.name,
                                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                              fontWeight: FontWeight.bold,
                                                              color: isDark ? Colors.white : AppColors.textPrimary,
                                                            ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
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
                                  },
                                  loading: () => const SizedBox(),
                                  error: (_, __) => const SizedBox(),
                                ),

                                // 4. Global Loading / Shimmers
                                if (clipsAsync.isLoading || albumsAsync.isLoading || playlistsAsync.isLoading)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24.0),
                                      child: CircularProgressIndicator(color: AppColors.primary),
                                    ),
                                  ),

                                // 5. Empty State
                                if (clipsAsync.value?.isEmpty == true &&
                                    albumsAsync.value?.isEmpty == true &&
                                    playlistsAsync.value?.isEmpty == true)
                                  Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 60),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.music_off_rounded,
                                            color: AppColors.textTertiary,
                                            size: 48,
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No matching songs, albums, or playlists.',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(color: AppColors.textTertiary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),

              // Mini player
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends ConsumerWidget {
  final Clip clip;
  final int index;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.clip,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albums = ref.watch(albumsProvider).value ?? [];

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

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
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
              size: 44,
              borderRadius: BorderRadius.circular(10),
              fallbackColor: coverColor,
              fallbackIcon: Icons.music_note_rounded,
              fallbackIconSize: 22,
            ),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 2),
                  Text(
                    clip.artist != null && clip.artist!.isNotEmpty && clip.artist != 'Unknown Artist'
                        ? '${clip.artist} • ${clip.platformIcon} ${clip.formattedDuration}'
                        : '${clip.platformIcon} ${clip.formattedDuration}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(
              isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
              color: AppColors.primary,
              size: 28,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 30 * (index > 8 ? 8 : index)),
          duration: 250.ms,
        )
        .slideX(begin: 0.02, duration: 250.ms);
  }
}
