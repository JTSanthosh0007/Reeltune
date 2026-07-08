import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../album_providers.dart';

class CreateAlbumDialog extends ConsumerStatefulWidget {
  const CreateAlbumDialog({super.key});

  @override
  ConsumerState<CreateAlbumDialog> createState() => _CreateAlbumDialogState();
}

class _CreateAlbumDialogState extends ConsumerState<CreateAlbumDialog> {
  final _nameController = TextEditingController();
  int _selectedColorIndex = 0;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Album'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Album name (e.g. Workout Hype)',
            ),
            onSubmitted: (_) => _createAlbum(),
          ),
          const SizedBox(height: 20),
          Text(
            'Color',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(
              AppColors.albumColors.length,
              (index) => GestureDetector(
                onTap: () => setState(() => _selectedColorIndex = index),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.albumColors[index],
                    borderRadius: BorderRadius.circular(10),
                    border: _selectedColorIndex == index
                        ? Border.all(color: AppColors.textPrimary, width: 2.5)
                        : null,
                    boxShadow: _selectedColorIndex == index
                        ? [
                            BoxShadow(
                              color: AppColors.albumColors[index]
                                  .withValues(alpha: 0.5),
                              blurRadius: 8,
                            )
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _createAlbum,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createAlbum() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() => _isCreating = true);

    final colorHex = AppColors
        .albumColors[_selectedColorIndex].value
        .toRadixString(16)
        .substring(2); // Remove alpha

    await ref.read(albumsProvider.notifier).createAlbum(
          name,
          coverColor: colorHex,
        );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}
