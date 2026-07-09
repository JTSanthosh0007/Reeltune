import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/clip.dart';

final localAudioRepositoryProvider = Provider<LocalAudioRepository>((ref) {
  return LocalAudioRepository();
});

class LocalAudioRepository {
  final OnAudioQuery _audioQuery = OnAudioQuery();
  static const _uuid = Uuid();

  /// Check and request audio storage permissions.
  Future<bool> checkAndRequestPermissions() async {
    // on_audio_query manages permissions request automatically
    bool permissionStatus = await _audioQuery.permissionsStatus();
    if (!permissionStatus) {
      permissionStatus = await _audioQuery.permissionsRequest();
    }
    return permissionStatus;
  }

  /// Scan local storage and query all music tracks.
  Future<List<Clip>> scanDeviceSongs({required String defaultAlbumId}) async {
    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      return [];
    }

    try {
      final List<SongModel> songs = await _audioQuery.querySongs(
        sortType: SongSortType.DATE_ADDED,
        orderType: OrderType.DESC_OR_GREATER,
        uriType: UriType.EXTERNAL,
      );

      final List<Clip> clips = [];
      for (final song in songs) {
        // Skip files that don't have a valid path or title
        if (song.data.isEmpty || song.title.isEmpty) continue;

        // Map SongModel properties into our custom Clip model
        clips.add(Clip(
          id: 'local_${song.id}',
          albumId: defaultAlbumId,
          title: song.title,
          filePath: song.data,
          durationMs: song.duration,
          sourcePlatform: 'local',
          createdAt: song.dateAdded != null 
              ? song.dateAdded! * 1000 // Convert seconds to milliseconds
              : DateTime.now().millisecondsSinceEpoch,
          artist: song.artist == '<unknown>' ? 'Unknown Artist' : song.artist,
          albumName: song.album == '<unknown>' ? 'Unknown Album' : song.album,
          fileSize: song.size,
          trackNumber: song.track,
          genre: song.genre == '<unknown>' ? null : song.genre,
        ));
      }
      return clips;
    } catch (e) {
      // Return empty list if query fails or is not supported
      return [];
    }
  }

  /// Retrieve artwork bytes for a given local song ID
  Future<List<int>?> getSongArtwork(int songId) async {
    try {
      return await _audioQuery.queryArtwork(
        songId,
        ArtworkType.AUDIO,
        format: ArtworkFormat.JPEG,
        size: 200,
      );
    } catch (e) {
      return null;
    }
  }
}
