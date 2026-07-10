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
      appBar: AppBar(
        title: const Text('Import Songs', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            itemCount: platforms.length,
            separatorBuilder: (context, index) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final platform = platforms[index];
              return Card(
                color: isDark ? AppColors.darkCard : Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                  ),
                ),
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
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: platform['color'].withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            platform['icon'],
                            color: platform['color'],
                            size: 28,
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
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                platform['description'],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? AppColors.darkSubtitle : AppColors.textTertiary,
                        ),
                      ],
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
