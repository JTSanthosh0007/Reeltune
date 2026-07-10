import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../../core/theme/app_colors.dart';
import '../../core/network/api_client.dart';
import '../../core/network/extraction_service.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/clip.dart';
import '../../core/models/playlist.dart';
import '../library/PlaylistsProvider.dart';
import '../notifications/notifications_provider.dart';
import '../../core/storage/file_storage_service.dart';

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

  // Track download states: 'idle', 'downloading', 'success', 'error'
  final Map<int, String> _downloadStates = {};
  final Map<int, double> _downloadProgress = {};

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
        _isLoading = false;
      });

      // Initialize states
      for (int i = 0; i < _tracks.length; i++) {
        _downloadStates[i] = 'idle';
        _downloadProgress[i] = 0.0;
      }
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

  Future<void> _importPlaylistStructure() async {
    if (_playlistTitle == null || _tracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot import an empty playlist.')),
      );
      return;
    }

    try {
      // Create local playlist
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create playlist: $e')),
      );
    }
  }

  Future<void> _downloadTrack(int index) async {
    if (_createdPlaylist == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please import playlist structure first')),
      );
      return;
    }

    final track = _tracks[index];
    setState(() {
      _downloadStates[index] = 'downloading';
      _downloadProgress[index] = 0.0;
    });

    int attempt = 0;
    const maxAttempts = 3;

    while (attempt < maxAttempts) {
      attempt++;
      try {
        final title = track['title'] as String;
        final artist = track['artist'] as String;
        final queryUrl = track['url'] as String;

        // For Spotify, queryUrl is YouTube search results page link.
        // We submit search query to backend.
        final submitUrl = queryUrl.contains('youtube.com/results')
            ? 'ytsearch:${title} ${artist}'
            : queryUrl;

        final extractionService = ref.read(extractionServiceProvider);
        
        // 1. Submit job
        final jobId = await extractionService.submitExtraction(submitUrl, quality: 'high');

        // 2. Poll job status
        String? downloadUrl;
        int pollAttempts = 0;
        while (pollAttempts < 40) {
          pollAttempts++;
          await Future.delayed(const Duration(seconds: 2));
          try {
            final statusRes = await extractionService.pollStatus(jobId);
            if (statusRes.status == ExtractionStatus.completed) {
              downloadUrl = statusRes.downloadUrl;
              break;
            } else if (statusRes.status == ExtractionStatus.failed) {
              throw Exception(statusRes.error ?? 'Extraction failed');
            }
          } catch (e) {
            if (pollAttempts >= 40) {
              rethrow;
            }
            debugPrint('[Import-Poll] Transient polling error (attempt $pollAttempts): $e');
          }
        }

        if (downloadUrl == null) {
          throw Exception('Download timeout');
        }

        // 3. Download actual MP3 file
        final fileService = ref.read(fileStorageServiceProvider);
        final localFilePath = await fileService.getClipFilePath('imported_playlist_songs', jobId);
        
        // Ensure the directory exists
        final localFile = File(localFilePath);
        if (!await localFile.parent.exists()) {
          await localFile.parent.create(recursive: true);
        }

        final dio = Dio();
        await dio.download(
          downloadUrl,
          localFilePath,
          onReceiveProgress: (received, total) {
            if (total > 0) {
              setState(() {
                _downloadProgress[index] = received / total;
              });
            }
          },
        );

        // 4. Save to local SQLite
        final clip = Clip(
          id: jobId,
          albumId: 'imported_playlist_songs', // Fallback Category
          title: title,
          filePath: localFilePath,
          durationMs: track['durationMs'] as int?,
          sourcePlatform: 'download',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          artist: artist,
          albumName: _playlistTitle,
        );

        await ref.read(clipRepositoryProvider).insertClip(clip);
        await ref.read(playlistsProvider.notifier).addClipToPlaylist(_createdPlaylist!.id, clip.id);

        setState(() {
          _downloadStates[index] = 'success';
        });

        ref.read(notificationsProvider.notifier).addNotification(
              title: 'Track Downloaded 🎵',
              body: '"$title" imported successfully.',
              type: 'import',
            );
        return; // Success, exit function
      } catch (e, stack) {
        debugPrintStack(stackTrace: stack, label: 'Error in _downloadTrack (attempt $attempt)');
        if (attempt >= maxAttempts) {
          setState(() {
            _downloadStates[index] = 'error';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download "${track['title']}" after $maxAttempts attempts: $e')),
          );
        } else {
          // Wait 3 seconds before retrying
          await Future.delayed(const Duration(seconds: 3));
        }
      }
    }
  }

  Future<void> _downloadAll() async {
    if (_createdPlaylist == null) {
      await _importPlaylistStructure();
    }
    if (_createdPlaylist == null) return;

    // Queue all downloadable songs first
    setState(() {
      for (int i = 0; i < _tracks.length; i++) {
        if (_downloadStates[i] == 'idle' || _downloadStates[i] == 'error') {
          _downloadStates[i] = 'queued';
        }
      }
    });
    for (int i = 0; i < _tracks.length; i++) {
      if (_downloadStates[i] == 'queued') {
        await _downloadTrack(i);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            child: _buildContent(isDark, hintText),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark, String hintText) {
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
                'Fetching playlist info and entries...',
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
      return Column(
        key: const ValueKey('playlist_view'),
        children: [
          // Playlist Card (styled like Bloomee)
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 80,
                        height: 80,
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (_playlistDesc != null && _playlistDesc!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              _playlistDesc!,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? AppColors.darkSubtitle : AppColors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _createdPlaylist == null ? _importPlaylistStructure : null,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: isDark
                                          ? AppColors.darkBorder.withValues(alpha: 0.5)
                                          : AppColors.surfaceBorder.withValues(alpha: 0.5),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: Text(
                                    _createdPlaylist != null ? 'Imported ✔' : 'Import structure',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? Colors.white : AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _downloadAll,
                                  icon: const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                                  label: const Text(
                                    'Download All',
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
                  ],
                ),
              ),
            ),
          ),
          
          // Tracks List (styled like Bloomee)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _tracks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final track = _tracks[index];
                final state = _downloadStates[index] ?? 'idle';
                final progress = _downloadProgress[index] ?? 0.0;

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
                            : state == 'queued'
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 1.5,
                                    ),
                                  )
                                : state == 'success'
                                    ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
                                    : state == 'error'
                                        ? const Icon(Icons.error_outline_rounded, color: AppColors.error)
                                        : IconButton(
                                            icon: const Icon(Icons.download_rounded, color: AppColors.primary),
                                            onPressed: () => _downloadTrack(index),
                                          ),
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

    // Default: IDLE Input Screen (identical to Bloomee input view)
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
