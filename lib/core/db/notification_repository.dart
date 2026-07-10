import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../models/notification_item.dart';
import 'database_helper.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final dbHelper = ref.watch(databaseHelperProvider);
  return NotificationRepository(dbHelper);
});

class NotificationRepository {
  final DatabaseHelper _dbHelper;

  NotificationRepository(this._dbHelper);

  Future<void> insertNotification(NotificationItem item) async {
    final db = await _dbHelper.database;
    await db.insert(
      'notifications',
      item.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<NotificationItem>> getNotifications() async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notifications',
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => NotificationItem.fromMap(map)).toList();
  }

  Future<void> markAsRead(String id) async {
    final db = await _dbHelper.database;
    await db.update(
      'notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAllAsRead() async {
    final db = await _dbHelper.database;
    await db.update(
      'notifications',
      {'is_read': 1},
    );
  }

  Future<void> deleteNotification(String id) async {
    final db = await _dbHelper.database;
    await db.delete(
      'notifications',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAll() async {
    final db = await _dbHelper.database;
    await db.delete('notifications');
  }

  Future<List<NotificationItem>> searchNotifications(String query) async {
    final db = await _dbHelper.database;
    final List<Map<String, dynamic>> maps = await db.query(
      'notifications',
      where: 'title LIKE ? OR body LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'timestamp DESC',
    );
    return maps.map((map) => NotificationItem.fromMap(map)).toList();
  }
}
