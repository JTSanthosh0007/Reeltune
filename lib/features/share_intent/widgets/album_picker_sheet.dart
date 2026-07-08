import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../albums/album_providers.dart';
import '../../albums/widgets/create_album_dialog.dart';

class AlbumPickerSheet extends ConsumerWidget {
  final String title;
  final void Function(String albumId) onAlbumSelected;

  const AlbumPickerSheet({
    super.key,
    required this.title,
    required this.onAlbumSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumsAsync = ref.watch(albumsProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Row(
          children: [
            const Icon(Icons.music_note_rounded,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choose an album to save this clip',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),

        // Album list
        albumsAsync.when(
          data: (albums) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.35,
              ),
              child: ListView(
                shrinkWrap: true,
                children: [
                  // Create new album option
                  _AlbumOption(
                    icon: Icons.add_rounded,
                    iconColor: AppColors.primary,
                    name: 'Create New Album',
                    subtitle: null,
                    isCreate: true,
                    onTap: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (_) => const CreateAlbumDialog(),
                      );
                      // After creating, the new album will appear in the list
                    },
                  ),
                  const SizedBox(height: 4),
                  ...albums.map(
                    (album) {
                      final coverColor = album.coverColor != null
                          ? Color(int.parse(album.coverColor!, radix: 16) |
                              0xFF000000)
                          : AppColors.primary;

                      return _AlbumOption(
                        icon: Icons.album_rounded,
                        iconColor: coverColor,
                        name: album.name,
                        subtitle:
                            '${album.clipCount} clip${album.clipCount == 1 ? '' : 's'}',
                        onTap: () => onAlbumSelected(album.id),
                      );
                    },
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ),
          error: (_, __) => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Failed to load albums'),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlbumOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String? subtitle;
  final bool isCreate;
  final VoidCallback onTap;

  const _AlbumOption({
    required this.icon,
    required this.iconColor,
    required this.name,
    this.subtitle,
    this.isCreate = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isCreate
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.getAdaptiveSurfaceCard(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isCreate
                ? AppColors.primary.withValues(alpha: 0.3)
                : AppColors.getAdaptiveSurfaceBorder(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: isCreate
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Icon(
              isCreate ? Icons.add_rounded : Icons.chevron_right_rounded,
              color: AppColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
