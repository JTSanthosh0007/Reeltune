import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/models/clip.dart';

class ClipListTile extends StatelessWidget {
  final Clip clip;
  final int index;
  final VoidCallback onPlay;
  final VoidCallback? onRename;
  final VoidCallback onDelete;
  final VoidCallback? onMove;
  final VoidCallback? onAddToPlaylist;

  const ClipListTile({
    super.key,
    required this.clip,
    required this.index,
    required this.onPlay,
    this.onRename,
    required this.onDelete,
    this.onMove,
    this.onAddToPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onPlay,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.getAdaptiveSurfaceCard(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.getAdaptiveSurfaceBorder(context)),
          ),
          child: Row(
            children: [
              // Play button
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),

              const SizedBox(width: 12),

              // Title + metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      clip.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white
                                : AppColors.textPrimary,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          clip.platformIcon,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          clip.formattedDuration,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (clip.sourcePlatform != null) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.glassBg,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              clip.sourcePlatform!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // More menu
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
                onSelected: (value) {
                  switch (value) {
                    case 'rename':
                      onRename?.call();
                      break;
                    case 'move':
                      onMove?.call();
                      break;
                    case 'playlist':
                      onAddToPlaylist?.call();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  if (onRename != null)
                    const PopupMenuItem(
                      value: 'rename',
                      child: Row(
                        children: [
                          Icon(Icons.edit_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Rename'),
                        ],
                      ),
                    ),
                  if (onMove != null)
                    const PopupMenuItem(
                      value: 'move',
                      child: Row(
                        children: [
                          Icon(Icons.drive_file_move_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Move to Album'),
                        ],
                      ),
                    ),
                  if (onAddToPlaylist != null)
                    const PopupMenuItem(
                      value: 'playlist',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Add to Playlist'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_rounded,
                            size: 18, color: AppColors.error),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: AppColors.error)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 50 * index),
          duration: 300.ms,
        )
        .slideX(
          begin: 0.05,
          delay: Duration(milliseconds: 50 * index),
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
