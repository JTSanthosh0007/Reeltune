import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/album.dart';
import '../../core/models/clip.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import '../albums/album_providers.dart';
import '../albums/album_detail_screen.dart';
import '../player/player_provider.dart';
import '../player/full_player_screen.dart';
import '../albums/recent_songs_screen.dart';
import '../notifications/notification_center_screen.dart';
import '../share_intent/share_overlay_bridge.dart';

import '../search/search_provider.dart';
import '../search/search_results_view.dart';

class HomeScreen extends ConsumerStatefulWidget {
  final VoidCallback onNavigateToQueue;
  final VoidCallback onNavigateToLibrary;
  final VoidCallback? onMenuPressed;

  const HomeScreen({
    super.key,
    required this.onNavigateToQueue,
    required this.onNavigateToLibrary,
    this.onMenuPressed,
  });

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  bool _hasOverlayPermission = true;
  bool _isSearching = false;
  late final FocusNode _searchFocusNode;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    final granted = await ShareOverlayBridge.checkOverlayPermission();
    if (mounted) {
      setState(() {
        _hasOverlayPermission = granted;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsProvider);
    final recentClipsAsync = ref.watch(recentClipsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.cream,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Premium App Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.menu_rounded),
                    onPressed: widget.onMenuPressed,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                  Text(
                    'ReelTune',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: AppColors.primary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                  ).animate().fadeIn(duration: 400.ms),
                  IconButton(
                    icon: const Icon(Icons.notifications_none_rounded),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const NotificationCenterScreen(),
                        ),
                      );
                    },
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ],
              ),
            ),

            // 2. Greeting Header (only if not actively searching)
            if (!_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getGreeting(),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 26,
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Enjoy your saved sounds',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 300.ms),

            const SizedBox(height: 12),

            // 3. Universal Search Bar
            _buildSearchBar(context, isDark),

            // 4. Overlay Permission Card (only if not searching)
            if (!_hasOverlayPermission && !_isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF14B8A6), Color(0xFF0F766E)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF14B8A6).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.layers_outlined, color: Colors.white, size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Enable Floating Queue Badge',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Allow ReelTune to display a small floating overlay so you can track download queues instantly without leaving Instagram or YouTube.',
                          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () async {
                                await ShareOverlayBridge.requestOverlayPermission();
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF0F766E),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              ),
                              child: const Text('Enable Now', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 10),

            // 5. Body Switcher (Search results or normal home screen items)
            Expanded(
              child: _isSearching
                  ? SearchResultsView(
                      query: _searchController.text,
                      onSearchHistorySelect: (term) {
                        setState(() {
                          _searchController.text = term;
                          _searchController.selection = TextSelection.fromPosition(
                            TextPosition(offset: term.length),
                          );
                        });
                        ref.read(searchProvider.notifier).onQueryChanged(term);
                      },
                    ).animate().fadeIn(duration: 250.ms)
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Your Albums Horizontal Section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Your Albums',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppColors.textPrimary,
                                      ),
                                ),
                                TextButton(
                                  onPressed: widget.onNavigateToLibrary,
                                  child: const Text(
                                    'See All',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          SizedBox(
                            height: 210,
                            child: albumsAsync.when(
                              data: (albums) {
                                if (albums.isEmpty) {
                                  return const Center(
                                    child: Text(
                                      'No albums created yet',
                                      style: TextStyle(color: AppColors.textSecondary),
                                    ),
                                  );
                                }
                                return ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: albums.length,
                                  itemBuilder: (context, index) {
                                    final album = albums[index];
                                    return _HorizontalAlbumCard(
                                      album: album,
                                      index: index,
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AlbumDetailScreen(albumId: album.id),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                              loading: () => const Center(
                                child: CircularProgressIndicator(color: AppColors.primary),
                              ),
                              error: (_, __) => const Center(
                                child: Text('Failed to load albums'),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Recent Clips Section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Recent Clips',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppColors.textPrimary,
                                      ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const RecentSongsScreen(),
                                      ),
                                    );
                                  },
                                  child: const Text(
                                    'See All',
                                    style: TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          recentClipsAsync.when(
                            data: (clips) {
                              if (clips.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                                  child: Center(
                                    child: Text(
                                      'No clips saved yet.\nCopy/Share a link to start saving audio!',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: AppColors.textSecondary),
                                    ),
                                  ),
                                );
                              }

                              final recentClips = clips.take(5).toList();
                              return ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(bottom: 180),
                                itemCount: recentClips.length,
                                itemBuilder: (context, index) {
                                  final clip = recentClips[index];
                                  return _RecentClipListTile(
                                    clip: clip,
                                    onPlay: () {
                                      final playerState = ref.read(playerProvider);
                                      if (playerState.currentClip?.id == clip.id) {
                                        ref.read(playerProvider.notifier).togglePlayPause();
                                      } else {
                                        ref.read(playerProvider.notifier).playQueue(clips, index);
                                      }
                                    },
                                  );
                                },
                              );
                            },
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: CircularProgressIndicator(color: AppColors.primary),
                              ),
                            ),
                            error: (_, __) => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text('Failed to load recent clips'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.gray100,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: _isSearching
              ? AppColors.primary
              : (isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
          width: _isSearching ? 2.0 : 1.0,
        ),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onTap: () {
          if (!_isSearching) {
            setState(() {
              _isSearching = true;
            });
          }
        },
        onChanged: (val) {
          ref.read(searchProvider.notifier).onQueryChanged(val);
          setState(() {}); // refresh trailing icon
        },
        onSubmitted: (val) {
          ref.read(searchProvider.notifier).addToHistory(val);
        },
        style: TextStyle(
          color: isDark ? Colors.white : AppColors.textPrimary,
          fontSize: 16,
        ),
        decoration: InputDecoration(
          hintText: 'Search songs, artists, albums or playlists...',
          hintStyle: TextStyle(
            color: isDark
                ? AppColors.darkSubtitle.withValues(alpha: 0.6)
                : AppColors.textTertiary,
            fontSize: 14,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: AppColors.primary,
          ),
          suffixIcon: _isSearching
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, color: AppColors.textTertiary),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(searchProvider.notifier).onQueryChanged('');
                    if (_searchFocusNode.hasFocus) {
                      _searchFocusNode.unfocus();
                    }
                    setState(() {
                      _isSearching = false;
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}

class _HorizontalAlbumCard extends StatelessWidget {
  final Album album;
  final int index;
  final VoidCallback onTap;

  const _HorizontalAlbumCard({
    required this.album,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final coverColor = AppColors.parseHexColor(
      album.coverColor,
      fallback: AppColors.albumColors[index % AppColors.albumColors.length],
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 140,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Square Cover Art
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: coverColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CachedArtworkImage(
                imagePath: album.coverImagePath,
                size: 140,
                borderRadius: BorderRadius.circular(18),
                fallbackColor: coverColor,
                fallbackIcon: Icons.album_rounded,
                fallbackIconSize: 48,
              ),
            ),
            const SizedBox(height: 8),
            // Title
            Text(
              album.name,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    fontSize: 14,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            // Subtitle
            Text(
              '${album.clipCount} clip${album.clipCount == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                    fontSize: 12,
                  ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 400.ms, delay: Duration(milliseconds: index * 50));
  }
}

class _RecentClipListTile extends ConsumerWidget {
  final Clip clip;
  final VoidCallback onPlay;

  const _RecentClipListTile({
    required this.clip,
    required this.onPlay,
  });

  String _formatLastPlayed(int? timestamp) {
    if (timestamp == null) return '';
    final now = DateTime.now();
    final playedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final difference = now.difference(playedTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

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
    final isLoading = isCurrent && playerState.isLoading;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: GestureDetector(
        onTap: onPlay,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isCurrent ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
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
                            color: isCurrent ? AppColors.primary : (isDark ? Colors.white : AppColors.textPrimary),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      clip.artist != null && clip.artist!.isNotEmpty && clip.artist != 'Unknown Artist'
                          ? '${clip.artist} • ${clip.formattedDuration}'
                          : '${clip.platformIcon} ${clip.formattedDuration}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

              Container(
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
            ],
          ),
        ),
      ),
    );
  }
}

String _getGreeting() {
  final hour = DateTime.now().hour;
  if (hour >= 5 && hour < 12) {
    return 'Good Morning 👋';
  } else if (hour >= 12 && hour < 17) {
    return 'Good Afternoon ☀️';
  } else if (hour >= 17 && hour < 21) {
    return 'Good Evening 🌇';
  } else {
    return 'Good Night 🌙';
  }
}
