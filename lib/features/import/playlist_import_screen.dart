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

  Future<void> _fetchMetadata() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final lowerUrl = url.toLowerCase();
    bool isValid = false;

    switch (widget.platform) {
      case 'spotify':
        isValid = lowerUrl.contains('spotify.com');
        break;
      case 'youtube':
        isValid = lowerUrl.contains('youtube.com') || lowerUrl.contains('youtu.be');
        break;
      case 'apple':
        isValid = lowerUrl.contains('apple.com');
        break;
      case 'jiosaavn':
        isValid = lowerUrl.contains('jiosaavn');
        break;
      case 'm3u':
        isValid = lowerUrl.endsWith('.m3u') || lowerUrl.endsWith('.m3u8') || lowerUrl.contains('/m3u');
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
    if (_playlistTitle == null) return;

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
      int attempts = 0;
      while (attempts < 40) {
        attempts++;
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
          if (attempts >= 40) {
            rethrow;
          }
          debugPrint('[Import-Poll] Transient polling error (attempt $attempts): $e');
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
    } catch (e, stack) {
      debugPrintStack(stackTrace: stack, label: 'Error in _downloadTrack');
      setState(() {
        _downloadStates[index] = 'error';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to download "${track['title']}": $e')),
      );
    }
  }

  Future<void> _downloadAll() async {
    if (_createdPlaylist == null) {
      await _importPlaylistStructure();
    }
    if (_createdPlaylist == null) return;

    for (int i = 0; i < _tracks.length; i++) {
      if (_downloadStates[i] == 'idle' || _downloadStates[i] == 'error') {
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
        hintText = 'Paste Spotify playlist or album URL...';
        break;
      case 'youtube':
        screenTitle = 'Import YouTube Music';
        hintText = 'Paste YouTube/YT Music playlist URL...';
        break;
      case 'apple':
        screenTitle = 'Import Apple Music';
        hintText = 'Paste Apple Music playlist URL...';
        break;
      case 'jiosaavn':
        screenTitle = 'Import JioSaavn';
        hintText = 'Paste JioSaavn playlist URL...';
        break;
      case 'm3u':
        screenTitle = 'Import M3U Playlist';
        hintText = 'Paste M3U playlist file URL...';
        break;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.getAdaptiveBackgroundGradient(context),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                
                // URL input bar
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        style: TextStyle(color: isDark ? Colors.white : AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: hintText,
                          prefixIcon: const Icon(Icons.link_rounded, color: AppColors.primary),
                          filled: true,
                          fillColor: isDark ? AppColors.darkCard : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.search_rounded, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: _isLoading ? null : _fetchMetadata,
                    ),
                  ],
                ),
                
                const SizedBox(height: 16),
                
                if (_isLoading)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: AppColors.primary),
                          SizedBox(height: 16),
                          Text('Fetching playlist info and entries...'),
                        ],
                      ),
                    ),
                  )
                else if (_error != null)
                  Expanded(
                    child: Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  )
                else if (_playlistTitle != null) ...[
                  // Playlist Metadata Top Card
                  Card(
                    color: isDark ? AppColors.darkCard : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_playlistCoverUrl != null && _playlistCoverUrl!.isNotEmpty)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                _playlistCoverUrl!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 80,
                                  height: 80,
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  child: const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 40),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 40),
                            ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _playlistTitle!,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_playlistDesc != null && _playlistDesc!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    _playlistDesc!,
                                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton(
                                      onPressed: _createdPlaylist == null ? _importPlaylistStructure : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                        foregroundColor: AppColors.primary,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      ),
                                      child: Text(_createdPlaylist != null ? 'Imported ✔' : 'Import Structure'),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton.icon(
                                      onPressed: _downloadAll,
                                      icon: const Icon(Icons.download_rounded, size: 16),
                                      label: const Text('Download All'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  const SizedBox(height: 16),
                  
                  // Tracks List
                  Expanded(
                    child: ListView.builder(
                      itemCount: _tracks.length,
                      itemBuilder: (context, index) {
                        final track = _tracks[index];
                        final state = _downloadStates[index] ?? 'idle';
                        final progress = _downloadProgress[index] ?? 0.0;

                        return Card(
                          color: isDark ? AppColors.darkCard : Colors.white,
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.surfaceBorder),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                              child: Text('${index + 1}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(track['title'] ?? 'Unknown Title', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(track['artist'] ?? 'Unknown Artist'),
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
                ] else
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Paste a Spotify/YouTube playlist URL above to scan and fetch tracks.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
