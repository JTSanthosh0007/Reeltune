import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/notification_item.dart';
import '../../core/db/notification_repository.dart';

final notificationsProvider = StateNotifierProvider<NotificationsNotifier, List<NotificationItem>>((ref) {
  return NotificationsNotifier(ref);
});

class NotificationsNotifier extends StateNotifier<List<NotificationItem>> {
  final Ref _ref;
  String _searchQuery = '';

  NotificationsNotifier(this._ref) : super([]) {
    loadNotifications();
  }

  NotificationRepository get _repo => _ref.read(notificationRepositoryProvider);

  Future<void> loadNotifications() async {
    List<NotificationItem> list;
    if (_searchQuery.trim().isEmpty) {
      list = await _repo.getNotifications();
    } else {
      list = await _repo.searchNotifications(_searchQuery);
    }

    // Prepopulate with high-quality mock announcements if database is empty (for demo & test purposes)
    if (list.isEmpty && _searchQuery.trim().isEmpty) {
      final now = DateTime.now();
      final demoList = [
        NotificationItem(
          id: 'demo_1',
          title: 'Welcome to ReelTune 1.0! 🎵',
          body: 'We are thrilled to launch ReelTune. Easily extract reel clips, cache audio offline, and boost your playback flow!',
          timestamp: now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch,
          type: 'update',
        ),
        NotificationItem(
          id: 'demo_2',
          title: 'Supercharge Your Bass 🔊',
          body: 'Tip: Tap the equalizer icon in the player footer to toggle Bass Boost and Loudness Normalizer presets.',
          timestamp: now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch,
          type: 'feature',
        ),
        NotificationItem(
          id: 'demo_3',
          title: 'Premium Reward Unlocked 🎁',
          body: 'Thanks for choosing ReelTune! Ad-free background playback is active on your device.',
          timestamp: now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
          type: 'reward',
        ),
        NotificationItem(
          id: 'demo_4',
          title: 'Share ReelTune & Earn Stars ⭐',
          body: 'Loving the app? Use the slide drawer to share ReelTune with friends and unlock high bitrate exports.',
          timestamp: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          type: 'promotion',
        ),
      ];

      for (final item in demoList) {
        await _repo.insertNotification(item);
      }
      list = await _repo.getNotifications();
    }

    state = list;
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    loadNotifications();
  }

  Future<void> addNotification({
    required String title,
    required String body,
    required String type,
  }) async {
    final notification = NotificationItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: type,
    );
    await _repo.insertNotification(notification);
    await loadNotifications();
  }

  Future<void> markAsRead(String id) async {
    await _repo.markAsRead(id);
    await loadNotifications();
  }

  Future<void> markAllAsRead() async {
    await _repo.markAllAsRead();
    await loadNotifications();
  }

  Future<void> deleteNotification(String id) async {
    await _repo.deleteNotification(id);
    await loadNotifications();
  }

  Future<void> clearAll() async {
    await _repo.clearAll();
    await loadNotifications();
  }
}
