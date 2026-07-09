import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/playlist.dart';
import '../../core/models/clip.dart';
import '../player/player_provider.dart';
import '../player/mini_player.dart';
import '../player/full_player_screen.dart';
import '../albums/widgets/clip_list_tile.dart';
import 'PlaylistsProvider.dart';

class PlaylistDetailScreen extends ConsumerWidget {
  final Playlist playlist;

  const PlaylistDetailScreen({super.key, required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clipsAsync = ref.watch(playlistClipsProvider(playlist.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              clipsAsync.when(
                data: (clips) {
                  return CustomScrollView(
                    slivers: [
                      // Back Button & Playlist Info Header
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_rounded),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Playlist cover placeholder
                                  Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      gradient: AppColors.primaryGradient,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withValues(alpha: 0.2),
                                          blurRadius: 15,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.playlist_play_rounded,
                                      color: Colors.white,
                                      size: 52,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'PLAYLIST',
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                                color: AppColors.primary,
                                                letterSpacing: 1.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          playlist.name,
                                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : AppColors.textPrimary,
                                              ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${clips.length} ${clips.length == 1 ? 'song' : 'songs'}',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  // More menu
                                  IconButton(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onPressed: () => _showPlaylistMenu(context, ref),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // Play / Shuffle Buttons
                              if (clips.isNotEmpty)
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 52,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            ref.read(playerProvider.notifier).playQueue(clips, 0);
                                            showModalBottomSheet(
                                              context: context,
                                              isScrollControlled: true,
                                              backgroundColor: Colors.transparent,
                                              builder: (_) => const FullPlayerScreen(),
                                            );
                                          },
                                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                          label: const Text(
                                            'Play',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.white,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(26),
                                            ),
                                            elevation: 0,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    GestureDetector(
                                      onTap: () {
                                        final shuffled = List<Clip>.from(clips)..shuffle();
                                        ref.read(playerProvider.notifier).playQueue(shuffled, 0);
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (_) => const FullPlayerScreen(),
                                        );
                                      },
                                      child: Container(
                                        width: 52,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: isDark ? AppColors.darkCard : AppColors.gray100,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.shuffle_rounded,
                                          color: AppColors.primary,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Playlist clips list
                      if (clips.isEmpty)
                        const SliverFillRemaining(
                          child: Center(
                            child: Text(
                              'This playlist is empty.\nGo to songs or search and tap "+" to add tracks.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final clip = clips[index];
                              return ClipListTile(
                                clip: clip,
                                index: index,
                                onPlay: () {
                                  ref.read(playerProvider.notifier).playQueue(clips, index);
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (_) => const FullPlayerScreen(),
                                  );
                                },
                                onRename: null, // Custom playlist items cannot be renamed directly
                                onDelete: () async {
                                  await ref
                                      .read(playlistsProvider.notifier)
                                      .removeClipFromPlaylist(playlist.id, clip.id);
                                  ref.invalidate(playlistClipsProvider(playlist.id));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Removed from playlist')),
                                  );
                                },
                              );
                            },
                            childCount: clips.length,
                          ),
                        ),

                      const SliverToBoxAdapter(
                        child: SizedBox(height: 120),
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

              // Mini player fixed at bottom
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

  void _showPlaylistMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: AppColors.primary),
              title: const Text('Rename Playlist'),
              onTap: () {
                Navigator.of(context).pop();
                _showRenameDialog(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: AppColors.coral),
              title: const Text('Delete Playlist'),
              onTap: () {
                Navigator.of(context).pop();
                _showDeleteConfirm(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Playlist'),
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
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await ref.read(playlistsProvider.notifier).renamePlaylist(playlist.id, newName);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist?'),
        content: Text('Are you sure you want to delete "${playlist.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.coral),
            onPressed: () async {
              await ref.read(playlistsProvider.notifier).deletePlaylist(playlist.id);
              Navigator.of(context).pop(); // pop dialog
              Navigator.of(context).pop(); // pop details screen
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
