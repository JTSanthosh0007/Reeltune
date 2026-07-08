import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/clip.dart';
import 'database_helper.dart';

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
    final results = await db.query(
      'clips',
      where: 'title LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'created_at DESC',
    );
    return results.map((map) => Clip.fromMap(map)).toList();
  }

  Future<Clip> createClip({
    required String albumId,
    required String title,
    required String filePath,
    int? durationMs,
    String? sourceUrl,
    String? sourcePlatform,
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
