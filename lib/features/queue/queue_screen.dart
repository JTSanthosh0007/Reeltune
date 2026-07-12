import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/models/queue_item.dart';
import 'queue_provider.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _sortBy = 'Newest'; // 'Newest', 'Oldest', 'Priority'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = ref.watch(queueProvider);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0B0B) : AppColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Download Queue',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.sort_rounded, color: isDark ? Colors.white : AppColors.textPrimary),
            onSelected: (value) {
              setState(() {
                _sortBy = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'Newest', child: Text('Sort by Newest')),
              const PopupMenuItem(value: 'Oldest', child: Text('Sort by Oldest')),
              const PopupMenuItem(value: 'Priority', child: Text('Sort by Priority')),
            ],
          ),
          IconButton(
            icon: Icon(Icons.clear_all_rounded, color: isDark ? Colors.white : AppColors.textPrimary),
            tooltip: 'Clear Completed',
            onPressed: () {
              ref.read(queueProvider.notifier).clearCompleted();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cleared completed items')),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Quick Action Row (styled like Bloomee)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => ref.read(queueProvider.notifier).downloadAll(),
                        icon: const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                        label: const Text('Download All', style: TextStyle(fontWeight: FontWeight.bold)),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF19D38A),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ref.read(queueProvider.notifier).pauseAll(),
                        icon: Icon(Icons.pause_rounded, size: 18, color: isDark ? Colors.white : AppColors.textPrimary),
                        label: Text('Pause All', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.textPrimary)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Filter Tabs
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF171717) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                    ),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    indicator: BoxDecoration(
                      color: const Color(0xFF19D38A),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: isDark ? const Color(0xFFA0A0A0) : AppColors.textSecondary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    tabs: const [
                      Tab(text: 'All'),
                      Tab(text: 'Queue'),
                      Tab(text: 'Active'),
                      Tab(text: 'Done'),
                    ],
                  ),
                ),
              ),

              // Tab View Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildFilteredList(queue, 'all', isDark),
                    _buildFilteredList(queue, 'pending', isDark),
                    _buildFilteredList(queue, 'downloading', isDark),
                    _buildFilteredList(queue, 'completed', isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilteredList(List<QueueItem> items, String filter, bool isDark) {
    var list = items;
    if (filter == 'pending') {
      list = items.where((i) => 
        i.status == 'queued' || 
        i.status == 'pending' || 
        i.status == 'paused'
      ).toList();
    } else if (filter == 'downloading') {
      list = items.where((i) => 
        i.status == 'preparing' || 
        i.status == 'fetching_metadata' || 
        i.status == 'extracting_audio' || 
        i.status == 'generating_download_link' || 
        i.status == 'downloading' || 
        i.status == 'saving'
      ).toList();
    } else if (filter == 'completed') {
      list = items.where((i) => 
        i.status == 'completed' || 
        i.status == 'failed'
      ).toList();
    }

    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_rounded,
              size: 48,
              color: isDark ? const Color(0xFFA0A0A0).withValues(alpha: 0.5) : AppColors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              'No items in this queue section',
              style: TextStyle(
                color: isDark ? const Color(0xFFA0A0A0) : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // 2. Sort items
    if (_sortBy == 'Newest') {
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } else if (_sortBy == 'Oldest') {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } else if (_sortBy == 'Priority') {
      list.sort((a, b) {
        final pCompare = b.priority.compareTo(a.priority);
        if (pCompare != 0) return pCompare;
        return b.createdAt.compareTo(a.createdAt);
      });
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = list[index];
        return _QueueCard(item: item, isDark: isDark)
            .animate()
            .fade(duration: 300.ms, delay: (index * 50).ms)
            .slideX(begin: 0.1, end: 0.0, curve: Curves.easeOutCubic);
      },
    );
  }
}

class _QueueCard extends ConsumerWidget {
  final QueueItem item;
  final bool isDark;

  const _QueueCard({
    required this.item,
    required this.isDark,
  });

  String _getStageText(QueueItem item) {
    switch (item.status) {
      case 'queued':
      case 'pending':
        return 'Queued';
      case 'preparing':
        return 'Preparing';
      case 'fetching_metadata':
        return 'Fetching Metadata...';
      case 'extracting_audio':
        return 'Extracting Audio...';
      case 'generating_download_link':
        return 'Generating Download Link...';
      case 'downloading':
        return 'Downloading: ${(item.progress * 100).toStringAsFixed(0)}%';
      case 'saving':
        return 'Saving to Library...';
      case 'completed':
        return 'Completed';
      case 'failed':
        return 'Failed: ${item.error ?? "Failed"}';
      case 'paused':
        return 'Paused';
      default:
        return item.status.toUpperCase();
    }
  }

  Color _getStageColor(QueueItem item) {
    switch (item.status) {
      case 'queued':
      case 'pending':
        return const Color(0xFF6B7280); // Gray
      case 'preparing':
        return const Color(0xFF6366F1); // Indigo
      case 'fetching_metadata':
        return const Color(0xFF0284C7); // Blue
      case 'extracting_audio':
        return const Color(0xFFA855F7); // Purple
      case 'generating_download_link':
        return const Color(0xFFD97706); // Orange/Amber
      case 'downloading':
        return const Color(0xFF10B981); // Emerald Green
      case 'saving':
        return const Color(0xFF0D9488); // Teal
      case 'completed':
        return const Color(0xFF19D38A); // Bright Green
      case 'failed':
        return const Color(0xFFEF4444); // Red
      case 'paused':
        return const Color(0xFFF59E0B); // Amber
      default:
        return const Color(0xFF19D38A);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    IconData platformIcon = Icons.link_rounded;
    Color platformColor = const Color(0xFF19D38A);

    switch (item.platform.toLowerCase()) {
      case 'spotify':
        platformIcon = Icons.music_note_rounded;
        platformColor = const Color(0xFF1DB954);
        break;
      case 'youtube':
      case 'youtube shorts':
        platformIcon = Icons.video_library_rounded;
        platformColor = const Color(0xFFFF0000);
        break;
      case 'tiktok':
        platformIcon = Icons.audiotrack_rounded;
        platformColor = Colors.teal;
        break;
      case 'instagram':
        platformIcon = Icons.camera_alt_rounded;
        platformColor = const Color(0xFFE1306C);
        break;
      case 'facebook':
        platformIcon = Icons.thumb_up_rounded;
        platformColor = const Color(0xFF1877F2);
        break;
      case 'jiosaavn':
        platformIcon = Icons.album_rounded;
        platformColor = const Color(0xFF24A1E1);
        break;
    }

    final isQueued = item.status == 'queued' || item.status == 'pending';
    final isFailed = item.status == 'failed';
    final isPaused = item.status == 'paused';
    final isCompleted = item.status == 'completed';
    
    final isActive = !isQueued && !isFailed && !isPaused && !isCompleted;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171717) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Thumbnail / Cover Art with tiny Platform Badge
                Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: isDark ? const Color(0xFF222222) : Colors.grey[200],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: item.thumbnail != null && item.thumbnail!.isNotEmpty
                          ? Image.network(
                              item.thumbnail!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Center(
                                child: Icon(platformIcon, color: platformColor, size: 22),
                              ),
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(platformIcon, color: platformColor, size: 22),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF171717) : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? const Color(0xFF171717) : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(platformIcon, color: platformColor, size: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),

                // Text detail column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title ?? 'Loading metadata...',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.artist ?? 'Please wait...',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFA0A0A0) : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Trailing controls (Circular progress or buttons)
                if (isActive)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      value: item.progress > 0 ? item.progress : null,
                      color: _getStageColor(item),
                      strokeWidth: 3,
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isQueued)
                        IconButton(
                          icon: Icon(
                            item.priority > 0 ? Icons.star_rounded : Icons.star_outline_rounded,
                            color: item.priority > 0 ? const Color(0xFF19D38A) : (isDark ? Colors.white60 : Colors.black45),
                          ),
                          onPressed: () {
                            ref.read(queueProvider.notifier).updatePriority(
                                  item.id,
                                  item.priority > 0 ? 0 : 1,
                                );
                          },
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.all(8),
                        ),
                      IconButton(
                        icon: Icon(
                          isPaused
                              ? Icons.play_arrow_rounded
                              : isFailed
                                  ? Icons.replay_rounded
                                  : Icons.pause_rounded,
                          color: isFailed ? AppColors.error : const Color(0xFF19D38A),
                        ),
                        onPressed: () {
                          final notifier = ref.read(queueProvider.notifier);
                          if (isPaused) {
                            notifier.resumeDownload(item.id);
                          } else if (isFailed) {
                            notifier.retryDownload(item.id);
                          } else if (isQueued) {
                            notifier.pauseDownload(item.id);
                          }
                        },
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: isDark ? Colors.white54 : AppColors.textTertiary),
                        onPressed: () {
                          ref.read(queueProvider.notifier).cancelDownload(item.id);
                        },
                        constraints: const BoxConstraints(),
                        padding: const EdgeInsets.all(8),
                      ),
                    ],
                  ),
              ],
            ),

            // Progress text and error details
            if (isActive || isFailed || isQueued) ...[
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _getStageText(item),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getStageColor(item),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.status == 'downloading' && item.speed > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${item.speed >= 1024 ? (item.speed / 1024).toStringAsFixed(1) : item.speed.toStringAsFixed(0)} ${item.speed >= 1024 ? "MB/s" : "KB/s"} • ETA ${item.eta}s',
                      style: const TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ],
              ),
            ],
            if (isFailed && item.error != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => ref.read(queueProvider.notifier).retryDownload(item.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Tap to Retry',
                    style: TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
            if (isActive) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: item.progress > 0 ? item.progress : null,
                  backgroundColor: isDark ? Colors.white10 : AppColors.surfaceBorder,
                  valueColor: AlwaysStoppedAnimation<Color>(_getStageColor(item)),
                  minHeight: 4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
