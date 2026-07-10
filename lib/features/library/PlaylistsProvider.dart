import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/clip.dart';
import '../../core/models/playlist.dart';
import 'PlaylistRepository.dart';

final playlistsProvider = StateNotifierProvider<PlaylistsNotifier, AsyncValue<List<Playlist>>>((ref) {
  return PlaylistsNotifier(ref.watch(playlistRepositoryProvider), ref);
});

class PlaylistsNotifier extends StateNotifier<AsyncValue<List<Playlist>>> {
  final PlaylistRepository _playlistRepo;
  final Ref _ref;

  PlaylistsNotifier(this._playlistRepo, this._ref) : super(const AsyncValue.loading()) {
    loadPlaylists();
  }

  Future<void> loadPlaylists() async {
    try {
      final list = await _playlistRepo.getAllPlaylists();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<Playlist?> createPlaylist(
    String name, {
    String? description,
    String? coverImagePath,
  }) async {
    try {
      final playlist = await _playlistRepo.createPlaylist(
        name,
        description: description,
        coverImagePath: coverImagePath,
      );
      await loadPlaylists();
      return playlist;
    } catch (e) {
      return null;
    }
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    try {
      await _playlistRepo.updatePlaylist(playlist);
      await loadPlaylists();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> deletePlaylist(String playlistId) async {
    try {
      await _playlistRepo.deletePlaylist(playlistId);
      await loadPlaylists();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> renamePlaylist(String playlistId, String newName) async {
    try {
      await _playlistRepo.renamePlaylist(playlistId, newName);
      await loadPlaylists();
    } catch (e) {
      // Handle error
    }
  }

  Future<void> addClipToPlaylist(String playlistId, String clipId) async {
    try {
      await _playlistRepo.addClipToPlaylist(playlistId, clipId);
      _ref.invalidate(playlistClipsProvider(playlistId));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> removeClipFromPlaylist(String playlistId, String clipId) async {
    try {
      await _playlistRepo.removeClipFromPlaylist(playlistId, clipId);
      _ref.invalidate(playlistClipsProvider(playlistId));
    } catch (e) {
      // Handle error
    }
  }

  Future<void> reorderPlaylistClips(String playlistId, List<String> clipIds) async {
    try {
      await _playlistRepo.reorderPlaylistClips(playlistId, clipIds);
      _ref.invalidate(playlistClipsProvider(playlistId));
    } catch (e) {
      // Handle error
    }
  }
}

// FutureProvider to fetch clips of a specific playlist
final playlistClipsProvider = FutureProvider.family<List<Clip>, String>((ref, playlistId) async {
  return ref.watch(playlistRepositoryProvider).getPlaylistClips(playlistId);
});

// Search playlists provider
final searchPlaylistsProvider = FutureProvider.family<List<Playlist>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  ref.watch(playlistsProvider);
  return ref.watch(playlistRepositoryProvider).searchPlaylists(query);
});
