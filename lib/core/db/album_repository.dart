import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';

import '../models/album.dart';
import 'database_helper.dart';

final albumRepositoryProvider = Provider<AlbumRepository>((ref) {
  return AlbumRepository(ref.watch(databaseHelperProvider));
});

class AlbumRepository {
  final DatabaseHelper _dbHelper;
  static const _uuid = Uuid();

  AlbumRepository(this._dbHelper);

  Future<List<Album>> getAllAlbums() async {
    final db = await _dbHelper.database;

    // Get albums with clip counts via a JOIN
    final results = await db.rawQuery('''
      SELECT a.*, COUNT(c.id) as clip_count
      FROM albums a
      LEFT JOIN clips c ON c.album_id = a.id
      GROUP BY a.id
      ORDER BY a.created_at DESC
    ''');

    return results.map((map) {
      return Album.fromMap(map, clipCount: (map['clip_count'] as int?) ?? 0);
    }).toList();
  }

  Future<Album?> getAlbum(String id) async {
    final db = await _dbHelper.database;

    final results = await db.rawQuery('''
      SELECT a.*, COUNT(c.id) as clip_count
      FROM albums a
      LEFT JOIN clips c ON c.album_id = a.id
      WHERE a.id = ?
      GROUP BY a.id
    ''', [id]);

    if (results.isEmpty) return null;
    return Album.fromMap(
      results.first,
      clipCount: (results.first['clip_count'] as int?) ?? 0,
    );
  }

  Future<Album> createAlbum(String name, {String? coverColor, String? coverImagePath}) async {
    final db = await _dbHelper.database;

    final album = Album(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      coverColor: coverColor,
      coverImagePath: coverImagePath,
    );

    await db.insert('albums', album.toMap());
    return album;
  }

  Future<void> saveAlbum(Album album) async {
    final db = await _dbHelper.database;
    await db.insert(
      'albums',
      album.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateAlbum(Album album) async {
    final db = await _dbHelper.database;
    await db.update(
      'albums',
      album.toMap(),
      where: 'id = ?',
      whereArgs: [album.id],
    );
  }

  Future<void> deleteAlbum(String id) async {
    final db = await _dbHelper.database;
    // Clips will be cascade-deleted via foreign key constraint
    await db.delete('albums', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> getAlbumCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM albums');
    return (result.first['count'] as int?) ?? 0;
  }

  Future<List<Album>> searchAlbums(String query) async {
    final db = await _dbHelper.database;
    final results = await db.rawQuery('''
      SELECT a.*, COUNT(c.id) as clip_count
      FROM albums a
      LEFT JOIN clips c ON c.album_id = a.id
      WHERE a.name LIKE ?
      GROUP BY a.id
      ORDER BY a.created_at DESC
    ''', ['%$query%']);
    return results.map((map) {
      return Album.fromMap(map, clipCount: (map['clip_count'] as int?) ?? 0);
    }).toList();
  }
}
