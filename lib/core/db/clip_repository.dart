import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/clip.dart';
import 'database_helper.dart';
import 'package:sqflite/sqflite.dart';

final clipRepositoryProvider = Provider<ClipRepository>((ref) {
  return ClipRepository(ref.watch(databaseHelperProvider));
});

class ClipRepository {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  ClipRepository(this._dbHelper);

  Future<List<Clip>> getClipsByAlbum(String albumId) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'clips',
      where: 'album_id = ?',
      whereArgs: [albumId],
      orderBy: 'created_at DESC',
    );
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  Future<List<Clip>> getAllClips() async {
    final db = await _dbHelper.database;
    final results = await db.query('clips', orderBy: 'created_at DESC');
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  Future<List<Clip>> searchClips(String query) async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT c.*
      FROM clips c
      LEFT JOIN albums a ON c.album_id = a.id
      WHERE c.title LIKE ? 
         OR a.name LIKE ? 
         OR c.artist LIKE ?
         OR c.album_name LIKE ?
         OR c.genre LIKE ?
         OR c.source_platform LIKE ?
      ORDER BY c.created_at DESC
    ''', ['%$query%', '%$query%', '%$query%', '%$query%', '%$query%', '%$query%']);
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  Future<List<Clip>> getFavoriteClips() async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'clips',
      where: 'is_favorite = 1',
      orderBy: 'created_at DESC',
    );
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  Future<List<Clip>> getRecentlyPlayedClips({int limit = 20}) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'clips',
      where: 'last_played_at IS NOT NULL',
      orderBy: 'last_played_at DESC',
      limit: limit,
    );
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  Future<void> toggleFavorite(String clipId, bool isFavorite) async {
    final db = await _dbHelper.database;
    await db.update(
      'clips',
      {'is_favorite': isFavorite ? 1 : 0},
      where: 'id = ?',
      whereArgs: [clipId],
    );
  }

  Future<void> updateLastPlayed(String clipId) async {
    final db = await _dbHelper.database;
    await db.update(
      'clips',
      {'last_played_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [clipId],
    );
  }

  Future<Clip> insertClip(Clip clip) async {
    final db = await _dbHelper.database;
    await db.insert(
      'clips',
      clip.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return clip;
  }

  Future<Clip> createClip({
    required String albumId,
    required String title,
    required String filePath,
    int? durationMs,
    String? sourceUrl,
    String? sourcePlatform,
    String? artist,
    String? albumName,
    int? bitrate,
    int? fileSize,
    String? genre,
    int? year,
    int? trackNumber,
  }) async {
    final db = await _dbHelper.database;

    final clip = Clip(
      id: _uuid.v4(),
      albumId: albumId,
      title: title,
      filePath: filePath,
      durationMs: durationMs,
      sourceUrl: sourceUrl,
      sourcePlatform: sourcePlatform,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      artist: artist,
      albumName: albumName,
      bitrate: bitrate,
      fileSize: fileSize,
      genre: genre,
      year: year,
      trackNumber: trackNumber,
    );

    await db.insert('clips', clip.toMap());
    return clip;
  }

  Future<void> updateClip(Clip clip) async {
    final db = await _dbHelper.database;
    await db.update(
      'clips',
      clip.toMap(),
      where: 'id = ?',
      whereArgs: [clip.id],
    );
  }

  Future<void> deleteClip(String id) async {
    final db = await _dbHelper.database;

    // Get clip to delete its file
    final results = await db.query(
      'clips',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isNotEmpty) {
      final clip = Clip.fromMap(results.first);
      final file = File(clip.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    }

    await db.delete('clips', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> moveClip(String clipId, String newAlbumId) async {
    final db = await _dbHelper.database;
    await db.update(
      'clips',
      {'album_id': newAlbumId},
      where: 'id = ?',
      whereArgs: [clipId],
    );
  }

  Future<Clip?> getClip(String id) async {
    final db = await _dbHelper.database;
    final results = await db.query(
      'clips',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return Clip.fromMap(results.first);
  }

  Future<int> getTotalClipCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM clips');
    return (result.first['count'] as int?) ?? 0;
  }
}
