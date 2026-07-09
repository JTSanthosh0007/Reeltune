import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../albums/albums_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../player/mini_player.dart';
import '../share_intent/widgets/extraction_bottom_sheet.dart';
import '../share_intent/share_intent_provider.dart';
import '../../core/network/extraction_service.dart';
import '../../core/ads/BannerAdWidget.dart';
import '../../core/ads/InterstitialService.dart';
import 'home_screen.dart';

// Import destinations for the navigation drawer
import '../albums/album_providers.dart';
import '../albums/recent_songs_screen.dart';
import '../library/favorites_screen.dart';
import '../albums/filtered_clips_screen.dart';
import '../settings/static_content_screen.dart';
import '../settings/feedback_screen.dart';

// --- Shared Riverpod state for global tab index ---
final navigationIndexProvider = StateProvider<int>((ref) => 0);

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  void _onTabSelected(int index) {
    ref.read(navigationIndexProvider.notifier).state = index;
  }

  void _showAddClipSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddLinkBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAdFree = ref.watch(adFreeProvider);
    final currentIndex = ref.watch(navigationIndexProvider);
    final showBanner = currentIndex != 4 && !isAdFree;

    return Scaffold(
      key: _scaffoldKey,
      drawer: const _MainDrawer(),
      // Disable default drawer swipe behavior if player is expanded (managed natively)
      drawerEnableOpenDragGesture: true,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.cream,
      body: Stack(
        children: [
          // Sub-screen rendering — each tab wrapped in RepaintBoundary
          IndexedStack(
            index: currentIndex >= 3 ? currentIndex - 1 : currentIndex, // Skip the placeholder at index 2
            children: [
              RepaintBoundary(
                child: HomeScreen(
                  onNavigateToSearch: () => _onTabSelected(1),
                  onNavigateToLibrary: () => _onTabSelected(3),
                  onMenuPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
              ),
              const RepaintBoundary(child: SearchScreen(isTab: true)),
              const RepaintBoundary(child: AlbumsScreen(isLibrary: true)),
              const RepaintBoundary(child: SettingsScreen(isTab: true)),
            ],
          ),

          // Mini Player floated above the bottom bar
          Positioned(
            left: 0,
            right: 0,
            bottom: showBanner ? 142 : 92, // position above banner or custom bottom bar
            child: const MiniPlayer(),
          ),

          // Banner Ad Widget
          if (showBanner)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 92,
              child: BannerAdWidget(),
            ),

          // Custom Bottom Navigation Bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _CustomBottomNavigationBar(
              currentIndex: currentIndex,
              onTabSelected: _onTabSelected,
              onFABPressed: _showAddClipSheet,
            ),
          ),
        ],
      ),
    );
  }
}

// --- Navigation Drawer Widget ---
class _MainDrawer extends ConsumerWidget {
  const _MainDrawer();

  void _showMockRateDialog(BuildContext context) {
    int localRating = 5;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkCard
                  : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Rate ReelTune', style: TextStyle(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('How much do you love ReelTune? Let us know!'),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      return IconButton(
                        icon: Icon(
                          starIndex <= localRating ? Icons.star_rounded : Icons.star_border_rounded,
                          color: Colors.amber,
                          size: 32,
                        ),
                        onPressed: () {
                          setState(() {
                            localRating = starIndex;
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textTertiary)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Thank you for rating us $localRating stars! ⭐'),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _shareApp(BuildContext context) {
    Clipboard.setData(const ClipboardData(text: 'https://play.google.com/store/apps/details?id=com.reeltune.app'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('App share link copied to clipboard! 🔗'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildDrawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isSelected = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        selected: isSelected,
        selectedTileColor: AppColors.primary.withValues(alpha: 0.12),
        selectedColor: AppColors.primary,
        leading: Icon(
          icon,
          size: 22,
          color: isSelected
              ? AppColors.primary
              : (isDark ? AppColors.darkSubtitle : AppColors.textSecondary),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? AppColors.primary
                : (isDark ? Colors.white70 : AppColors.textPrimary),
          ),
        ),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  Widget _buildCategoryHeader(BuildContext context, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.5) : AppColors.textTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentIndex = ref.watch(navigationIndexProvider);
    final selectedLibTab = ref.watch(libraryTabProvider);

    // Watch Stats & Album updates
    final statsAsync = ref.watch(settingsStatsProvider);
    final albums = ref.watch(albumsProvider).value ?? [];

    final totalSongs = statsAsync.when(
      data: (map) => (map['downloaded'] as int? ?? 0) + (map['imported'] as int? ?? 0),
      loading: () => 0,
      error: (_, __) => 0,
    );
    final storageUsed = statsAsync.when(
      data: (map) => map['storageUsed'] as String? ?? '0 B',
      loading: () => '0 B',
      error: (_, __) => '0 B',
    );
    final totalAlbums = albums.length;

    return Drawer(
      backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
      child: Column(
        children: [
          // User Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [AppColors.primaryDark.withValues(alpha: 0.35), Colors.transparent]
                    : [AppColors.green50.withValues(alpha: 0.8), Colors.transparent],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // ReelTune Logo
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary, width: 2),
                    color: Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/images/logo.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.music_note_rounded,
                        color: AppColors.primary,
                        size: 28,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // App Name & Statistics
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ReelTune',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                      ),
                      const Text(
                        'Version 1.0.0',
                        style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      // Stats Row
                      Wrap(
                        spacing: 8,
                        children: [
                          _buildStatChip(context, '$totalSongs Songs'),
                          _buildStatChip(context, '$totalAlbums Albums'),
                          _buildStatChip(context, storageUsed),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Drawer Navigation Items Scroll
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildCategoryHeader(context, 'LIBRARY & PLAYBACK'),
                _buildDrawerItem(
                  context,
                  icon: Icons.home_rounded,
                  title: 'Home',
                  isSelected: currentIndex == 0,
                  onTap: () {
                    ref.read(navigationIndexProvider.notifier).state = 0;
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.search_rounded,
                  title: 'Search',
                  isSelected: currentIndex == 1,
                  onTap: () {
                    ref.read(navigationIndexProvider.notifier).state = 1;
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.history_rounded,
                  title: 'Recent Songs',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const RecentSongsScreen()),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.favorite_rounded,
                  title: 'Favorites',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.album_rounded,
                  title: 'Albums',
                  isSelected: currentIndex == 3 && selectedLibTab == 0,
                  onTap: () {
                    ref.read(navigationIndexProvider.notifier).state = 3;
                    ref.read(libraryTabProvider.notifier).state = 0;
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.playlist_play_rounded,
                  title: 'Playlists',
                  isSelected: currentIndex == 3 && selectedLibTab == 1,
                  onTap: () {
                    ref.read(navigationIndexProvider.notifier).state = 3;
                    ref.read(libraryTabProvider.notifier).state = 1;
                    Navigator.pop(context);
                  },
                ),

                _buildCategoryHeader(context, 'MUSIC CATEGORIES'),
                _buildDrawerItem(
                  context,
                  icon: Icons.folder_shared_rounded,
                  title: 'Imported Songs',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FilteredClipsScreen(
                          title: 'Imported Songs',
                          filter: 'imported',
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.download_for_offline_rounded,
                  title: 'Downloaded Songs',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FilteredClipsScreen(
                          title: 'Downloaded Songs',
                          filter: 'downloaded',
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.more_time_rounded,
                  title: 'Recently Added',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FilteredClipsScreen(
                          title: 'Recently Added',
                          filter: 'recently_added',
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.star_rounded,
                  title: 'Most Played',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FilteredClipsScreen(
                          title: 'Most Played',
                          filter: 'most_played',
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.view_list_rounded,
                  title: 'History',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FilteredClipsScreen(
                          title: 'History',
                          filter: 'history',
                        ),
                      ),
                    );
                  },
                ),

                _buildCategoryHeader(context, 'APPLICATION'),
                _buildDrawerItem(
                  context,
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  isSelected: currentIndex == 4,
                  onTap: () {
                    ref.read(navigationIndexProvider.notifier).state = 4;
                    Navigator.pop(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.feedback_rounded,
                  title: 'Send Feedback',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FeedbackScreen()),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.rate_review_rounded,
                  title: 'Rate App',
                  onTap: () {
                    Navigator.pop(context);
                    _showMockRateDialog(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.share_rounded,
                  title: 'Share App',
                  onTap: () {
                    Navigator.pop(context);
                    _shareApp(context);
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.info_rounded,
                  title: 'About ReelTune',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StaticContentScreen(
                          title: 'About ReelTune',
                          type: 'about',
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.privacy_tip_rounded,
                  title: 'Privacy Policy',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StaticContentScreen(
                          title: 'Privacy Policy',
                          type: 'privacy',
                        ),
                      ),
                    );
                  },
                ),
                _buildDrawerItem(
                  context,
                  icon: Icons.description_rounded,
                  title: 'Terms of Service',
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StaticContentScreen(
                          title: 'Terms of Service',
                          type: 'terms',
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.08) : AppColors.gray100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
        ),
      ),
    );
  }
}

// --- Custom Bottom Navigation Bar Item ---
class _CustomBottomNavigationBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTabSelected;
  final VoidCallback onFABPressed;

  const _CustomBottomNavigationBar({
    required this.currentIndex,
    required this.onTabSelected,
    required this.onFABPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? AppColors.darkSurface : Colors.white;
    final borderDividerColor = isDark ? AppColors.darkBorder : AppColors.surfaceBorder;

    return Container(
      height: 76,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderDividerColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _NavBarItem(
              icon: Icons.home_rounded,
              label: 'Home',
              isActive: currentIndex == 0,
              onTap: () => onTabSelected(0),
            ),
            _NavBarItem(
              icon: Icons.search_rounded,
              label: 'Search',
              isActive: currentIndex == 1,
              onTap: () => onTabSelected(1),
            ),
            
            // Center Floating Action Button (+ button)
            GestureDetector(
              onTap: onFABPressed,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),

            _NavBarItem(
              icon: Icons.library_music_rounded,
              label: 'Library',
              isActive: currentIndex == 3,
              onTap: () => onTabSelected(3),
            ),
            _NavBarItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              isActive: currentIndex == 4,
              onTap: () => onTabSelected(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primary;
    final inactiveColor = isDark ? AppColors.darkSubtitle : AppColors.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: isActive ? activeColor : inactiveColor,
            size: 24,
          ).animate(target: isActive ? 1.0 : 0.0).scale(
                begin: const Offset(1, 1),
                end: const Offset(1.15, 1.15),
                duration: 200.ms,
              ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : inactiveColor,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddLinkBottomSheet extends ConsumerStatefulWidget {
  const _AddLinkBottomSheet();

  @override
  ConsumerState<_AddLinkBottomSheet> createState() => _AddLinkBottomSheetState();
}

class _AddLinkBottomSheetState extends ConsumerState<_AddLinkBottomSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleAnalyze() {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a link first')),
      );
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL (starting with http/https)')),
      );
      return;
    }

    _controller.clear();
    Navigator.of(context).pop(); // Close current link input sheet

    final platform = ExtractionService.detectPlatform(url);
    ref.read(extractionFlowProvider.notifier).startExtraction(
          url: url,
          platform: platform,
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      builder: (_) => const ExtractionBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkCard : AppColors.surfaceCard;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.surfaceBorder;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        left: 24,
        right: 24,
        top: 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Save Reel Sound',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Paste a social media video link to extract and save audio.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.link_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                    decoration: InputDecoration(
                      hintText: 'Paste Reel, Short or TikTok link...',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                      hintStyle: TextStyle(
                        color: isDark ? AppColors.darkSubtitle.withValues(alpha: 0.6) : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _handleAnalyze,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Analyze and Extract',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
