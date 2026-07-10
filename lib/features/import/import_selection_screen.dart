import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'playlist_import_screen.dart';

class ImportSelectionScreen extends StatelessWidget {
  const ImportSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, dynamic>> platforms = [
      {
        'id': 'spotify',
        'name': 'Spotify Importer',
        'description': 'Import Spotify playlists and albums into ReelTune.',
        'color': const Color(0xFF1DB954),
        'icon': Icons.music_note_rounded,
      },
      {
        'id': 'youtube',
        'name': 'YouTube Music Importer',
        'description': 'Import YouTube and YouTube Music playlists/albums.',
        'color': const Color(0xFFFF0000),
        'icon': Icons.video_library_rounded,
      },
      {
        'id': 'apple',
        'name': 'Apple Music Importer',
        'description': 'Import Apple Music playlists and albums.',
        'color': const Color(0xFFFC3C44),
        'icon': Icons.apple_rounded,
      },
      {
        'id': 'jiosaavn',
        'name': 'JioSaavn Importer',
        'description': 'Import JioSaavn playlists and albums into ReelTune.',
        'color': const Color(0xFF24A1E1),
        'icon': Icons.library_music_rounded,
      },
      {
        'id': 'm3u',
        'name': 'M3U Importer',
        'description': 'Import tracks from local M3U / M3U8 files.',
        'color': const Color(0xFFD4AF37),
        'icon': Icons.list_alt_rounded,
      },
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          'Import Songs',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: platforms.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final platform = platforms[index];
              return Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkCard.withValues(alpha: 0.6)
                      : Colors.white.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder.withValues(alpha: 0.5)
                        : AppColors.surfaceBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PlaylistImportScreen(platform: platform['id']),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(14.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: platform['color'].withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              platform['icon'],
                              color: platform['color'],
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  platform['name'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  platform['description'],
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: isDark
                                        ? AppColors.darkSubtitle.withValues(alpha: 0.8)
                                        : AppColors.textSecondary.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isDark
                                ? AppColors.darkSubtitle.withValues(alpha: 0.5)
                                : AppColors.textTertiary.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
