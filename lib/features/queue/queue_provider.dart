import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/db/clip_repository.dart';
import '../../core/db/queue_repository.dart';
import '../../core/models/clip.dart';
import '../../core/models/queue_item.dart';
import '../../core/network/api_client.dart';
import '../../core/network/extraction_service.dart';
import '../../core/storage/file_storage_service.dart';
import '../library/PlaylistRepository.dart';
import '../library/PlaylistsProvider.dart';
import '../share_intent/share_overlay_bridge.dart';
import '../albums/album_providers.dart';

final queueProvider = StateNotifierProvider<QueueNotifier, List<QueueItem>>((ref) {
  final repository = ref.watch(queueRepositoryProvider);
  final extractionService = ref.watch(extractionServiceProvider);
  final fileStorageService = ref.watch(fileStorageServiceProvider);
  final clipRepository = ref.watch(clipRepositoryProvider);
  final playlistRepository = ref.watch(playlistRepositoryProvider);
  final apiClient = ref.watch(apiClientProvider);
  return QueueNotifier(
    repository,
    extractionService,
    fileStorageService,
    clipRepository,
    playlistRepository,
    apiClient,
    ref,
  );
});

class QueueNotifier extends StateNotifier<List<QueueItem>> {
  final QueueRepository _repository;
  final ExtractionService _extractionService;
  final FileStorageService _fileStorageService;
  final ClipRepository _clipRepository;
  final PlaylistRepository _playlistRepository;
  final ApiClient _apiClient;
  final Ref _ref;
  
  final Set<String> _activeJobs = {};
  final Map<String, DateTime> _lastDbWriteTime = {};
  static const _uuid = Uuid();
  bool _serverWarm = false;

  // Max concurrent downloads
  static const _maxConcurrent = 3;

  QueueNotifier(
    this._repository,
    this._extractionService,
    this._fileStorageService,
    this._clipRepository,
    this._playlistRepository,
    this._apiClient,
    this._ref,
  ) : super([]) {
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    try {
      final items = await _repository.getAllQueueItems();
      // Auto-resume or reset downloading items back to pending on startup
      final resetItems = items.map((item) {
        if (item.status == 'downloading' || item.status == 'connecting' || item.status == 'extracting') {
          _repository.updateStatusProgressSpeedEtaRetries(
            item.id,
            'pending',
            0.0,
            0.0,
            0,
            item.retries,
          );
          return item.copyWith(status: 'pending', progress: 0.0, speed: 0.0, eta: 0);
        }
        return item;
      }).toList();

      // Preserve any items that were already added to state in memory before _loadQueue finished!
      final existingIds = resetItems.map((i) => i.id).toSet();
      final inMemoryNewItems = state.where((item) => !existingIds.contains(item.id)).toList();

      state = [...inMemoryNewItems, ...resetItems];
      _syncNativeOverlayBadge();
      _processNext();
    } catch (e) {
      debugPrint('[Queue] Error loading queue: $e');
    }
  }

  void _syncNativeOverlayBadge() {
    try {
      final pendingCount = state.where((item) => 
        item.status == 'queued' || 
        item.status == 'pending' || 
        item.status == 'preparing' || 
        item.status == 'fetching_metadata' || 
        item.status == 'extracting_audio' || 
        item.status == 'generating_download_link' || 
        item.status == 'downloading' || 
        item.status == 'saving'
      ).length;
      if (pendingCount == 0) {
        ShareOverlayBridge.dismissBubble();
      } else {
        ShareOverlayBridge.updateBubbleBadge(pendingCount);
      }
    } catch (e) {
      debugPrint('[Queue] Error syncing native overlay badge: $e');
    }
  }

  Future<void> addToQueue({
    required String url,
    required String platform,
    String? title,
    String? artist,
    int priority = 0,
    String? playlistId,
    String? albumId,
  }) async {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return;

    // Avoid adding exact duplicate active URLs
    final hasDuplicate = state.any((item) =>
        item.url == cleanUrl &&
        (item.status == 'queued' ||
            item.status == 'pending' ||
            item.status == 'preparing' ||
            item.status == 'fetching_metadata' ||
            item.status == 'extracting_audio' ||
            item.status == 'generating_download_link' ||
            item.status == 'downloading' ||
            item.status == 'saving' ||
            item.status == 'paused'));
    if (hasDuplicate) {
      debugPrint('[Queue] Duplicate active URL skipped: $cleanUrl');
      return;
    }

    // Check if already downloaded
    final alreadyCompleted = state.any((item) =>
        item.url == cleanUrl && item.status == 'completed');
    if (alreadyCompleted) {
      debugPrint('[Queue] URL already downloaded: $cleanUrl');
      return;
    }

    final id = _uuid.v4();
    final item = QueueItem(
      id: id,
      url: cleanUrl,
      title: title ?? 'Loading metadata...',
      artist: artist ?? 'Please wait...',
      platform: platform,
      status: 'queued',
      progress: 0.0,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      priority: priority,
      speed: 0.0,
      eta: 0,
      retries: 0,
      playlistId: playlistId,
      albumId: albumId,
    );

    await _repository.insertQueueItem(item);
    state = [item, ...state];
    _syncNativeOverlayBadge();
    _processNext();
  }

  String _defaultTitle(String url, String platform) {
    try {
      final parsed = Uri.parse(url);
      final segment = parsed.pathSegments.isNotEmpty ? parsed.pathSegments.last : '';
      if (segment.isNotEmpty && segment.length < 50) return '$platform-$segment';
    } catch (_) {}
    return 'Shared $platform Audio';
  }

  void _updateItemMetadata(String id, String title, String artist, String thumbnail, int duration) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(
          title: title,
          artist: artist,
          thumbnail: thumbnail,
          duration: duration,
        );
      }
      return item;
    }).toList();

    try {
      _repository.updateMetadata(id, title, artist, thumbnail, duration);
    } catch (e) {
      debugPrint('[Queue] Error updating item metadata in DB: $e');
    }
  }

  void _updateItemState(String id, String status, double progress, {String? error}) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(
          status: status,
          progress: progress,
          error: error,
          speed: 0.0,
          eta: 0,
        );
      }
      return item;
    }).toList();
    
    try {
      final currentItem = state.firstWhere((i) => i.id == id);
      _repository.updateStatusProgressSpeedEtaRetries(
        id,
        status,
        progress,
        0.0,
        0,
        currentItem.retries,
        error: error,
      );
    } catch (e) {
      debugPrint('[Queue] Error updating item state: $e');
    }
    _syncNativeOverlayBadge();
  }

  void _updateItemStateMetrics(
    String id,
    String status,
    double progress,
    double speed,
    int eta,
    int retries, {
    String? error,
  }) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(
          status: status,
          progress: progress,
          speed: speed,
          eta: eta,
          retries: retries,
          error: error,
        );
      }
      return item;
    }).toList();
    _repository.updateStatusProgressSpeedEtaRetries(
      id,
      status,
      progress,
      speed,
      decayEta(eta),
      retries,
      error: error,
    );
    _syncNativeOverlayBadge();
  }

  int decayEta(int rawEta) {
    return rawEta < 0 ? 0 : rawEta;
  }

  void _updateItemProgressMetrics(String id, double progress, double speed, int eta) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(
          progress: progress,
          speed: speed,
          eta: eta,
        );
      }
      return item;
    }).toList();

    final lastWrite = _lastDbWriteTime[id];
    final now = DateTime.now();
    if (lastWrite == null || now.difference(lastWrite).inMilliseconds >= 1000) {
      _lastDbWriteTime[id] = now;
      try {
        final currentItem = state.firstWhere((i) => i.id == id);
        _repository.updateStatusProgressSpeedEtaRetries(
          id,
          currentItem.status,
          progress,
          speed,
          eta,
          currentItem.retries,
        );
      } catch (e) {
        debugPrint('[Queue] Error writing progress: $e');
      }
    }
  }

  Future<void> pauseDownload(String id) async {
    _activeJobs.remove(id);
    _updateItemState(id, 'paused', 0.0);
    _processNext();
  }

  Future<void> resumeDownload(String id) async {
    _updateItemState(id, 'pending', 0.0);
    _processNext();
  }

  Future<void> cancelDownload(String id) async {
    _activeJobs.remove(id);
    await _repository.deleteQueueItem(id);
    state = state.where((item) => item.id != id).toList();
    _syncNativeOverlayBadge();
    _processNext();
  }

  Future<void> retryDownload(String id) async {
    // Reset retries to 0 on manual retry request
    _updateItemStateMetrics(id, 'pending', 0.0, 0.0, 0, 0);
    _processNext();
  }

  Future<void> clearCompleted() async {
    await _repository.clearCompleted();
    state = state.where((item) => item.status != 'completed').toList();
    _syncNativeOverlayBadge();
  }

  Future<void> downloadAll() async {
    state = state.map((item) {
      if (item.status == 'paused' || item.status == 'failed') {
        _repository.updateStatusProgressSpeedEtaRetries(
          item.id,
          'pending',
          0.0,
          0.0,
          0,
          0, // Reset retries count
        );
        return item.copyWith(status: 'pending', progress: 0.0, speed: 0.0, eta: 0, retries: 0);
      }
      return item;
    }).toList();
    _syncNativeOverlayBadge();
    _processNext();
  }

  Future<void> pauseAll() async {
    for (final item in state) {
      final isActive = item.status == 'queued' || 
                       item.status == 'pending' || 
                       item.status == 'preparing' || 
                       item.status == 'fetching_metadata' || 
                       item.status == 'extracting_audio' || 
                       item.status == 'generating_download_link' || 
                       item.status == 'downloading' || 
                       item.status == 'saving';
      if (isActive) {
        pauseDownload(item.id);
      }
    }
    _syncNativeOverlayBadge();
  }

  Future<void> updatePriority(String id, int priority) async {
    state = state.map((item) {
      if (item.id == id) {
        final updated = item.copyWith(priority: priority);
        _repository.updateQueueItem(updated);
        return updated;
      }
      return item;
    }).toList();
    _processNext();
  }

  // Core scheduler with max concurrent downloads
  void _processNext() {
    if (_activeJobs.length >= _maxConcurrent) {
      debugPrint('[Queue] Concurrency limit ($_maxConcurrent) reached.');
      return;
    }

    final pendings = state.where((item) => item.status == 'pending' || item.status == 'queued').toList();
    if (pendings.isEmpty) return;

    // Sort by priority DESC, then by createdAt ASC (oldest first)
    pendings.sort((a, b) {
      final pCompare = b.priority.compareTo(a.priority);
      if (pCompare != 0) return pCompare;
      return a.createdAt.compareTo(b.createdAt);
    });

    final nextItem = pendings.first;
    _activeJobs.add(nextItem.id);
    _updateItemState(nextItem.id, 'preparing', 0.0);
    
    // Spawn task
    _executeDownload(nextItem);
    
    // Check if we have more slots available
    if (_activeJobs.length < _maxConcurrent) {
      _processNext();
    }
  }

  /// Wake up the Render backend if it's sleeping (free tier goes to sleep after 15m)
  Future<void> _ensureServerWarm() async {
    if (_serverWarm) return;
    
    debugPrint('[Queue] Waking up backend server...');
    final isAlive = await _apiClient.wakeUpServer();
    if (isAlive) {
      _serverWarm = true;
      debugPrint('[Queue] Server is warm and ready.');
    } else {
      debugPrint('[Queue] Server wake-up failed, will retry with the actual request.');
    }
    
    // Server stays warm for a while, reset after 10 minutes
    Future.delayed(const Duration(minutes: 10), () {
      _serverWarm = false;
    });
  }

  Future<void> _executeDownload(QueueItem item) async {
    final startTime = DateTime.now();
    try {
      // Step 1: Wake up server if needed
      _updateItemState(item.id, 'preparing', 0.0);
      await _ensureServerWarm();

      if (!_activeJobs.contains(item.id)) {
        debugPrint('[Queue] Job ${item.id} aborted during server warm-up.');
        return;
      }

      // Step 2: Submit extraction
      _updateItemState(item.id, 'preparing', 0.1);
      
      final submitUrl = item.url.contains('youtube.com/results')
          ? 'ytsearch:${item.title ?? "audio"}'
          : item.url;

      debugPrint('[Queue] Job ${item.id} submitting: $submitUrl');
      final submitResponse = await _extractionService.submitExtraction(submitUrl, quality: 'high');
      final jobId = submitResponse.jobId;

      // Update metadata immediately upon job receipt
      _updateItemMetadata(
        item.id,
        submitResponse.title,
        submitResponse.artist,
        submitResponse.thumbnail,
        submitResponse.duration,
      );

      // Step 3: Poll status with timeout
      ExtractionJob? status;
      int pollAttempts = 0;
      const maxPollTime = Duration(minutes: 3);
      final pollDeadline = DateTime.now().add(maxPollTime);
      
      while (DateTime.now().isBefore(pollDeadline)) {
        if (!_activeJobs.contains(item.id)) {
          debugPrint('[Queue] Job ${item.id} execution aborted/paused.');
          return;
        }
        pollAttempts++;
        
        try {
          status = await _extractionService.pollStatus(jobId);
        } catch (pollError) {
          debugPrint('[Queue] Job ${item.id} poll error (attempt $pollAttempts): $pollError');
          if (pollAttempts > 5) rethrow; // Give up after 5 poll failures
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        // Dynamically update metadata if resolved or modified on server
        if (status.title != null && status.title != 'Loading metadata...') {
          _updateItemMetadata(
            item.id,
            status.title!,
            status.artist ?? 'ReelTune',
            status.thumbnail ?? '',
            status.duration ?? 180000,
          );
        }
        
        if (status.status == 'completed') {
          break;
        } else if (status.status == 'failed') {
          throw Exception(status.error ?? 'Extraction failed on server');
        }

        // Map status stage directly from server
        // Progress mapping: preparing=10%, fetching_metadata=20%, extracting_audio=30%, generating_download_link=40%
        double stageProgress = 0.1;
        if (status.stage == 'preparing') stageProgress = 0.1;
        if (status.stage == 'fetching_metadata') stageProgress = 0.2;
        if (status.stage == 'extracting_audio') stageProgress = 0.3;
        if (status.stage == 'generating_download_link') stageProgress = 0.4;

        _updateItemState(item.id, status.stage, stageProgress);

        await Future.delayed(const Duration(seconds: 2));
      }

      if (status == null || status.status != 'completed') {
        throw Exception('Extraction timed out after ${maxPollTime.inMinutes} minutes');
      }

      if (status.downloadUrl == null) {
        throw Exception('Server returned no download URL');
      }

      // Step 4: Download actual file
      _updateItemState(item.id, 'downloading', 0.5);
      
      final localFilePath = await _fileStorageService.getClipFilePath('imported_playlist_songs', jobId);
      final localFile = File(localFilePath);
      if (!await localFile.parent.exists()) {
        await localFile.parent.create(recursive: true);
      }

      debugPrint('[Queue] Job ${item.id} downloading file...');
      await _extractionService.downloadAudio(
        status.downloadUrl!,
        localFilePath,
        onProgress: (p) {
          // Map download progress to 50%-90% of overall progress
          final overallProgress = 0.5 + (p * 0.4);
          final elapsed = DateTime.now().difference(startTime).inSeconds;
          if (elapsed > 0) {
            // Assume 4MB audio file for calculations: 4.0 * 1024 = 4096 KB
            final speedKBps = (p * 4096) / elapsed;
            final etaSec = (p > 0 && p < 1.0) ? ((1.0 - p) * elapsed / p).round() : 0;
            _updateItemProgressMetrics(item.id, overallProgress, speedKBps, etaSec);
          } else {
            _updateItemProgressMetrics(item.id, overallProgress, 0.0, 0);
          }
        },
      );

      // Step 5: Save to database
      _updateItemState(item.id, 'saving', 0.95);
      
      final currentItem = state.firstWhere((i) => i.id == item.id);
      
      // Probe the actual duration of the downloaded file locally on the device using just_audio
      int resolvedDurationMs = currentItem.duration ?? 180000;
      try {
        final probePlayer = AudioPlayer();
        final probedDuration = await probePlayer.setFilePath(localFilePath);
        if (probedDuration != null && probedDuration.inMilliseconds > 0) {
          debugPrint('[Queue] Probed local audio file duration: ${probedDuration.inMilliseconds} ms');
          resolvedDurationMs = probedDuration.inMilliseconds;
        } else {
          throw Exception('Zero or null duration probed');
        }
        await probePlayer.dispose();
      } catch (probeErr) {
        debugPrint('[Queue] Error: Failed to probe local audio duration: $probeErr');
        // Delete the invalid file to avoid wasting space
        try {
          final file = File(localFilePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
        throw Exception('Downloaded audio file is corrupted or not a valid audio format (Source error).');
      }

      final clip = Clip(
        id: jobId,
        albumId: 'imported_playlist_songs',
        title: currentItem.title ?? 'Audio Clip',
        filePath: localFilePath,
        durationMs: resolvedDurationMs,
        sourceUrl: item.url,
        sourcePlatform: item.platform,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        artist: currentItem.artist ?? 'ReelTune',
        albumName: currentItem.title ?? 'Imported Tracks',
      );

      await _clipRepository.insertClip(clip);

      // Refresh the albums list so the downloaded track shows up in "Imported Tracks" immediately
      _ref.read(albumsProvider.notifier).refresh();

      // Map to playlist if playlistId is provided
      if (item.playlistId != null) {
        try {
          await _playlistRepository.addClipToPlaylist(item.playlistId!, clip.id);
          _ref.read(playlistsProvider.notifier).loadPlaylists();
          _ref.invalidate(playlistClipsProvider(item.playlistId!));
        } catch (e) {
          debugPrint('[Queue] Warning: Could not add clip to playlist: $e');
        }
      }

      _updateItemStateMetrics(item.id, 'completed', 1.0, 0.0, 0, item.retries);
      debugPrint('[Queue] Job ${item.id} successfully completed.');
    } catch (e) {
      debugPrint('[Queue] Job ${item.id} failed: $e');
      
      try {
        final currentItem = state.firstWhere((i) => i.id == item.id);
        final nextRetry = currentItem.retries + 1;
        
        if (nextRetry <= 3) {
          // Exponential backoff: 3s, 6s, 12s
          final backoffDelay = Duration(seconds: 3 * (1 << (nextRetry - 1)));
          debugPrint('[Queue] Job ${item.id} retrying in ${backoffDelay.inSeconds}s ($nextRetry/3)');
          _updateItemStateMetrics(
            item.id,
            'queued',
            0.0,
            0.0,
            0,
            nextRetry,
            error: 'Retrying in ${backoffDelay.inSeconds}s ($nextRetry/3)...',
          );
          
          Future.delayed(backoffDelay, () {
            final exists = state.any((i) => i.id == item.id);
            if (exists) {
              final current = state.firstWhere((i) => i.id == item.id);
              if (current.status == 'queued' || current.status == 'pending') {
                _processNext();
              }
            }
          });
        } else {
          String errorMsg = e.toString();
          if (errorMsg.contains('ApiException:')) {
            errorMsg = errorMsg.replaceAll('ApiException: ', '');
          }
          if (errorMsg.contains('Exception:')) {
            errorMsg = errorMsg.replaceAll('Exception: ', '');
          }
          
          _updateItemStateMetrics(
            item.id,
            'failed',
            0.0,
            0.0,
            0,
            currentItem.retries,
            error: errorMsg,
          );
        }
      } catch (stateError) {
        debugPrint('[Queue] Error updating failure state: $stateError');
      }
    } finally {
      _activeJobs.remove(item.id);
      _processNext();
    }
  }
}
