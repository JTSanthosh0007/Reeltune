import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/network/extraction_service.dart';
import '../../core/models/playlist.dart';
import '../../core/models/queue_item.dart';
import '../library/PlaylistsProvider.dart';
import '../queue/queue_provider.dart';
import '../home/main_navigation_screen.dart';

class PlaylistImportScreen extends ConsumerStatefulWidget {
  final String platform;
  const PlaylistImportScreen({super.key, required this.platform});

  @override
  ConsumerState<PlaylistImportScreen> createState() => _PlaylistImportScreenState();
}

class _PlaylistImportScreenState extends ConsumerState<PlaylistImportScreen> {
  final _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  
  String? _playlistTitle;
  String? _playlistDesc;
  String? _playlistCoverUrl;
  List<Map<String, dynamic>> _tracks = [];
  Playlist? _createdPlaylist;

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

  Future<void> _fetchMetadata() async {
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
      setState(() {
        _error = 'Please enter a valid URL for the selected platform.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _playlistTitle = null;
      _tracks = [];
      _createdPlaylist = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post<Map<String, dynamic>>(
        '/api/playlist/metadata',
        data: {'url': url},
      );

      final data = response.data;
      if (data == null) {
        throw Exception('Invalid response from backend');
      }

      setState(() {
        _playlistTitle = data['title'] as String?;
        _playlistDesc = data['description'] as String?;
        _playlistCoverUrl = data['coverUrl'] as String?;
        final rawTracks = data['tracks'] as List<dynamic>? ?? [];
        _tracks = rawTracks.map((t) => Map<String, dynamic>.from(t)).toList();
      });

      // Automatically create playlist structure & start queue downloads
      final playlist = await _importPlaylistStructure();
      if (playlist != null) {
        final queueNotifier = ref.read(queueProvider.notifier);
        for (final track in _tracks) {
          queueNotifier.addToQueue(
            url: track['url'] as String,
            platform: widget.platform,
            title: track['title'] as String?,
            artist: track['artist'] as String?,
            playlistId: playlist.id,
          );
        }
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e, stack) {
      debugPrintStack(stackTrace: stack, label: 'Error in _fetchMetadata');
      String errMsg = 'Failed to fetch playlist metadata: $e';
      if (e is ApiException) {
        errMsg = e.message;
      } else if (e is DioException) {
        errMsg = e.message ?? 'Network error';
      }
      setState(() {
        _error = errMsg;
        _isLoading = false;
      });
    }
  }

  Future<Playlist?> _importPlaylistStructure() async {
    if (_playlistTitle == null || _tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot import an empty playlist.')),
      );
      return null;
    }

    try {
      final playlist = await ref.read(playlistsProvider.notifier).createPlaylist(
            _playlistTitle!,
            description: _playlistDesc,
          );
      
      setState(() {
        _createdPlaylist = playlist;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created playlist "${playlist?.name ?? _playlistTitle}" successfully!')),
      );
      return playlist;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create playlist: $e')),
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queueItems = ref.watch(queueProvider);

    String screenTitle = 'Import Playlist';
    String hintText = 'Paste playlist or album URL...';

    switch (widget.platform) {
      case 'spotify':
        screenTitle = 'Import Spotify';
        hintText = 'Paste Spotify URL...';
        break;
      case 'youtube':
        screenTitle = 'Import YouTube Music';
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

    return Scaffold(
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
            child: _buildContent(isDark, hintText, queueItems),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, String hintText, List<QueueItem> queueItems) {
    if (_isLoading) {
      return Center(
        key: const ValueKey('loading'),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 3),
              const SizedBox(height: 24),
              Text(
                'Fetching playlist metadata and tracks...',
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

    if (_error != null) {
      return Center(
        key: const ValueKey('error'),
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
              const SizedBox(height: 24),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white70 : AppColors.textSecondary,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _error = null;
                  });
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Try Again', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      );
    }

    if (_playlistTitle != null) {
      // Calculate download statistics
      final playlistQueue = queueItems.where((i) => i.playlistId == _createdPlaylist?.id).toList();
      final completedCount = playlistQueue.where((i) => i.status == 'completed').length;
      final failedCount = playlistQueue.where((i) => i.status == 'failed').length;
      final activeItems = playlistQueue.where((i) => i.status == 'downloading').toList();
      final overallProgress = playlistQueue.isEmpty ? 0.0 : completedCount / playlistQueue.length;
      
      final totalSpeedKB = activeItems.fold<double>(0.0, (sum, i) => sum + i.speed);
      final overallETA = activeItems.isEmpty ? 0 : activeItems.map((i) => i.eta).reduce((a, b) => a > b ? a : b);
      
      final speedText = totalSpeedKB >= 1024
          ? '${(totalSpeedKB / 1024).toStringAsFixed(1)} MB/s'
          : '${totalSpeedKB.toStringAsFixed(0)} KB/s';

      final currentSong = activeItems.isNotEmpty ? activeItems.first.title ?? '' : '';

      return Column(
        key: const ValueKey('playlist_view'),
        children: [
          // Playlist Card (stats container)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder.withValues(alpha: 0.5) : AppColors.surfaceBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: (_playlistCoverUrl != null && _playlistCoverUrl!.isNotEmpty)
                                ? Image.network(
                                    _playlistCoverUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _playlistPlaceholder(),
                                  )
                                : _playlistPlaceholder(),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _playlistTitle!,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Importing tracks: $completedCount/${playlistQueue.length}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                                ),
                              ),
                              if (failedCount > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Failed downloads: $failedCount',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Overall progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: overallProgress,
                        backgroundColor: isDark ? Colors.white10 : AppColors.surfaceBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        minHeight: 8.0,
                      ),
                    ),
                    
                    if (activeItems.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Downloading: $currentSong',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '$speedText • ETA ${overallETA}s',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              ref.read(navigationIndexProvider.notifier).state = 1;
                              Navigator.pop(context);
                            },
                            icon: Icon(Icons.schedule_rounded, size: 16, color: isDark ? Colors.white : AppColors.textPrimary),
                            label: Text(
                              'View Queue',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : AppColors.textPrimary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: isDark
                                    ? AppColors.darkBorder.withValues(alpha: 0.5)
                                    : AppColors.surfaceBorder.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => ref.read(queueProvider.notifier).downloadAll(),
                            icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                            label: const Text(
                              'Resume All',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Tracks List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _tracks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final track = _tracks[index];
                final trackUrl = track['url'] as String;
                
                QueueItem? qItem;
                try {
                  qItem = queueItems.firstWhere((i) => i.url == trackUrl && i.playlistId == _createdPlaylist?.id);
                } catch (_) {}

                final state = qItem?.status ?? 'idle';
                final progress = qItem?.progress ?? 0.0;

                return Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.darkCard.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.darkBorder.withValues(alpha: 0.4)
                          : AppColors.surfaceBorder.withValues(alpha: 0.4),
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text(
                      track['title'] ?? 'Unknown Title',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      track['artist'] ?? 'Unknown Artist',
                      style: TextStyle(
                        color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                      ),
                    ),
                    trailing: SizedBox(
                      width: 80,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: state == 'downloading'
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: progress > 0 ? progress : null,
                                  color: AppColors.primary,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : state == 'pending'
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 1.5,
                                    ),
                                  )
                                : state == 'completed' || state == 'success'
                                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                                    : state == 'failed'
                                        ? IconButton(
                                            icon: const Icon(Icons.replay_rounded, color: AppColors.error),
                                            onPressed: () {
                                              if (qItem != null) {
                                                ref.read(queueProvider.notifier).retryDownload(qItem.id);
                                              }
                                            },
                                          )
                                        : state == 'paused'
                                            ? IconButton(
                                                icon: const Icon(Icons.play_arrow_rounded, color: AppColors.primary),
                                                onPressed: () {
                                                  if (qItem != null) {
                                                    ref.read(queueProvider.notifier).resumeDownload(qItem.id);
                                                  }
                                                },
                                              )
                                            : const Icon(Icons.download_rounded, color: AppColors.primary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    // IDLE Input Screen
    return SingleChildScrollView(
      key: const ValueKey('url_input'),
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
              onSubmitted: (_) => _fetchMetadata(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _fetchMetadata,
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

  Widget _playlistPlaceholder() => Container(
        color: AppColors.primary.withValues(alpha: 0.1),
        child: const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 40),
      );
}
