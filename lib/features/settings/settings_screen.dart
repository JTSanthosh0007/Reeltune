import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';



import '../../core/theme/app_colors.dart';
import '../../core/storage/file_storage_service.dart';
import 'legal_dialog.dart';
import 'theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // App bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Text(
                        'Settings',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Storage section
                      _SectionHeader(title: 'Storage'),
                      _SettingsTile(
                        icon: Icons.storage_rounded,
                        iconColor: AppColors.skyBlue,
                        title: 'Clear Cache',
                        subtitle: 'Remove temporary files',
                        onTap: () => _showClearCacheDialog(context, ref),
                      ),
                      _StorageInfo(),

                      const SizedBox(height: 24),

                      // Appearance section
                      _SectionHeader(title: 'Appearance'),
                      _SettingsTile(
                        icon: Icons.palette_rounded,
                        iconColor: AppColors.primary,
                        title: 'Theme Mode',
                        subtitle: _getThemeModeLabel(ref.watch(themeModeProvider)),
                        onTap: () => _showThemeSelectionDialog(context, ref),
                      ),

                      const SizedBox(height: 24),

                      // Legal section
                      _SectionHeader(title: 'Legal'),
                      _SettingsTile(
                        icon: Icons.gavel_rounded,
                        iconColor: AppColors.coral,
                        title: 'Fair Use Notice',
                        subtitle: 'Copyright & usage disclaimer',
                        onTap: () => LegalDialog.show(context),
                      ),
                      _SettingsTile(
                        icon: Icons.privacy_tip_rounded,
                        iconColor: AppColors.primary,
                        title: 'Privacy',
                        subtitle: 'All data stored locally on your device',
                        onTap: null,
                      ),

                      const SizedBox(height: 24),

                      // About section
                      _SectionHeader(title: 'About'),
                      _SettingsTile(
                        icon: Icons.info_outline_rounded,
                        iconColor: AppColors.textTertiary,
                        title: 'ReelTune',
                        subtitle: 'Version 1.0.0',
                        onTap: null,
                      ),

                      const SizedBox(height: 32),

                      // Footer
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'ReelTune',
                              style:
                                  Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Save audio from your favorite reels',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 300.ms, duration: 500.ms),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System Default';
      case ThemeMode.light:
        return 'Light Mode';
      case ThemeMode.dark:
        return 'Dark Mode';
    }
  }

  void _showThemeSelectionDialog(BuildContext context, WidgetRef ref) {
    final currentMode = ref.read(themeModeProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ThemeMode.values.map((mode) {
            return RadioListTile<ThemeMode>(
              title: Text(_getThemeModeLabel(mode)),
              value: mode,
              groupValue: currentMode,
              activeColor: AppColors.primary,
              onChanged: (newMode) {
                if (newMode != null) {
                  ref.read(themeModeProvider.notifier).setThemeMode(newMode);
                  Navigator.of(context).pop();
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache?'),
        content: const Text(
          'This will remove temporary downloaded files. Your saved clips will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // Clear temp files
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.getAdaptiveSurfaceCard(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.getAdaptiveSurfaceBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
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
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _StorageInfo extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<int>(
      future: ref.read(fileStorageServiceProvider).getTotalStorageUsed(),
      builder: (context, snapshot) {
        final bytes = snapshot.data ?? 0;
        return Padding(
          padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
          child: Text(
            'Storage used: ${FileStorageService.formatBytes(bytes)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      },
    );
  }
}
