import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../albums/albums_screen.dart'; // We'll keep this as LibraryScreen or Home
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../player/mini_player.dart';
import '../share_intent/widgets/extraction_bottom_sheet.dart';
import '../share_intent/share_intent_provider.dart';
import '../../core/network/extraction_service.dart';
import '../../core/ads/BannerAdWidget.dart';
import '../../core/ads/InterstitialService.dart';
import 'home_screen.dart';

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;

  void _onTabSelected(int index) {
    setState(() {
      _currentIndex = index;
    });
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
    final showBanner = _currentIndex != 4 && !isAdFree;

    // List of screens for navigation
    final List<Widget> screens = [
      HomeScreen(onNavigateToSearch: () => _onTabSelected(1), onNavigateToLibrary: () => _onTabSelected(2)),
      const SearchScreen(isTab: true),
      const SizedBox.shrink(), // Center button spacer
      const AlbumsScreen(isLibrary: true),
      const SettingsScreen(isTab: true),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.cream,
      body: Stack(
        children: [
          // Sub-screen rendering
          IndexedStack(
            index: _currentIndex == 2 ? 0 : _currentIndex, // Avoid indexing the placeholder
            children: [
              screens[0],
              screens[1],
              screens[3],
              screens[4],
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
              currentIndex: _currentIndex,
              onTabSelected: _onTabSelected,
              onFABPressed: _showAddClipSheet,
            ),
          ),
        ],
      ),
    );
  }
}

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
