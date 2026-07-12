import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import 'playlist_import_provider.dart';
import '../home/main_navigation_screen.dart';

class PlaylistImportScreen extends ConsumerStatefulWidget {
  final String platform;
  const PlaylistImportScreen({super.key, required this.platform});

  @override
  ConsumerState<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends ConsumerState<PlaylistImportScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String _cleanUrl(String text) {
    final exp = RegExp(r'(https?://[^\s]+)');
    final match = exp.firstMatch(text);
    if (match != null) {
      return match.group(0)!;
    }
    return text;
  }

  void _startImport() {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) return;

    final url = _cleanUrl(rawUrl);
    final lowerUrl = url.toLowerCase();
    bool isValid = false;

    switch (widget.platform) {
      case 'spotify':
        isValid = lowerUrl.contains('spotify.com') || lowerUrl.contains('spotify.link') || lowerUrl.contains('open.spotify');
        break;
      case 'youtube':
        isValid = lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be') || lowerUrl.contains('music.youtube.com');
        break;
      case 'apple':
        isValid = lowerUrl.contains('apple.com') || lowerUrl.contains('music.apple.com');
        break;
      case 'jiosaavn':
        isValid = lowerUrl.contains('jiosaavn.com') || lowerUrl.contains('jiosaav.in');
        break;
      case 'm3u':
        isValid = lowerUrl.endsWith('.m3u') || lowerUrl.endsWith('.m3u8') || lowerUrl.contains('/m3u') || lowerUrl.contains('.m3u') || lowerUrl.contains('.m3u8');
        break;
    }

    if (!isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL for the selected platform.')),
      );
      return;
    }

    ref.read(playlistImportProvider.notifier).fetchAndResolvePlaylist(url, widget.platform);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final importState = ref.watch(playlistImportProvider);

    String screenTitle = 'Import Playlist';
    String hintText = 'Paste playlist or album URL...';

    switch (widget.platform) {
      case 'spotify':
        screenTitle = 'Import Spotify';
        hintText = 'Paste Spotify URL...';
        break;
      case 'youtube':
        screenTitle = 'Import YouTube';
        hintText = 'Paste YouTube URL...';
        break;
      case 'apple':
        screenTitle = 'Import Apple Music';
        hintText = 'Paste Apple Music URL...';
        break;
      case 'jiosaavn':
        screenTitle = 'Import JioSaavn';
        hintText = 'Paste JioSaavn URL...';
        break;
      case 'm3u':
        screenTitle = 'Import M3U Playlist';
        hintText = 'Paste M3U URL...';
        break;
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(playlistImportProvider.notifier).cancel();
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.cream,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          iconTheme: IconThemeData(color: isDark ? Colors.white : AppColors.textPrimary),
          title: Text(
            screenTitle,
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildBody(isDark, hintText, importState),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark, String hintText, PlaylistImportState state) {
    switch (state.phase) {
      case ImportPhase.idle:
        return _buildInputScreen(isDark, hintText);
      case ImportPhase.fetchingMetadata:
        return _buildLoadingScreen(isDark, 'Fetching playlist metadata and tracks...');
      case ImportPhase.resolving:
        return _buildResolvingScreen(isDark, state);
      case ImportPhase.review:
        return _buildReviewScreen(isDark, state);
      case ImportPhase.saving:
        return _buildLoadingScreen(isDark, 'Downloading and saving tracks to local library...');
      case ImportPhase.completed:
        return _buildCompletedScreen(isDark, state);
      case ImportPhase.error:
        return _buildErrorScreen(isDark, state);
    }
  }

  Widget _buildInputScreen(bool isDark, String hintText) {
    return SingleChildScrollView(
      key: const ValueKey('idle_input'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.link_rounded, color: AppColors.primary, size: 48),
          ),
          const SizedBox(height: 32),
          const Text(
            'Paste playlist or album link from supported platform to scan and fetch tracks.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 40),
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
              ),
            ),
            child: TextField(
              controller: _urlController,
              textInputAction: TextInputAction.go,
              autofocus: true,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(
                  color: isDark
                      ? AppColors.darkSubtitle.withValues(alpha: 0.4)
                      : AppColors.textTertiary.withValues(alpha: 0.5),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                prefixIcon: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(Icons.search_rounded, color: AppColors.primary, size: 20),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _urlController,
                  builder: (_, v, __) => v.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(
                          icon: Icon(Icons.cancel, size: 20, color: isDark ? Colors.white60 : Colors.black54),
                          onPressed: _urlController.clear,
                        ),
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
              onSubmitted: (_) => _startImport(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _startImport,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text(
              'Import playlist',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingScreen(bool isDark, String message) {
    return Center(
      key: const ValueKey('loading_view'),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResolvingScreen(bool isDark, PlaylistImportState state) {
    final totalCount = state.tracks.length;
    final resolvedCount = state.resolvedCount;
    final failedCount = state.failedCount;
    final progress = totalCount > 0 ? (resolvedCount + failedCount) / totalCount : 0.0;

    return Column(
      key: const ValueKey('resolving_view'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: (state.playlistCoverUrl != null && state.playlistCoverUrl!.isNotEmpty)
                            ? Image.network(state.playlistCoverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _playlistPlaceholder())
                            : _playlistPlaceholder(),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.playlistTitle ?? 'Importing Playlist',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Resolving links: ${resolvedCount + failedCount} / $totalCount',
                            style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: progress,
                  backgroundColor: isDark ? Colors.white10 : AppColors.surfaceBorder,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  minHeight: 6,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Resolved: $resolvedCount', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.bold)),
                    Text('Failed: $failedCount', style: TextStyle(fontSize: 12, color: failedCount > 0 ? AppColors.error : AppColors.textTertiary, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: state.tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = state.tracks[index];
              return _buildTrackListTile(isDark, track, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReviewScreen(bool isDark, PlaylistImportState state) {
    return Column(
      key: const ValueKey('review_view'),
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Review Playlist Import',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Total tracks: ${state.tracks.length}  •  Succeeded: ${state.resolvedCount}  •  Failed: ${state.failedCount}',
                  style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          ref.read(playlistImportProvider.notifier).reset();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: state.resolvedCount > 0
                            ? () => ref.read(playlistImportProvider.notifier).savePlaylistToLibrary()
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Import to Library', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: state.tracks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final track = state.tracks[index];
              return _buildTrackListTile(isDark, track, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedScreen(bool isDark, PlaylistImportState state) {
    return Center(
      key: const ValueKey('completed_view'),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, color: AppColors.primary, size: 64),
            const SizedBox(height: 24),
            Text(
              'Successfully Imported! 🎉',
              style: TextStyle(
                color: isDark ? Colors.white : AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Saved ${state.resolvedCount} tracks to your playlist library.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                // Navigate to library or close
                ref.read(navigationIndexProvider.notifier).state = 2; // Library tab
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Go to Library', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorScreen(bool isDark, PlaylistImportState state) {
    return Center(
      key: const ValueKey('error_view'),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 54),
            const SizedBox(height: 24),
            Text(
              state.errorMessage ?? 'An error occurred during import.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark ? Colors.white70 : AppColors.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () {
                ref.read(playlistImportProvider.notifier).reset();
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Try Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackListTile(bool isDark, TrackImportEntry track, int index) {
    Widget trailingWidget;
    switch (track.status) {
      case TrackImportStatus.pending:
        trailingWidget = const Icon(Icons.hourglass_empty_rounded, color: Colors.grey, size: 20);
        break;
      case TrackImportStatus.resolving:
        trailingWidget = const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
        );
        break;
      case TrackImportStatus.resolved:
        trailingWidget = const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 22);
        break;
      case TrackImportStatus.failed:
        trailingWidget = const Icon(Icons.error_rounded, color: AppColors.error, size: 22);
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder.withValues(alpha: 0.3) : AppColors.surfaceBorder.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
          radius: 16,
          child: Text(
            '${index + 1}',
            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        title: Text(
          track.title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.artist,
              style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (track.status == TrackImportStatus.failed && track.error != null) ...[
              const SizedBox(height: 2),
              Text(
                track.error!,
                style: const TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]
          ],
        ),
        trailing: trailingWidget,
      ),
    );
  }

  Widget _playlistPlaceholder() => Container(
        color: AppColors.primary.withValues(alpha: 0.1),
        child: const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 32),
      );
}
