import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// A reusable widget that displays album artwork from a file path,
/// with proper error handling, loading placeholders, and fallback UI.
/// Uses gaplessPlayback to prevent white flashes during image transitions.
class CachedArtworkImage extends StatelessWidget {
  final String? imagePath;
  final double size;
  final BorderRadius? borderRadius;
  final Color? fallbackColor;
  final IconData fallbackIcon;
  final double fallbackIconSize;

  const CachedArtworkImage({
    super.key,
    required this.imagePath,
    this.size = 50,
    this.borderRadius,
    this.fallbackColor,
    this.fallbackIcon = Icons.music_note_rounded,
    this.fallbackIconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    final color = fallbackColor ?? AppColors.primary;
    final radius = borderRadius ?? BorderRadius.circular(10);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.3),
            color.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildImage(color),
    );
  }

  Widget _buildImage(Color color) {
    if (imagePath == null || imagePath!.isEmpty) {
      return _buildFallback(color);
    }

    final file = File(imagePath!);

    return Image(
      image: FileImage(file),
      fit: BoxFit.cover,
      width: size,
      height: size,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        // Show a subtle placeholder while the image decodes
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: frame == null ? _buildFallback(color) : child,
        );
      },
      errorBuilder: (_, __, ___) => _buildFallback(color),
    );
  }

  Widget _buildFallback(Color color) {
    return Center(
      child: Icon(
        fallbackIcon,
        color: color,
        size: fallbackIconSize,
      ),
    );
  }
}
