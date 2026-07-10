import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/notification_item.dart';
import 'notifications_provider.dart';

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  ConsumerState<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends ConsumerState<NotificationCenterScreen> {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getDateCategory(int timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final itemDate = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final itemDay = DateTime(itemDate.year, itemDate.month, itemDate.day);

    if (itemDay == today) {
      return 'Today';
    } else if (itemDay == yesterday) {
      return 'Yesterday';
    } else {
      return 'Earlier';
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'extraction':
        return Icons.link_rounded;
      case 'download':
        return Icons.download_for_offline_rounded;
      case 'import':
        return Icons.folder_shared_rounded;
      case 'update':
        return Icons.system_update_rounded;
      case 'feature':
        return Icons.auto_awesome_rounded;
      case 'promotion':
        return Icons.star_rounded;
      case 'reward':
        return Icons.redeem_rounded;
      case 'error':
        return Icons.error_outline_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'extraction':
        return AppColors.primary;
      case 'download':
        return AppColors.skyBlue;
      case 'import':
        return AppColors.gold;
      case 'update':
        return AppColors.primary;
      case 'feature':
        return Colors.purple;
      case 'promotion':
        return Colors.amber;
      case 'reward':
        return AppColors.coral;
      case 'error':
        return AppColors.error;
      default:
        return AppColors.primary;
    }
  }

  void _showClearAllConfirmDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.darkCard
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Clear All Notifications?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will permanently delete all notification logs from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () {
              ref.read(notificationsProvider.notifier).clearAll();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final list = ref.watch(notificationsProvider);

    // Group items
    final Map<String, List<NotificationItem>> grouped = {
      'Today': [],
      'Yesterday': [],
      'Earlier': [],
    };

    for (final item in list) {
      final category = _getDateCategory(item.timestamp);
      grouped[category]?.add(item);
    }

    final hasNotifications = list.isNotEmpty;
    final unreadCount = list.where((item) => !item.isRead).length;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom Header App Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded),
                      color: isDark ? Colors.white : AppColors.textPrimary,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: _isSearching
                          ? TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Search notifications...',
                                border: InputBorder.none,
                                hintStyle: TextStyle(
                                  color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.5) : AppColors.textTertiary,
                                ),
                              ),
                              onChanged: (val) {
                                ref.read(notificationsProvider.notifier).setSearchQuery(val);
                              },
                            )
                          : Row(
                              children: [
                                Text(
                                  'Notifications',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : AppColors.textPrimary,
                                      ),
                                ),
                                if (unreadCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '$unreadCount new',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                    IconButton(
                      icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
                      color: isDark ? Colors.white70 : AppColors.textSecondary,
                      onPressed: () {
                        setState(() {
                          if (_isSearching) {
                            _isSearching = false;
                            _searchController.clear();
                            ref.read(notificationsProvider.notifier).setSearchQuery('');
                          } else {
                            _isSearching = true;
                          }
                        });
                      },
                    ),
                    if (hasNotifications)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded, color: isDark ? Colors.white70 : AppColors.textSecondary),
                        onSelected: (val) {
                          if (val == 'read') {
                            ref.read(notificationsProvider.notifier).markAllAsRead();
                          } else if (val == 'clear') {
                            _showClearAllConfirmDialog();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'read',
                            child: Row(
                              children: [
                                Icon(Icons.mark_chat_read_rounded, size: 18),
                                SizedBox(width: 8),
                                Text('Mark all as read'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'clear',
                            child: Row(
                              children: [
                                Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.error),
                                SizedBox(width: 8),
                                Text('Clear all logs', style: TextStyle(color: AppColors.error)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              // Notification List scroll
              Expanded(
                child: !hasNotifications
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isDark ? Colors.white.withValues(alpha: 0.05) : AppColors.gray100,
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                                color: AppColors.textTertiary,
                                size: 36,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty ? 'No matching logs' : 'No notifications yet',
                              style: TextStyle(
                                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 100),
                        children: [
                          _buildSection(context, 'Today', grouped['Today']!),
                          _buildSection(context, 'Yesterday', grouped['Yesterday']!),
                          _buildSection(context, 'Earlier', grouped['Earlier']!),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<NotificationItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.6) : AppColors.textTertiary,
            ),
          ),
        ),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final icon = _getTypeIcon(item.type);
            final typeColor = _getTypeColor(item.type);
            final timeStr = DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(item.timestamp));

            return Dismissible(
              key: ValueKey(item.id),
              direction: DismissDirection.endToStart,
              onDismissed: (_) {
                ref.read(notificationsProvider.notifier).deleteNotification(item.id);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Notification removed'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                color: AppColors.error,
                child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
              ),
              child: GestureDetector(
                onTap: () {
                  if (!item.isRead) {
                    ref.read(notificationsProvider.notifier).markAsRead(item.id);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: !item.isRead
                        ? (isDark ? AppColors.primary.withValues(alpha: 0.05) : AppColors.green50.withValues(alpha: 0.5))
                        : (isDark ? AppColors.darkCard : Colors.white),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                      ),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Status Circle indicator
                      Padding(
                        padding: const EdgeInsets.only(top: 4, right: 12),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: !item.isRead ? AppColors.primary : Colors.transparent,
                          ),
                        ),
                      ),
                      // Type Icon Badge
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: typeColor.withValues(alpha: 0.12),
                        ),
                        child: Icon(icon, color: typeColor, size: 20),
                      ),
                      const SizedBox(width: 14),
                      // Text Description
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: TextStyle(
                                fontWeight: !item.isRead ? FontWeight.bold : FontWeight.w600,
                                fontSize: 14,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.body,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    ).animate().fadeIn(duration: 250.ms);
  }
}
