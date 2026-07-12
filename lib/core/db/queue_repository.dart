import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../models/queue_item.dart';
import 'database_helper.dart';

final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return QueueRepository(dbHelper);
});

class QueueRepository {
  final DatabaseHelper _dbHelper;

  QueueRepository(this._dbHelper);

  Future<void> insertQueueItem(QueueItem item) async {
    final db = await _dbHelper.database;
    await db.insert(
      'download_queue',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateQueueItem(QueueItem item) async {
    final db = await _dbHelper.database;
    await db.update(
      'download_queue',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> updateMetadata(String id, String title, String artist, String thumbnail, int duration) async {
    final db = await _dbHelper.database;
    await db.update(
      'download_queue',
      {
        'title': title,
        'artist': artist,
        'thumbnail': thumbnail,
        'duration': duration,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStatusAndProgress(String id, String status, double progress, {String? error}) async {
    final db = await _dbHelper.database;
    final Map<String, dynamic> values = {
      'status': status,
      'progress': progress,
    };
    if (error != null) {
      values['error'] = error;
    }
    await db.update(
      'download_queue',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateStatusProgressSpeedEtaRetries(
    String id,
    String status,
    double progress,
    double speed,
    int eta,
    int retries, {
    String? error,
  }) async {
    final db = await _dbHelper.database;
    final Map<String, dynamic> values = {
      'status': status,
      'progress': progress,
      'speed': speed,
      'eta': eta,
      'retries': retries,
    };
    if (error != null) {
      values['error'] = error;
    }
    await db.update(
      'download_queue',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<QueueItem>> getAllQueueItems() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'download_queue',
      orderBy: 'priority DESC, created_at DESC',
    );
    return maps.map((map) => QueueItem.fromMap(map)).toList();
  }

  Future<int> getPendingCount() async {
    final db = await _dbHelper.database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM download_queue WHERE status = 'pending' OR status = 'downloading'"
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> deleteQueueItem(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'download_queue',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearCompleted() async {
    final db = await _dbHelper.database;
    await db.delete(
      'download_queue',
      where: "status = 'completed'",
    );
  }

  Future<void> clearAll() async {
    final db = await _dbHelper.database;
    await db.delete('download_queue');
  }
}
