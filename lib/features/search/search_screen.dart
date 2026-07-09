import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/theme/app_colors.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/clip.dart';
import '../player/player_provider.dart';
import '../player/mini_player.dart';
import '../player/full_player_screen.dart';

import '../../core/ads/NativeAdWidget.dart';
import '../../core/ads/InterstitialService.dart';

// --- Search provider ---
final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<List<Clip>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];
  return ref.watch(clipRepositoryProvider).searchClips(query);
});

class SearchScreen extends ConsumerStatefulWidget {
  final bool isTab;

  const SearchScreen({
    super.key,
    this.isTab = false,
  });

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(searchResultsProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        if (!widget.isTab)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_rounded),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            autofocus: true,
                            onChanged: _onSearchChanged,
                            style: Theme.of(context).textTheme.bodyLarge,
                            decoration: InputDecoration(
                              hintText: 'Search clips...',
                              prefixIcon: const Icon(Icons.search_rounded,
                                  color: AppColors.textTertiary),
                              suffixIcon: query.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          size: 18),
                                      onPressed: () {
                                        _controller.clear();
                                        ref
                                            .read(searchQueryProvider.notifier)
                                            .state = '';
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 300.ms),

                  // Results
                  Expanded(
                    child: query.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  color: AppColors.textTertiary,
                                  size: 48,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Search your clips',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          )
                        : resultsAsync.when(
                            data: (clips) {
                              if (clips.isEmpty) {
                                return Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.music_off_rounded,
                                        color: AppColors.textTertiary,
                                        size: 48,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No matching songs or albums found.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium,
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final isAdFree = ref.watch(adFreeProvider);
                              final int adInterval = 8;
                              final int adCount = isAdFree ? 0 : clips.length ~/ adInterval;
                              final int totalCount = clips.length + adCount;

                              return ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                itemCount: totalCount,
                                itemBuilder: (context, index) {
                                  if (!isAdFree && (index + 1) % (adInterval + 1) == 0) {
                                    return const NativeAdWidget();
                                  }
                                  final adOffset = isAdFree ? 0 : index ~/ (adInterval + 1);
                                  final clipIndex = index - adOffset;
                                  final clip = clips[clipIndex];
                                  return _SearchResultTile(
                                    clip: clip,
                                    index: clipIndex,
                                    onTap: () {
                                      ref
                                          .read(playerProvider.notifier)
                                          .playClip(clip);
                                    },
                                  );
                                },
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(
                                color: AppColors.primary,
                              ),
                            ),
                            error: (_, __) => const Center(
                              child: Text('Search failed'),
                            ),
                          ),
                  ),
                ],
              ),

              // Mini player
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Clip clip;
  final int index;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.clip,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.getAdaptiveSurfaceCard(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.getAdaptiveSurfaceBorder(context)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    clip.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppColors.textPrimary,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    clip.artist != null && clip.artist!.isNotEmpty && clip.artist != 'Unknown Artist'
                        ? '${clip.artist} • ${clip.platformIcon} ${clip.formattedDuration}'
                        : '${clip.platformIcon} ${clip.formattedDuration}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 50 * (index > 8 ? 8 : index)),
          duration: 300.ms,
        )
        .slideX(begin: 0.03, duration: 300.ms);
  }
}
