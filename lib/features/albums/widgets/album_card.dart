import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/album.dart';
import '../../../shared/widgets/cached_artwork_image.dart';

class AlbumCard extends StatelessWidget {
  final Album album;
  final int index;
  final VoidCallback onTap;

  const AlbumCard({
    super.key,
    required this.album,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final coverColor = album.coverColor != null
        ? Color(int.parse(album.coverColor!, radix: 16) | 0xFF000000)
        : AppColors.albumColors[index % AppColors.albumColors.length];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.getAdaptiveSurfaceCard(context),
              AppColors.getAdaptiveSurfaceCard(context).withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.getAdaptiveSurfaceBorder(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: coverColor.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // Background glow
              Positioned(
                top: -20,
                right: -20,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        coverColor.withValues(alpha: 0.3),
                        coverColor.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Album icon
                    CachedArtworkImage(
                      imagePath: album.coverImagePath,
                      size: 52,
                      borderRadius: BorderRadius.circular(16),
                      fallbackColor: coverColor,
                      fallbackIcon: Icons.album_rounded,
                      fallbackIconSize: 28,
                    ),

                    const Spacer(),

                    // Album name
                    Text(
                      album.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 16,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 4),

                    // Clip count
                    Row(
                      children: [
                        Icon(
                          Icons.music_note_rounded,
                          color: coverColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${album.clipCount} clip${album.clipCount == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 100 * index),
          duration: 400.ms,
        )
        .slideY(
          begin: 0.1,
          delay: Duration(milliseconds: 100 * index),
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
