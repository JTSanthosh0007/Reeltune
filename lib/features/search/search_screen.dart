import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/models/playlist.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import '../player/player_provider.dart';
import '../player/mini_player.dart';
import '../albums/album_providers.dart';
import '../albums/album_detail_screen.dart';
import '../library/PlaylistsProvider.dart';
import '../library/playlist_detail_screen.dart';
import 'search_provider.dart';
import '../queue/queue_provider.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(searchProvider.notifier).onQueryChanged(query);
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final albumsAsync = ref.watch(searchAlbumsProvider(searchState.query));
    final playlistsAsync = ref.watch(searchPlaylistsProvider(searchState.query));

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
                                      hintText: 'Search songs, artists, albums...',
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                                if (searchState.query.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 18),
                                    onPressed: () {
                                      _controller.clear();
                                      ref.read(searchProvider.notifier).onQueryChanged('');
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
                    child: searchState.query.isEmpty
                        ? SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (searchState.history.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Recent Searches',
                                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : AppColors.textPrimary,
                                              ),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            ref.read(searchProvider.notifier).clearAllHistory();
                                          },
                                          child: const Text('Clear All'),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: searchState.history.length > 5 ? 5 : searchState.history.length,
                                    itemBuilder: (context, index) {
                                      final historyQuery = searchState.history[index];
                                      return ListTile(
                                        leading: const Icon(Icons.history_rounded, color: AppColors.textTertiary),
                                        title: Text(historyQuery),
                                        trailing: IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 18),
                                          onPressed: () {
                                            ref.read(searchProvider.notifier).removeFromHistory(historyQuery);
                                          },
                                        ),
                                        onTap: () {
                                          _controller.text = historyQuery;
                                          ref.read(searchProvider.notifier).onQueryChanged(historyQuery);
                                        },
                                      );
                                    },
                                  ),
                                ],
                                // Trending list
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
                                  child: Text(
                                    'Trending Searches',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : AppColors.textPrimary,
                                        ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      'Coldplay',
                                      'Taylor Swift',
                                      'Post Malone',
                                      'Adele',
                                      'Drake',
                                      'The Weeknd',
                                      'Billie Eilish'
                                    ].map((tag) {
                                      return ActionChip(
                                        label: Text(tag),
                                        onPressed: () {
                                          _controller.text = tag;
                                          ref.read(searchProvider.notifier).onQueryChanged(tag);
                                          ref.read(searchProvider.notifier).addToHistory(tag);
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ),
                                const SizedBox(height: 120),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 120),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 1. Local Songs
                                if (searchState.songs.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                    child: Text(
                                      'Downloaded Songs',
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
                                    itemCount: searchState.songs.length,
                                    itemBuilder: (context, index) {
                                      final clip = searchState.songs[index];
                                      return _SearchResultTile(
                                        clip: clip,
                                        index: index,
                                        onTap: () {
                                          ref.read(searchProvider.notifier).addToHistory(searchState.query);
                                          ref.read(playerProvider.notifier).playQueue(searchState.songs, index);
                                        },
                                      );
                                    },
                                  ),
                                ],

                                // 2. Online Search Results
                                if (searchState.onlineSongs.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                    child: Text(
                                      'Online Songs',
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
                                    itemCount: searchState.onlineSongs.length,
                                    itemBuilder: (context, index) {
                                      final clip = searchState.onlineSongs[index];
                                      return _SearchResultTile(
                                        clip: clip,
                                        index: index,
                                        isOnline: true,
                                        onTap: () {
                                          ref.read(searchProvider.notifier).addToHistory(searchState.query);
                                          ref.read(playerProvider.notifier).playQueue(searchState.onlineSongs, index);
                                        },
                                      );
                                    },
                                  ),
                                ],

                                // 2.5 JioSaavn Online Songs Results
                                if (searchState.saavnSongs.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                    child: Text(
                                      'JioSaavn Songs',
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
                                    itemCount: searchState.saavnSongs.length,
                                    itemBuilder: (context, index) {
                                      final clip = searchState.saavnSongs[index];
                                      return _SearchResultTile(
                                        clip: clip,
                                        index: index,
                                        isOnline: true,
                                        onTap: () {
                                          ref.read(searchProvider.notifier).addToHistory(searchState.query);
                                          ref.read(playerProvider.notifier).playQueue(searchState.saavnSongs, index);
                                        },
                                      );
                                    },
                                  ),
                                ],

                                // 2.7 Apple Music Online Songs Results
                                if (searchState.appleSongs.isNotEmpty) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                                    child: Text(
                                      'Apple Music Songs',
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
                                    itemCount: searchState.appleSongs.length,
                                    itemBuilder: (context, index) {
                                      final clip = searchState.appleSongs[index];
                                      return _SearchResultTile(
                                        clip: clip,
                                        index: index,
                                        isOnline: true,
                                        onTap: () {
                                          ref.read(searchProvider.notifier).addToHistory(searchState.query);
                                          ref.read(playerProvider.notifier).playQueue(searchState.appleSongs, index);
                                        },
                                      );
                                    },
                                  ),
                                ],

                                // 3. Albums Results
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
                                                      builder: (_) => AlbumDetailScreen(albumId: album.id),
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

                                // 4. Playlists Results
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

                                // 5. Global Loading / Shimmers
                                if (searchState.isLoading || albumsAsync.isLoading || playlistsAsync.isLoading)
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(24.0),
                                      child: CircularProgressIndicator(color: AppColors.primary),
                                    ),
                                  ),

                                // 6. Empty State
                                if (searchState.songs.isEmpty &&
                                    searchState.onlineSongs.isEmpty &&
                                    searchState.saavnSongs.isEmpty &&
                                    searchState.appleSongs.isEmpty &&
                                    albumsAsync.value?.isEmpty == true &&
                                    playlistsAsync.value?.isEmpty == true &&
                                    !searchState.isLoading)
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
  final bool isOnline;

  const _SearchResultTile({
    required this.clip,
    required this.index,
    required this.onTap,
    this.isOnline = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final albums = ref.watch(albumsProvider).value ?? [];

    Album? album;
    if (!isOnline) {
      try {
        album = albums.firstWhere((a) => a.id == clip.albumId);
      } catch (_) {
        album = null;
      }
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
            isOnline
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      (clip.sourcePlatform == 'jiosaavn' || clip.sourcePlatform == 'applemusic')
                          ? (clip.genre ?? '')
                          : 'https://i.ytimg.com/vi/${clip.id}/hqdefault.jpg',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (context, _, __) => Container(
                        width: 44,
                        height: 44,
                        color: coverColor,
                        child: const Icon(Icons.music_note_rounded, size: 22, color: Colors.white),
                      ),
                    ),
                  )
                : CachedArtworkImage(
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
                        ? '${clip.artist} • ${isOnline ? (clip.sourcePlatform == 'jiosaavn' ? "🌐 JioSaavn" : (clip.sourcePlatform == 'applemusic' ? "🌐 Apple Music" : "🌐 YT Music")) : "💾 Offline"} • ${clip.formattedDuration}'
                        : '${isOnline ? (clip.sourcePlatform == 'jiosaavn' ? "🌐 JioSaavn" : (clip.sourcePlatform == 'applemusic' ? "🌐 Apple Music" : "🌐 YT Music")) : "💾 Offline"} • ${clip.formattedDuration}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isOnline) ...[
              IconButton(
                icon: const Icon(Icons.download_for_offline_rounded, color: AppColors.primary),
                onPressed: () {
                  final downloadUrl = (clip.sourcePlatform == 'jiosaavn' || clip.sourcePlatform == 'applemusic')
                      ? 'ytsearch:${clip.title} ${clip.artist ?? ""}'
                      : (clip.sourceUrl ?? '');
                  ref.read(queueProvider.notifier).addToQueue(
                        url: downloadUrl,
                        platform: 'youtube',
                        title: clip.title,
                        artist: clip.artist,
                      );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Added "${clip.title}" to downloads queue!'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
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
