import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class StaticContentScreen extends StatelessWidget {
  final String title;
  final String type;

  const StaticContentScreen({
    super.key,
    required this.title,
    required this.type,
  });

  Widget _buildContent(BuildContext context, bool isDark) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.6,
          color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
        );
    final headerStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white : AppColors.textPrimary,
        );

    switch (type) {
      case 'about':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? AppColors.darkCard : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.music_note_rounded,
                      color: AppColors.primary,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ReelTune',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Version 1.0.0',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Text(
              'ReelTune is a premium music storage and clip player designed for creators and music fans alike. Easily import local songs or extract video audio links to organize custom folders and build playlists. Experience gapless audio, Lock Screen controls, and custom presets tailored specifically to your listening workflow.',
              textAlign: TextAlign.center,
              style: bodyStyle,
            ),
            const SizedBox(height: 32),
            Text('Developed by ReelTune Inc.', style: Theme.of(context).textTheme.bodySmall),
          ],
        );

      case 'privacy':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Privacy Policy', style: headerStyle),
            const SizedBox(height: 12),
            Text(
              'Last Updated: July 2026\n\nYour privacy is important to us. ReelTune processes local files and cached link audio files directly on your device. We do not sell or upload your personal media files to external cloud servers.\n\nData Collection:\nWe do not collect identifiable personal information. Database schemas and preferences are stored locally in secure app space.\n\nPermissions:\nWe require storage permissions strictly to scan local music files and write extracted content to folders.',
              style: bodyStyle,
            ),
          ],
        );

      case 'terms':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Terms of Service', style: headerStyle),
            const SizedBox(height: 12),
            Text(
              'Last Updated: July 2026\n\nBy using ReelTune, you agree to comply with the terms set forth:\n\n1. Media Ownership: You are responsible for ensuring that any audio links you extract or import do not infringe third-party copyrights.\n\n2. Device Storage: ReelTune manages local files. Clearing your app cache or deleting database tables manually will remove saved content.\n\n3. Limitation of Liability: ReelTune is provided "as is" with no warranty or guarantee of service stability.',
              style: bodyStyle,
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Sticky App Bar
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_rounded),
                    color: isDark ? Colors.white : AppColors.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                  ),
                ],
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _buildContent(context, isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
