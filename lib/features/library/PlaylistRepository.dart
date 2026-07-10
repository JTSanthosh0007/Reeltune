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

  /// Retrieve all clips inside a playlist, ordered by sort_order.
  Future<List<Clip>> getPlaylistClips(String playlistId, {String? sortBy, bool desc = false}) async {
    final db = await _dbHelper.database;

    String orderPart = 'pc.sort_order ASC';
    if (sortBy == 'title') {
      orderPart = 'c.title ${desc ? "DESC" : "ASC"}';
    } else if (sortBy == 'date_added') {
      orderPart = 'c.created_at ${desc ? "DESC" : "ASC"}';
    }

    final results = await db.rawQuery('''
      SELECT c.* 
      FROM clips c
      INNER JOIN playlist_clips pc ON c.id = pc.clip_id
      WHERE pc.playlist_id = ?
      ORDER BY $orderPart
    ''', [playlistId]);
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  /// Create a new playlist.
  Future<Playlist> createPlaylist(
    String name, {
    String? description,
    String? coverImagePath,
  }) async {
    final db = await _dbHelper.database;
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      description: description,
      coverImagePath: coverImagePath,
    );
    await db.insert('playlists', playlist.toMap());
    return playlist;
  }

  /// Update playlist details.
  Future<void> updatePlaylist(Playlist playlist) async {
    final db = await _dbHelper.database;
    await db.update(
      'playlists',
      playlist.toMap(),
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
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
    
    // Check if already in playlist
    final exists = await isClipInPlaylist(playlistId, clipId);
    if (exists) return;

    // Get max sort order
    final maxResult = await db.rawQuery(
      'SELECT MAX(sort_order) as max_order FROM playlist_clips WHERE playlist_id = ?',
      [playlistId],
    );
    int sortOrder = 0;
    if (maxResult.isNotEmpty && maxResult.first['max_order'] != null) {
      sortOrder = (maxResult.first['max_order'] as int) + 1;
    }

    await db.insert(
      'playlist_clips',
      {
        'playlist_id': playlistId,
        'clip_id': clipId,
        'sort_order': sortOrder,
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

  /// Reorder clips within a playlist.
  Future<void> reorderPlaylistClips(String playlistId, List<String> clipIds) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (int i = 0; i < clipIds.length; i++) {
        await txn.update(
          'playlist_clips',
          {'sort_order': i},
          where: 'playlist_id = ? AND clip_id = ?',
          whereArgs: [playlistId, clipIds[i]],
        );
      }
    });
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

  /// Search playlists by name.
  Future<List<Playlist>> searchPlaylists(String query) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'playlists',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
    );
    return results.map((map) => Playlist.fromMap(map)).toList();
  }
}
