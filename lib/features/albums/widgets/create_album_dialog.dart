import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/storage/cover_storage_helper.dart';
import '../../../core/ads/InterstitialService.dart';
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
  String? _pickedImagePath;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (pickedFile != null) {
        setState(() {
          _pickedImagePath = pickedFile.path;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Album'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image upload selector
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity,
                height: 100,
                decoration: BoxDecoration(
                  color: AppColors.getAdaptiveSurfaceCard(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.getAdaptiveSurfaceBorder(context),
                  ),
                  image: _pickedImagePath != null
                      ? DecorationImage(
                          image: FileImage(File(_pickedImagePath!)),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _pickedImagePath == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_rounded,
                              color: AppColors.primary, size: 32),
                          SizedBox(height: 6),
                          Text(
                            'Upload Album Cover (Optional)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.bottomRight,
                        child: Container(
                          margin: const EdgeInsets.all(8),
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),
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
              'Color Accent',
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

    try {
      final colorHex = AppColors
          .albumColors[_selectedColorIndex].value
          .toRadixString(16)
          .substring(2); // Remove alpha

      String? coverImagePath;
      if (_pickedImagePath != null) {
        // Generate a temporary ID for file path storage before creating the DB entry
        final tempId = DateTime.now().millisecondsSinceEpoch.toString();
        coverImagePath = await CoverStorageHelper.saveAlbumCover(_pickedImagePath!, tempId);
      }

      await ref.read(albumsProvider.notifier).createAlbum(
            name,
            coverColor: colorHex,
            coverImagePath: coverImagePath,
          );

      if (mounted) {
        Navigator.of(context).pop();
        // Trigger interstitial ad after creating album
        ref.read(interstitialServiceProvider).showInterstitialIfAllowed(
              onAdDismissed: () {},
            );
      }
    } catch (e) {
      debugPrint('Error creating album: $e');
      setState(() => _isCreating = false);
    }
  }
}
