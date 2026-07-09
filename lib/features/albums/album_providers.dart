import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/album_repository.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/album.dart';
import '../../core/models/clip.dart';
import '../../core/storage/file_storage_service.dart';

// --- Albums list provider ---
final albumsProvider =
    AsyncNotifierProvider<AlbumsNotifier, List<Album>>(AlbumsNotifier.new);

class AlbumsNotifier extends AsyncNotifier<List<Album>> {
  @override
  Future<List<Album>> build() async {
    return ref.watch(albumRepositoryProvider).getAllAlbums();
  }

  Future<Album> createAlbum(String name, {String? coverColor, String? coverImagePath}) async {
    final repo = ref.read(albumRepositoryProvider);
    final album = await repo.createAlbum(name, coverColor: coverColor, coverImagePath: coverImagePath);
    ref.invalidateSelf();
    return album;
  }

  Future<void> updateAlbumCover(String albumId, String? coverImagePath) async {
    final repo = ref.read(albumRepositoryProvider);
    final album = await repo.getAlbum(albumId);
    if (album != null) {
      await repo.updateAlbum(album.copyWith(coverImagePath: coverImagePath));
      ref.invalidateSelf();
    }
  }

  Future<void> renameAlbum(String albumId, String newName) async {
    final repo = ref.read(albumRepositoryProvider);
    final album = await repo.getAlbum(albumId);
    if (album != null) {
      await repo.updateAlbum(album.copyWith(name: newName));
      ref.invalidateSelf();
    }
  }

  Future<void> deleteAlbum(String albumId) async {
    final repo = ref.read(albumRepositoryProvider);
    final fileService = ref.read(fileStorageServiceProvider);

    await repo.deleteAlbum(albumId);
    await fileService.deleteAlbumDirectory(albumId);
    ref.invalidateSelf();
  }

  void refresh() {
    ref.invalidateSelf();
  }
}

// --- Album detail provider (clips for a specific album) ---
final albumDetailProvider = FutureProvider.family<AlbumDetail, String>(
  (ref, albumId) async {
    // Watch the albums provider to re-fetch when albums change
    ref.watch(albumsProvider);

    final albumRepo = ref.watch(albumRepositoryProvider);
    final clipRepo = ref.watch(clipRepositoryProvider);

    final album = await albumRepo.getAlbum(albumId);
    final clips = await clipRepo.getClipsByAlbum(albumId);

    return AlbumDetail(album: album, clips: clips);
  },
);

class AlbumDetail {
  final Album? album;
  final List<Clip> clips;

  const AlbumDetail({this.album, this.clips = const []});
}

// --- Clip operations ---
final clipOperationsProvider = Provider<ClipOperations>((ref) {
  return ClipOperations(ref);
});

class ClipOperations {
  final Ref _ref;

  ClipOperations(this._ref);

  Future<void> renameClip(String clipId, String newTitle) async {
    final repo = _ref.read(clipRepositoryProvider);
    final clip = await repo.getClip(clipId);
    if (clip != null) {
      await repo.updateClip(clip.copyWith(title: newTitle));
      _ref.read(albumsProvider.notifier).refresh();
    }
  }

  Future<void> deleteClip(String clipId) async {
    final repo = _ref.read(clipRepositoryProvider);
    await repo.deleteClip(clipId);
    _ref.read(albumsProvider.notifier).refresh();
  }

  Future<void> moveClip(String clipId, String newAlbumId) async {
    final clipRepo = _ref.read(clipRepositoryProvider);
    final fileService = _ref.read(fileStorageServiceProvider);

    final clip = await clipRepo.getClip(clipId);
    if (clip != null) {
      // Move the file
      final newPath = await fileService.moveClipFile(
        clip.filePath,
        newAlbumId,
        clip.id,
      );
      // Update DB
      await clipRepo.moveClip(clipId, newAlbumId);
      await clipRepo.updateClip(clip.copyWith(
        albumId: newAlbumId,
        filePath: newPath,
      ));
      _ref.read(albumsProvider.notifier).refresh();
    }
  }
}

// --- Recent clips provider ---
final recentClipsProvider = AsyncNotifierProvider<RecentClipsNotifier, List<Clip>>(RecentClipsNotifier.new);

class RecentClipsNotifier extends AsyncNotifier<List<Clip>> {
  @override
  Future<List<Clip>> build() async {
    ref.watch(albumsProvider);
    return ref.watch(clipRepositoryProvider).getAllClips();
  }
}
