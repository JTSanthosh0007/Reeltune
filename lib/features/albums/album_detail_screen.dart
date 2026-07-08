import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/clip.dart';
import '../player/player_provider.dart';
import '../player/mini_player.dart';
import 'album_providers.dart';
import 'widgets/clip_list_tile.dart';

class AlbumDetailScreen extends ConsumerWidget {
  final String albumId;

  const AlbumDetailScreen({super.key, required this.albumId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(albumDetailProvider(albumId));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: detailAsync.when(
          data: (detail) {
            final album = detail.album;
            if (album == null) {
              return const Center(child: Text('Album not found'));
            }

            final coverColor = album.coverColor != null
                ? Color(int.parse(album.coverColor!, radix: 16) | 0xFF000000)
                : AppColors.primary;

            return Stack(
              children: [
                CustomScrollView(
                  slivers: [
                    // Hero header
                    SliverToBoxAdapter(
                      child: Container(
                        padding: EdgeInsets.only(
                          top: MediaQuery.of(context).padding.top + 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              coverColor.withValues(alpha: 0.12),
                              Theme.of(context).scaffoldBackgroundColor,
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                        child: Column(
                          children: [
                            // Nav bar
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                        Icons.arrow_back_ios_rounded),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                  const Spacer(),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded),
                                    onSelected: (value) {
                                      switch (value) {
                                        case 'rename':
                                          _showRenameDialog(
                                              context, ref, album.name);
                                          break;
                                        case 'delete':
                                          _showDeleteConfirmation(
                                              context, ref);
                                          break;
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'rename',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_rounded,
                                                size: 18),
                                            SizedBox(width: 8),
                                            Text('Rename'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_rounded,
                                                size: 18,
                                                color: AppColors.error),
                                            SizedBox(width: 8),
                                            Text('Delete Album',
                                                style: TextStyle(
                                                    color: AppColors.error)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Album icon + info
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 24),
                              child: Row(
                                children: [
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      color: coverColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: coverColor.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.album_rounded,
                                      color: coverColor,
                                      size: 40,
                                    ),
                                  ).animate().scale(
                                        duration: 500.ms,
                                        curve: Curves.elasticOut,
                                      ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          album.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineLarge,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${detail.clips.length} clip${detail.clips.length == 1 ? '' : 's'}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (detail.clips.isNotEmpty)
                                    IconButton(
                                      onPressed: () => _playAll(ref, detail.clips),
                                      icon: Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          gradient: AppColors.primaryGradient,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Clips list
                    if (detail.clips.isEmpty)
                      SliverFillRemaining(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.music_off_rounded,
                                color: AppColors.textTertiary,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No clips yet',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: AppColors.textTertiary),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Share a reel to save audio here',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final clip = detail.clips[index];
                            return ClipListTile(
                              clip: clip,
                              index: index,
                              onPlay: () =>
                                  ref.read(playerProvider.notifier).playClip(clip),
                              onRename: () =>
                                  _showRenameClipDialog(context, ref, clip),
                              onDelete: () =>
                                  _deleteClip(context, ref, clip),
                              onMove: () =>
                                  _showMoveClipDialog(context, ref, clip),
                            );
                          },
                          childCount: detail.clips.length,
                        ),
                      ),

                    // Bottom padding for mini player
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 120),
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
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (error, _) => Center(
            child: Text('Error: $error'),
          ),
        ),
      ),
    );
  }

  void _playAll(WidgetRef ref, List<Clip> clips) {
    if (clips.isNotEmpty) {
      ref.read(playerProvider.notifier).playClip(clips.first);
    }
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Album'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Album name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref
                    .read(albumsProvider.notifier)
                    .renameAlbum(albumId, newName);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Album?'),
        content: const Text(
          'This will permanently delete the album and all its clips. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
            ),
            onPressed: () {
              ref.read(albumsProvider.notifier).deleteAlbum(albumId);
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRenameClipDialog(BuildContext context, WidgetRef ref, Clip clip) {
    final controller = TextEditingController(text: clip.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Clip'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Clip title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                ref.read(clipOperationsProvider).renameClip(clip.id, newTitle);
                Navigator.of(context).pop();
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteClip(BuildContext context, WidgetRef ref, Clip clip) {
    ref.read(clipOperationsProvider).deleteClip(clip.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted "${clip.title}"'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {},
        ),
      ),
    );
  }

  void _showMoveClipDialog(BuildContext context, WidgetRef ref, Clip clip) {
    final albumsAsync = ref.read(albumsProvider);
    albumsAsync.whenData((albums) {
      final otherAlbums = albums.where((a) => a.id != albumId).toList();
      if (otherAlbums.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Create another album to move clips')),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Move to Album',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ...otherAlbums.map(
                (album) => ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: album.coverColor != null
                          ? Color(
                                  int.parse(album.coverColor!, radix: 16) |
                                      0xFF000000)
                              .withValues(alpha: 0.12)
                          : AppColors.green50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.album_rounded, size: 20),
                  ),
                  title: Text(album.name),
                  subtitle: Text('${album.clipCount} clips'),
                  onTap: () {
                    ref
                        .read(clipOperationsProvider)
                        .moveClip(clip.id, album.id);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Moved to "${album.name}"'),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
