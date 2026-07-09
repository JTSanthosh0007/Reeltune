import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../albums/album_providers.dart';
import '../../albums/widgets/create_album_dialog.dart';

class AlbumPickerSheet extends ConsumerStatefulWidget {
  final String title;
  final void Function(String albumId) onAlbumSelected;

  const AlbumPickerSheet({
    super.key,
    required this.title,
    required this.onAlbumSelected,
  });

  @override
  ConsumerState<AlbumPickerSheet> createState() => _AlbumPickerSheetState();
}

class _AlbumPickerSheetState extends ConsumerState<AlbumPickerSheet> {
  String _searchQuery = '';
  String? _selectedAlbumId;

  @override
  Widget build(BuildContext context) {
    final albumsAsync = ref.watch(albumsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCard : AppColors.surfaceCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.surfaceBorder;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header / Title
          Row(
            children: [
              const Icon(Icons.music_note_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Select an album to save this audio clip',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                ),
          ),
          const SizedBox(height: 20),

          // Search Box mockup / interactive filter
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: isDark ? AppColors.darkSubtitle : AppColors.textTertiary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim().toLowerCase();
                      });
                    },
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                    decoration: InputDecoration(
                      hintText: 'Search album...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkSubtitle.withValues(alpha: 0.5)
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Album list
          albumsAsync.when(
            data: (albums) {
              final filteredAlbums = albums.where((album) {
                return album.name.toLowerCase().contains(_searchQuery);
              }).toList();

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Create new album option
                    _AlbumPickerOption(
                      icon: Icons.add_rounded,
                      iconColor: AppColors.primary,
                      name: 'Create New Album',
                      subtitle: null,
                      isCreate: true,
                      isSelected: false,
                      onTap: () async {
                        await showDialog<String>(
                          context: context,
                          builder: (_) => const CreateAlbumDialog(),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    if (filteredAlbums.isEmpty && _searchQuery.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No matching albums found',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      )
                    else
                      ...filteredAlbums.map(
                        (album) {
                          final coverColor = AppColors.parseHexColor(album.coverColor);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _AlbumPickerOption(
                              icon: Icons.album_rounded,
                              iconColor: coverColor,
                              name: album.name,
                              subtitle: '${album.clipCount} clip${album.clipCount == 1 ? '' : 's'}',
                              isSelected: _selectedAlbumId == album.id,
                              onTap: () {
                                setState(() {
                                  _selectedAlbumId = album.id;
                                });
                              },
                            ),
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
          const SizedBox(height: 20),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _selectedAlbumId == null
                  ? null
                  : () => widget.onAlbumSelected(_selectedAlbumId!),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Save to Album',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumPickerOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String? subtitle;
  final bool isCreate;
  final bool isSelected;
  final VoidCallback onTap;

  const _AlbumPickerOption({
    required this.icon,
    required this.iconColor,
    required this.name,
    this.subtitle,
    this.isCreate = false,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCard : AppColors.surfaceCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.surfaceBorder;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isCreate
              ? AppColors.primary.withValues(alpha: 0.1)
              : (isSelected ? AppColors.primary.withValues(alpha: 0.06) : cardColor),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isCreate
                ? AppColors.primary.withValues(alpha: 0.3)
                : (isSelected ? AppColors.primary : borderColor),
            width: isSelected ? 1.5 : 1.0,
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
                          fontWeight: FontWeight.bold,
                          color: isCreate
                              ? AppColors.primary
                              : (isDark ? Colors.white : AppColors.textPrimary),
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (!isCreate)
              Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? AppColors.primary : AppColors.textTertiary,
                size: 22,
              )
            else
              const Icon(
                Icons.add_rounded,
                color: AppColors.primary,
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}
