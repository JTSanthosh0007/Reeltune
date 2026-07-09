import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' hide Clip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/db/album_repository.dart';

import '../../core/theme/app_colors.dart';
import '../../core/storage/file_storage_service.dart';
import '../../core/ads/ConsentService.dart';
import '../../core/ads/RewardedService.dart';
import '../../core/ads/InterstitialService.dart';
import '../../core/db/clip_repository.dart';
import '../albums/album_providers.dart';
import '../player/player_provider.dart';
import '../player/audio_handler.dart';
import '../../main.dart';
import 'legal_dialog.dart';
import 'theme_provider.dart';
import '../import/ImportNotifier.dart';

// Dynamically watch library statistics and storage usage
final settingsStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final clips = await ref.watch(clipRepositoryProvider).getAllClips();
  final downloaded = clips.where((c) => c.sourcePlatform != 'local').length;
  final imported = clips.where((c) => c.sourcePlatform == 'local').length;
  final bytes = await ref.read(fileStorageServiceProvider).getTotalStorageUsed();
  return {
    'downloaded': downloaded,
    'imported': imported,
    'storageUsed': FileStorageService.formatBytes(bytes),
    'rawBytes': bytes,
  };
});

// App settings state providers (mock/persisted settings)
final playbackQualityProvider = StateProvider<String>((ref) => 'High (320kbps)');
final storagePathProvider = StateProvider<String>((ref) => 'Internal Storage');
final downloadWifiOnlyProvider = StateProvider<bool>((ref) => true);
final lockscreenWidgetStyleProvider = StateProvider<String>((ref) => 'Modern Wave');
final bluetoothMetadataProvider = StateProvider<bool>((ref) => true);

class SettingsScreen extends ConsumerWidget {
  final bool isTab;

  const SettingsScreen({
    super.key,
    this.isTab = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statsAsync = ref.watch(settingsStatsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isAdFree = ref.watch(adFreeProvider);
    final qualitySetting = ref.watch(playbackQualityProvider);
    final storageSetting = ref.watch(storagePathProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // Premium App Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(isTab ? 20 : 16, 20, 16, 10),
                  child: Row(
                    children: [
                      if (!isTab) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_rounded),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 30,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                          ),
                          Text(
                            'Customize your playback & library',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppColors.textTertiary,
                                ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // ReelTune Branding badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.music_note_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 4),
                            Text(
                              'ReelTune',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 12),

                      // 1. Profile Card with Glassmorphism
                      statsAsync.when(
                        data: (stats) => Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.05),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.primary,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Guest Library',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : AppColors.textPrimary,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${stats['downloaded']} downloads • ${stats['imported']} local songs',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 12,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Storage: ${stats['storageUsed']} used',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            fontSize: 11,
                                            color: AppColors.textTertiary,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        loading: () => const Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      ),

                      const SizedBox(height: 24),

                      // 2. Quick Actions Grid
                      Text(
                        'Quick Library Actions',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppColors.textTertiary,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 12),

                      // Grid layout of large actions
                      GridView.count(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        shrinkWrap: true,
                        childAspectRatio: 1.6,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _buildQuickActionCard(
                            context,
                            icon: Icons.storage_rounded,
                            title: 'Clear Cache',
                            subtitle: 'Free temporary space',
                            color: AppColors.skyBlue,
                            onTap: () => _showClearCacheSheet(context, ref),
                          ),
                          _buildQuickActionCard(
                            context,
                            icon: Icons.library_music_rounded,
                            title: 'Scan Device',
                            subtitle: 'Import local audio',
                            color: AppColors.primary,
                            onTap: () => _triggerMediaScan(context, ref),
                          ),
                          _buildQuickActionCard(
                            context,
                            icon: Icons.backup_rounded,
                            title: 'Backup Library',
                            subtitle: 'Export data to backup file',
                            color: Colors.green,
                            onTap: () => _backupLibrary(context, ref),
                          ),
                          _buildQuickActionCard(
                            context,
                            icon: Icons.restore_rounded,
                            title: 'Restore Library',
                            subtitle: 'Restore previous backup',
                            color: Colors.amber,
                            onTap: () => _restoreLibrary(context, ref),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // 3. Settings Groups
                      // Group A: Appearance
                      _buildGroupHeader(context, 'Appearance'),
                      _buildGroupCard(
                        context,
                        children: [
                          _buildListTile(
                            context,
                            icon: Icons.palette_rounded,
                            iconColor: AppColors.primary,
                            title: 'Theme Mode',
                            subtitle: _getThemeModeLabel(themeMode),
                            onTap: () => _showThemeSelectionSheet(context, ref),
                          ),
                          _buildDivider(),
                          _buildListTile(
                            context,
                            icon: Icons.grid_view_rounded,
                            iconColor: AppColors.skyBlue,
                            title: 'Storage Location',
                            subtitle: storageSetting,
                            onTap: () => _showStorageLocationSheet(context, ref),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Group B: Playback
                      _buildGroupHeader(context, 'Playback'),
                      _buildGroupCard(
                        context,
                        children: [
                          _buildListTile(
                            context,
                            icon: Icons.high_quality_rounded,
                            iconColor: AppColors.primary,
                            title: 'Audio Quality',
                            subtitle: qualitySetting,
                            onTap: () => _showQualitySelectionSheet(context, ref),
                          ),
                          _buildDivider(),
                          _buildListTile(
                            context,
                            icon: Icons.equalizer_rounded,
                            iconColor: AppColors.skyBlue,
                            title: 'Sound Equalizer',
                            subtitle: 'Bass boost, Treble & Normalizer',
                            onTap: () => _showEqualizerSheet(context, ref),
                          ),
                          _buildDivider(),
                          _buildListTile(
                            context,
                            icon: Icons.snooze_rounded,
                            iconColor: AppColors.coral,
                            title: 'Sleep Timer',
                            subtitle: ref.watch(playerProvider).sleepTimerRemaining != null
                                ? 'Active: ${_formatSleepTimerRemaining(ref.watch(playerProvider).sleepTimerRemaining!)} remaining'
                                : 'Turn off playback automatically',
                            onTap: () => _showSleepTimerSheet(context, ref),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Group C: Downloads & Network
                      _buildGroupHeader(context, 'Downloads & Network'),
                      _buildGroupCard(
                        context,
                        children: [
                          _buildSwitchListTile(
                            context,
                            icon: Icons.wifi_rounded,
                            iconColor: Colors.teal,
                            title: 'Download over Wi-Fi only',
                            subtitle: 'Reduce mobile network usage',
                            value: ref.watch(downloadWifiOnlyProvider),
                            onChanged: (val) {
                              ref.read(downloadWifiOnlyProvider.notifier).state = val;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Group D: Notifications & Hardware
                      _buildGroupHeader(context, 'Hardware & Notifications'),
                      _buildGroupCard(
                        context,
                        children: [
                          _buildListTile(
                            context,
                            icon: Icons.notification_important_rounded,
                            iconColor: AppColors.coral,
                            title: 'Lockscreen Widget Style',
                            subtitle: ref.watch(lockscreenWidgetStyleProvider),
                            onTap: () => _showLockscreenStyleSheet(context, ref),
                          ),
                          _buildDivider(),
                          _buildSwitchListTile(
                            context,
                            icon: Icons.bluetooth_audio_rounded,
                            iconColor: AppColors.skyBlue,
                            title: 'Bluetooth Metadata sharing',
                            subtitle: 'Stream cover art/titles to car console',
                            value: ref.watch(bluetoothMetadataProvider),
                            onChanged: (val) {
                              ref.read(bluetoothMetadataProvider.notifier).state = val;
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Group E: Sponsor & Ads
                      _buildGroupHeader(context, 'Sponsor & Ads'),
                      _buildGroupCard(
                        context,
                        children: [
                          _buildListTile(
                            context,
                            icon: Icons.card_giftcard_rounded,
                            iconColor: Colors.amber,
                            title: isAdFree ? 'Ad-free Premium Active' : 'Sponsor Ad-Free (1 Hour)',
                            subtitle: isAdFree
                                ? 'Enjoy premium ad-free experience!'
                                : 'Watch a short ad to support and remove ads',
                            onTap: isAdFree
                                ? null
                                : () {
                                    ref.read(rewardedServiceProvider).showRewardedAd(
                                          context: context,
                                          onRewardGranted: (reward) {
                                            ref
                                                .read(adFreeProvider.notifier)
                                                .setAdFreeForDuration(const Duration(hours: 1));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text('Ads removed for 1 hour! Enjoy! 🎉'),
                                                backgroundColor: AppColors.primary,
                                              ),
                                            );
                                          },
                                          onAdDismissed: () {},
                                        );
                                  },
                          ),
                          _buildDivider(),
                          _buildListTile(
                            context,
                            icon: Icons.privacy_tip_outlined,
                            iconColor: AppColors.skyBlue,
                            title: 'GDPR Privacy preferences',
                            subtitle: 'Manage personalized advertising choices',
                            onTap: () =>
                                ref.read(adConsentProvider.notifier).showPrivacyOptionsForm(context),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // Group F: Legal & Info
                      _buildGroupHeader(context, 'Legal & About'),
                      _buildGroupCard(
                        context,
                        children: [
                          _buildListTile(
                            context,
                            icon: Icons.gavel_rounded,
                            iconColor: AppColors.coral,
                            title: 'Fair Use Disclaimer',
                            subtitle: 'Usage guidelines & copyright information',
                            onTap: () => LegalDialog.show(context),
                          ),
                          _buildDivider(),
                          _buildListTile(
                            context,
                            icon: Icons.info_outline_rounded,
                            iconColor: AppColors.textTertiary,
                            title: 'ReelTune Version',
                            subtitle: 'v1.0.0 (Production build)',
                            onTap: null,
                          ),
                        ],
                      ),

                      const SizedBox(height: 40),

                      // Premium Branding Footer
                      Center(
                        child: Column(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: AppColors.primaryGradient,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.25),
                                    blurRadius: 15,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.music_note_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'ReelTune',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : AppColors.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Designed for audio lovers',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textTertiary,
                                  ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                      const SizedBox(height: 180), // spacing for bottom bar
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

  // --- UI Helpers ---

  Widget _buildGroupHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
      ),
    );
  }

  Widget _buildGroupCard(BuildContext context, {required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      color: isDark ? AppColors.darkCard : Colors.white,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
              fontSize: 14,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
      ),
      trailing: onTap != null
          ? const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20)
          : null,
      onTap: onTap,
    );
  }

  Widget _buildSwitchListTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeColor: AppColors.primary,
      secondary: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textPrimary,
              fontSize: 14,
            ),
      ),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: AppColors.textTertiary,
            ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, indent: 64, endIndent: 16, color: Colors.transparent);
  }

  Widget _buildQuickActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 16),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // --- Theme Mode Sheet ---
  void _showThemeSelectionSheet(BuildContext context, WidgetRef ref) {
    final currentMode = ref.read(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Choose Theme',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              ...ThemeMode.values.map((mode) {
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
              }),
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

  // --- Quality Selection Sheet ---
  void _showQualitySelectionSheet(BuildContext context, WidgetRef ref) {
    final currentQuality = ref.read(playbackQualityProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Playback Audio Quality',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              ...['Low (96kbps)', 'Medium (160kbps)', 'High (320kbps)'].map((quality) {
                return RadioListTile<String>(
                  title: Text(quality),
                  value: quality,
                  groupValue: currentQuality,
                  activeColor: AppColors.primary,
                  onChanged: (newQuality) {
                    if (newQuality != null) {
                      ref.read(playbackQualityProvider.notifier).state = newQuality;
                      Navigator.of(context).pop();
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // --- Storage Location Sheet ---
  void _showStorageLocationSheet(BuildContext context, WidgetRef ref) {
    final currentPath = ref.read(storagePathProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Primary Storage Path',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              ...['Internal Storage', 'External SD Card'].map((path) {
                return RadioListTile<String>(
                  title: Text(path),
                  value: path,
                  groupValue: currentPath,
                  activeColor: AppColors.primary,
                  onChanged: (newPath) {
                    if (newPath != null) {
                      ref.read(storagePathProvider.notifier).state = newPath;
                      Navigator.of(context).pop();
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // --- Lockscreen Style Sheet ---
  void _showLockscreenStyleSheet(BuildContext context, WidgetRef ref) {
    final currentStyle = ref.read(lockscreenWidgetStyleProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Lockscreen Widget Design',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              ...['Classic Bar', 'Modern Wave', 'Dynamic Minimal'].map((style) {
                return RadioListTile<String>(
                  title: Text(style),
                  value: style,
                  groupValue: currentStyle,
                  activeColor: AppColors.primary,
                  onChanged: (newStyle) {
                    if (newStyle != null) {
                      ref.read(lockscreenWidgetStyleProvider.notifier).state = newStyle;
                      Navigator.of(context).pop();
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // --- Clear Cache Modal bottom sheet ---
  void _showClearCacheSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clear Cache?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'This will delete temporary image & audio cache files from your device. Your saved library metadata and downloaded songs will remain completely untouched.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () async {
                      // Perform cache clear
                      try {
                        final tempDir = await getTemporaryDirectory();
                        if (await tempDir.exists()) {
                          await tempDir.delete(recursive: true);
                          await tempDir.create();
                        }
                        Navigator.of(context).pop();
                        ref.invalidate(settingsStatsProvider);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Temporary Cache files cleared successfully! 🧹'),
                            backgroundColor: AppColors.primary,
                          ),
                        );
                      } catch (_) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: const Text('Clear Cache'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Sleep Timer Sheet ---
  void _showSleepTimerSheet(BuildContext context, WidgetRef ref) {
    final timerRemaining = ref.read(playerProvider).sleepTimerRemaining;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Sleep Timer',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_off_rounded),
                title: const Text('Turn Off Timer'),
                trailing: timerRemaining == null ? const Icon(Icons.check, color: AppColors.primary) : null,
                onTap: () {
                  ref.read(playerProvider.notifier).cancelSleepTimer();
                  Navigator.of(context).pop();
                },
              ),
              ...[5, 15, 30, 45, 60].map((mins) {
                return ListTile(
                  leading: const Icon(Icons.snooze_rounded),
                  title: Text('$mins Minutes'),
                  onTap: () {
                    ref.read(playerProvider.notifier).setSleepTimer(Duration(minutes: mins));
                    Navigator.of(context).pop();
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // --- Equalizer & sound enhancements sheet ---
  void _showEqualizerSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final state = ref.watch(playerProvider);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'Equalizer & Effects',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    SwitchListTile(
                      title: const Text('Bass Boost'),
                      subtitle: const Text('Enhance deep low-end frequencies'),
                      value: state.isBassBoostEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        ref.read(playerProvider.notifier).toggleBassBoost(val);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Treble Boost'),
                      subtitle: const Text('Enhance clear high-end frequencies'),
                      value: state.isTrebleBoostEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        ref.read(playerProvider.notifier).toggleTrebleBoost(val);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Vocal Booster'),
                      subtitle: const Text('Highlights center-mid vocal ranges'),
                      value: state.isVocalEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        ref.read(playerProvider.notifier).toggleVocalEnhancement(val);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Loudness Normalizer'),
                      subtitle: const Text('Keeps volume consistent across clips'),
                      value: state.isLoudnessNormalizerEnabled,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        ref.read(playerProvider.notifier).toggleLoudnessNormalization(val);
                        setModalState(() {});
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- Real Database Backup ---
  Future<void> _backupLibrary(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(clipRepositoryProvider);
      final clips = await db.getAllClips();
      final albums = ref.read(albumsProvider).value ?? [];

      final backupData = {
        'clips': clips.map((c) => c.toMap()).toList(),
        'albums': albums.map((a) => a.toMap()).toList(),
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      final appDir = await getApplicationDocumentsDirectory();
      final backupFile = File('${appDir.path}/reeltune_backup.json');
      await backupFile.writeAsString(jsonEncode(backupData));

      ref.invalidate(settingsStatsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Library backed up successfully! 💾'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to backup library: $e'),
          backgroundColor: AppColors.coral,
        ),
      );
    }
  }

  // --- Real Database Restore ---
  Future<void> _restoreLibrary(BuildContext context, WidgetRef ref) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final backupFile = File('${appDir.path}/reeltune_backup.json');
      if (!await backupFile.exists()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No previous backup file found. Please backup first! ❌'),
            backgroundColor: AppColors.coral,
          ),
        );
        return;
      }

      final backupContent = await backupFile.readAsString();
      final backupData = jsonDecode(backupContent) as Map<String, dynamic>;

      final clipsData = backupData['clips'] as List<dynamic>;
      final albumsData = backupData['albums'] as List<dynamic>;

      final clipRepo = ref.read(clipRepositoryProvider);
      final albumRepo = ref.read(albumRepositoryProvider);
      // Restore each album & clip
      for (final albumMap in albumsData) {
        final album = Album.fromMap(albumMap as Map<String, dynamic>);
        await albumRepo.saveAlbum(album);
      }

      for (final clipMap in clipsData) {
        final clip = Clip.fromMap(clipMap as Map<String, dynamic>);
        await clipRepo.insertClip(clip);
      }

      ref.invalidate(settingsStatsProvider);
      ref.invalidate(albumsProvider);
      ref.invalidate(recentClipsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Library restored successfully from backup! 🔄'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to restore library: $e'),
          backgroundColor: AppColors.coral,
        ),
      );
    }
  }

  // --- Media scanner scan handler ---
  Future<void> _triggerMediaScan(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(width: 20),
            Text('Scanning local storage...'),
          ],
        ),
      ),
    );

    try {
      await ref.read(importProvider.notifier).scanAndImportLocalSongs();
      Navigator.of(context).pop(); // dismiss loading dialog

      final importState = ref.read(importProvider);
      if (importState.status == ImportStatus.success) {
        ref.invalidate(settingsStatsProvider);
        ref.invalidate(albumsProvider);
        ref.invalidate(recentClipsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import complete! Found ${importState.scannedCount} new songs.'),
            backgroundColor: AppColors.primary,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import: ${importState.errorMessage}'),
            backgroundColor: AppColors.coral,
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop(); // dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.coral,
        ),
      );
    }
  }

  String _formatSleepTimerRemaining(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
