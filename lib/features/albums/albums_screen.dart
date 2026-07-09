import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/album.dart';
import '../settings/settings_screen.dart';
import '../search/search_screen.dart';
import 'album_providers.dart';
import 'album_detail_screen.dart';
import 'widgets/album_card.dart';
import 'widgets/create_album_dialog.dart';
import 'package:flutter/services.dart';
import '../../core/network/extraction_service.dart';
import '../share_intent/share_intent_provider.dart';
import '../share_intent/widgets/extraction_bottom_sheet.dart';
import '../../core/ads/NativeAdWidget.dart';
import '../../core/ads/InterstitialService.dart';
import '../library/PlaylistsProvider.dart';
import '../library/playlist_detail_screen.dart';
import '../library/favorites_screen.dart';
final libraryTabProvider = StateProvider<int>((ref) => 0); // 0 = Albums, 1 = Playlists

class AlbumsScreen extends ConsumerWidget {
  final bool isLibrary;

  const AlbumsScreen({
    super.key,
    this.isLibrary = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdFree = ref.watch(adFreeProvider);
    final selectedTab = ref.watch(libraryTabProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: albumsAsync.when(
            data: (albums) {
              return CustomScrollView(
                slivers: [
                  if (!isLibrary) ...[
                    // App bar
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Row(
                          children: [
                            // Animated logo
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.asset(
                                'assets/images/logo.jpg',
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    gradient: AppColors.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ).animate().scale(
                                  duration: 600.ms,
                                  curve: Curves.elasticOut,
                                ),
                            const SizedBox(width: 12),
                            Text(
                              'ReelTune',
                              style: Theme.of(context).textTheme.displayMedium,
                            ).animate().fadeIn(duration: 400.ms).slideX(
                                  begin: -0.1,
                                  duration: 400.ms,
                                ),
                            const Spacer(),
                            // Search button
                            _ActionButton(
                              icon: Icons.search_rounded,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SearchScreen(),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            // Settings button
                            _ActionButton(
                              icon: Icons.settings_rounded,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Subtitle
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        child: Text(
                          'Your audio library',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).animate().fadeIn(delay: 200.ms, duration: 400.ms),
                      ),
                    ),

                    const SliverToBoxAdapter(
                      child: _PasteLinkCard(),
                    ),
                  ] else ...[
                    // Library Tab Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                        child: Text(
                          'Your Library',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          children: [
                            _buildTabItem(context, ref, title: 'Albums', index: 0, isSelected: selectedTab == 0),
                            const SizedBox(width: 12),
                            _buildTabItem(context, ref, title: 'Playlists', index: 1, isSelected: selectedTab == 1),
                            const SizedBox(width: 12),
                            _buildTabItem(context, ref, title: 'Favorites', index: 2, isSelected: false),
                          ],
                        ),
                      ),
                    ),
                  ],

                  if (selectedTab == 0) ...[
                    if (albums.isEmpty)
                      SliverFillRemaining(
                        child: _EmptyState(),
                      )
                    else
                      ..._buildAlbumSlivers(context, albums, isAdFree),
                  ] else ...[
                    ..._buildPlaylistSlivers(context, ref, isDark),
                  ],

                  // Bottom padding for FAB
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 100),
                  ),
                ],
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load albums',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => ref.read(albumsProvider.notifier).refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (selectedTab == 0) {
            _showCreateAlbumDialog(context, ref);
          } else {
            _showCreatePlaylistDialog(context, ref);
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(selectedTab == 0 ? 'New Album' : 'New Playlist'),
      )
          .animate()
          .scale(delay: 500.ms, duration: 400.ms, curve: Curves.elasticOut),
    );
  }

  List<Widget> _buildAlbumSlivers(BuildContext context, List<Album> albums, bool isAdFree) {
    final List<Widget> slivers = [];
    final int adInterval = 8;
    
    for (int i = 0; i < albums.length; i += adInterval) {
      final end = (i + adInterval < albums.length) ? i + adInterval : albums.length;
      final chunk = albums.sublist(i, end);
      
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final album = chunk[index];
                return AlbumCard(
                  album: album,
                  index: i + index,
                  onTap: () => _navigateToAlbum(context, album),
                );
              },
              childCount: chunk.length,
            ),
          ),
        ),
      );
      
      if (end < albums.length && !isAdFree) {
        slivers.add(
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: NativeAdWidget(),
            ),
          ),
        );
      }
    }
    return slivers;
  }

  void _navigateToAlbum(BuildContext context, Album album) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlbumDetailScreen(albumId: album.id),
      ),
    );
  }

  void _showCreateAlbumDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => const CreateAlbumDialog(),
    );
  }

  Widget _buildTabItem(BuildContext context, WidgetRef ref, {required String title, required int index, required bool isSelected}) {
    return GestureDetector(
      onTap: () {
        if (index == 2) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const FavoritesScreen(),
            ),
          );
        } else {
          ref.read(libraryTabProvider.notifier).state = index;
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.primary 
              : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkCard : AppColors.gray100),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected 
                ? AppColors.primary 
                : (Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : AppColors.surfaceBorder),
          ),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPlaylistSlivers(BuildContext context, WidgetRef ref, bool isDark) {
    final playlistsAsync = ref.watch(playlistsProvider);

    return [
      playlistsAsync.when(
        data: (playlists) {
          if (playlists.isEmpty) {
            return const SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: Text(
                    'No playlists created yet.\nCreate a playlist by tapping "New Playlist" below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ),
            );
          }
          return SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final playlist = playlists[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.gray100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.playlist_play_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      title: Text(
                        playlist.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      subtitle: Consumer(
                        builder: (context, ref, _) {
                          final countAsync = ref.watch(playlistClipsProvider(playlist.id));
                          return countAsync.when(
                            data: (clips) => Text('${clips.length} ${clips.length == 1 ? 'song' : 'songs'}', style: Theme.of(context).textTheme.bodySmall),
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                          );
                        },
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailScreen(playlist: playlist),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
              childCount: playlists.length,
            ),
          );
        },
        loading: () => const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
        error: (err, _) => SliverFillRemaining(
          child: Center(child: Text('Error: $err')),
        ),
      )
    ];
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Playlist name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                await ref.read(playlistsProvider.notifier).createPlaylist(name);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.gray100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
          ),
        ),
        child: Icon(
          icon,
          color: isDark ? Colors.white70 : AppColors.textSecondary,
          size: 20,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.library_music_rounded,
                color: Colors.white,
                size: 48,
              ),
            )
                .animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                )
                .scale(
                  begin: const Offset(1, 1),
                  end: const Offset(1.05, 1.05),
                  duration: 2000.ms,
                  curve: Curves.easeInOut,
                ),
            const SizedBox(height: 24),
            Text(
              'No albums yet',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first album and start saving\naudio from your favorite reels!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.green50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.primary.withValues(alpha: 0.3)
                      : AppColors.green200,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.share_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Share a reel → ReelTune saves the audio',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 600.ms, duration: 500.ms),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 500.ms);
  }
}

class _PasteLinkCard extends ConsumerStatefulWidget {
  const _PasteLinkCard();

  @override
  ConsumerState<_PasteLinkCard> createState() => _PasteLinkCardState();
}

class _PasteLinkCardState extends ConsumerState<_PasteLinkCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _controller.text = data!.text!;
      });
    }
  }

  void _handleAnalyze() {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a link first')),
      );
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL (starting with http/https)')),
      );
      return;
    }

    _controller.clear();
    FocusScope.of(context).unfocus();

    final platform = ExtractionService.detectPlatform(url);
    ref.read(extractionFlowProvider.notifier).startExtraction(
          url: url,
          platform: platform,
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExtractionBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.getAdaptiveSurfaceCard(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.getAdaptiveSurfaceBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Paste Reel Link',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Paste Instagram, YouTube, TikTok or FB link...',
                    prefixIcon: const Icon(Icons.link_rounded, color: AppColors.primary),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste_rounded, color: AppColors.primary),
                      onPressed: _pasteFromClipboard,
                      tooltip: 'Paste from clipboard',
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _handleAnalyze,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.analytics_outlined),
                  SizedBox(width: 8),
                  Text('Analyze Link', style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
