import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/album.dart';
import '../../core/models/clip.dart';
import '../../core/storage/cover_storage_helper.dart';
import '../player/player_provider.dart';
import '../player/mini_player.dart';
import '../player/full_player_screen.dart';
import 'album_providers.dart';
import '../../shared/widgets/cached_artwork_image.dart';
import 'widgets/clip_list_tile.dart';
import '../library/PlaylistsProvider.dart';

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

                            // Center large Album cover art + centered info + buttons
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                              child: Column(
                                children: [
                                  // 1. Centered large Album cover with pencil edit button overlay
                                  Center(
                                    child: Stack(
                                      children: [
                                        Container(
                                          width: 180,
                                          height: 180,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(24),
                                            border: Border.all(
                                              color: coverColor.withValues(alpha: 0.25),
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: coverColor.withValues(alpha: 0.15),
                                                blurRadius: 30,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                          child: CachedArtworkImage(
                                            imagePath: album.coverImagePath,
                                            size: 180,
                                            borderRadius: BorderRadius.circular(22),
                                            fallbackColor: coverColor,
                                            fallbackIcon: Icons.album_rounded,
                                            fallbackIconSize: 80,
                                          ),
                                        ).animate().scale(
                                              duration: 500.ms,
                                              curve: Curves.elasticOut,
                                            ),
                                        Positioned(
                                          bottom: 6,
                                          right: 6,
                                          child: GestureDetector(
                                            onTap: () => _pickAlbumImage(context, ref, album),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Theme.of(context).scaffoldBackgroundColor,
                                                  width: 2,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.edit_rounded,
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),

                                  // 2. Album name & clip count + duration
                                  Text(
                                    album.name,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${detail.clips.length} clip${detail.clips.length == 1 ? '' : 's'} • ${_calculateTotalDuration(detail.clips)}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? AppColors.darkSubtitle
                                              : AppColors.textSecondary,
                                        ),
                                  ),
                                  const SizedBox(height: 24),

                                  // 3. Play All & Shuffle Buttons Row
                                  if (detail.clips.isNotEmpty)
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Play All Button
                                        Expanded(
                                          child: SizedBox(
                                            height: 52,
                                            child: ElevatedButton.icon(
                                              onPressed: () => _playAll(context, ref, detail.clips),
                                              icon: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                              label: const Text(
                                                'Play All',
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
                                        // Shuffle Button
                                        GestureDetector(
                                          onTap: () {
                                            // Trigger queue playback with a shuffled copy
                                            final shuffledClips = List<Clip>.from(detail.clips)..shuffle();
                                            ref.read(playerProvider.notifier).playQueue(shuffledClips, 0);
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
                                              color: Theme.of(context).brightness == Brightness.dark
                                                  ? AppColors.darkCard
                                                  : AppColors.gray100,
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: Theme.of(context).brightness == Brightness.dark
                                                    ? AppColors.darkBorder
                                                    : AppColors.surfaceBorder,
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
                              onPlay: () {
                                ref.read(playerProvider.notifier).playQueue(detail.clips, index);
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (_) => const FullPlayerScreen(),
                                );
                              },
                              onRename: () =>
                                  _showRenameClipDialog(context, ref, clip),
                              onDelete: () =>
                                  _deleteClip(context, ref, clip),
                              onMove: () =>
                                  _showMoveClipDialog(context, ref, clip),
                              onAddToPlaylist: () =>
                                  _showAddToPlaylistDialog(context, ref, clip),
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

  void _playAll(BuildContext context, WidgetRef ref, List<Clip> clips) {
    if (clips.isNotEmpty) {
      ref.read(playerProvider.notifier).playQueue(clips, 0);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const FullPlayerScreen(),
      );
    }
  }

  Future<void> _pickAlbumImage(BuildContext context, WidgetRef ref, Album album) async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (pickedFile != null) {
        final localPath = await CoverStorageHelper.saveAlbumCover(pickedFile.path, album.id);
        await ref.read(albumsProvider.notifier).updateAlbumCover(album.id, localPath);
        
        // Invalidate detail provider so it re-fetches
        ref.invalidate(albumDetailProvider(album.id));
      }
    } catch (e) {
      debugPrint('Error picking album image: $e');
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

  String _calculateTotalDuration(List<Clip> clips) {
    int totalMs = 0;
    for (final clip in clips) {
      totalMs += clip.durationMs ?? 0;
    }
    final duration = Duration(milliseconds: totalMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes}m ${seconds}s';
  }

  void _showAddToPlaylistDialog(BuildContext context, WidgetRef ref, Clip clip) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.darkSurface
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final playlistsAsync = ref.watch(playlistsProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Add to Playlist',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              playlistsAsync.when(
                data: (playlists) {
                  return Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: playlists.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return ListTile(
                            leading: const Icon(Icons.add_rounded, color: AppColors.primary),
                            title: const Text('Create New Playlist'),
                            onTap: () {
                              Navigator.of(context).pop();
                              _showCreatePlaylistDialog(context, ref, clip);
                            },
                          );
                        }
                        final playlist = playlists[index - 1];
                        return ListTile(
                          leading: const Icon(Icons.playlist_play_rounded, color: AppColors.primary),
                          title: Text(playlist.name),
                          onTap: () async {
                            await ref.read(playlistsProvider.notifier).addClipToPlaylist(playlist.id, clip.id);
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Added to "${playlist.name}"'),
                                backgroundColor: AppColors.primary,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(color: AppColors.primary),
                )),
                error: (err, _) => ListTile(title: Text('Error: $err')),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref, Clip clip) {
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
                final playlist = await ref.read(playlistsProvider.notifier).createPlaylist(name);
                if (playlist != null) {
                  await ref.read(playlistsProvider.notifier).addClipToPlaylist(playlist.id, clip.id);
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Created playlist & added to "${playlist.name}"'),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
