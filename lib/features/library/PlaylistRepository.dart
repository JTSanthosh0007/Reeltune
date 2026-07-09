import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/database_helper.dart';
import '../../core/models/clip.dart';
import '../../core/models/playlist.dart';

final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(databaseHelperProvider));
});

class PlaylistRepository {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  PlaylistRepository(this._dbHelper);

  /// Retrieve all playlists.
  Future<List<Playlist>> getAllPlaylists() async {
    final db = await _dbHelper.database;
    final results = await db.query('playlists', orderBy: 'created_at DESC');
    return results.map((map) => Playlist.fromMap(map)).toList();
  }

  /// Retrieve all clips inside a playlist.
  Future<List<Clip>> getPlaylistClips(String playlistId) async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT c.* 
      FROM clips c
      INNER JOIN playlist_clips pc ON c.id = pc.clip_id
      WHERE pc.playlist_id = ?
      ORDER BY c.created_at DESC
    ''', [playlistId]);
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  /// Create a new playlist.
  Future<Playlist> createPlaylist(String name) async {
    final db = await _dbHelper.database;
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await db.insert('playlists', playlist.toMap());
    return playlist;
  }

  /// Rename a playlist.
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final db = await _dbHelper.database;
    await db.update(
      'playlists',
      {'name': newName},
      where: 'id = ?',
      whereArgs: [playlistId],
    );
  }

  /// Delete a playlist.
  Future<void> deletePlaylist(String playlistId) async {
    final db = await _dbHelper.database;
    await db.delete('playlists', where: 'id = ?', whereArgs: [playlistId]);
  }

  /// Add a clip to a playlist.
  Future<void> addClipToPlaylist(String playlistId, String clipId) async {
    final db = await _dbHelper.database;
    await db.insert(
      'playlist_clips',
      {
        'playlist_id': playlistId,
        'clip_id': clipId,
      },
    );
  }

  /// Remove a clip from a playlist.
  Future<void> removeClipFromPlaylist(String playlistId, String clipId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'playlist_clips',
      where: 'playlist_id = ? AND clip_id = ?',
      whereArgs: [playlistId, clipId],
    );
  }

  /// Check if a clip is already in a playlist.
  Future<bool> isClipInPlaylist(String playlistId, String clipId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'playlist_clips',
      where: 'playlist_id = ? AND clip_id = ?',
      whereArgs: [playlistId, clipId],
    );
    return results.isNotEmpty;
  }
}
