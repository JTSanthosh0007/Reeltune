import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/clip_repository.dart';
import '../../core/db/queue_repository.dart';
import '../../core/models/clip.dart';
import '../../core/models/queue_item.dart';
import '../../core/network/extraction_service.dart';
import '../../core/storage/file_storage_service.dart';
import '../library/PlaylistRepository.dart';
import '../library/PlaylistsProvider.dart';
import '../share_intent/share_overlay_bridge.dart';

final queueProvider = StateNotifierProvider<QueueNotifier, List<QueueItem>>((ref) {
  final repository = ref.watch(queueRepositoryProvider);
  final extractionService = ref.watch(extractionServiceProvider);
  final fileStorageService = ref.watch(fileStorageServiceProvider);
  final clipRepository = ref.watch(clipRepositoryProvider);
  final playlistRepository = ref.watch(playlistRepositoryProvider);
  return QueueNotifier(
    repository,
    extractionService,
    fileStorageService,
    clipRepository,
    playlistRepository,
    ref,
  );
});

class QueueNotifier extends StateNotifier<List<QueueItem>> {
  final QueueRepository _repository;
  final ExtractionService _extractionService;
  final FileStorageService _fileStorageService;
  final ClipRepository _clipRepository;
  final PlaylistRepository _playlistRepository;
  final Ref _ref;
  
  final Set<String> _activeJobs = {};
  final Map<String, DateTime> _lastDbWriteTime = {};
  static const _uuid = Uuid();

  QueueNotifier(
    this._repository,
    this._extractionService,
    this._fileStorageService,
    this._clipRepository,
    this._playlistRepository,
    this._ref,
  ) : super([]) {
    _loadQueue();
  }

  Future<void> _loadQueue() async {
    final items = await _repository.getAllQueueItems();
    // Auto-resume or reset downloading items back to pending on startup
    final resetItems = items.map((item) {
      if (item.status == 'downloading') {
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
    state = resetItems;
    _syncNativeOverlayBadge();
    _processNext();
  }

  void _syncNativeOverlayBadge() {
    try {
      final pendingCount = state.where((item) => item.status == 'pending' || item.status == 'downloading').length;
      if (pendingCount > 0) {
        ShareOverlayBridge.updateBubbleBadge(pendingCount);
      } else {
        ShareOverlayBridge.dismissBubble();
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
        (item.status == 'pending' ||
            item.status == 'downloading' ||
            item.status == 'paused'));
    if (hasDuplicate) {
      debugPrint('[Queue] Duplicate active URL skipped: $cleanUrl');
      return;
    }

    final id = _uuid.v4();
    final item = QueueItem(
      id: id,
      url: cleanUrl,
      title: title ?? _defaultTitle(cleanUrl, platform),
      artist: artist ?? 'ReelTune',
      platform: platform,
      status: 'pending',
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
      if (segment.isNotEmpty) return '$platform-$segment';
    } catch (_) {}
    return 'Shared $platform Audio';
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
    _repository.updateStatusProgressSpeedEtaRetries(
      id,
      status,
      progress,
      0.0,
      0,
      state.firstWhere((i) => i.id == id).retries,
      error: error,
    );
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
      final currentItem = state.firstWhere((i) => i.id == id);
      _repository.updateStatusProgressSpeedEtaRetries(
        id,
        currentItem.status,
        progress,
        speed,
        eta,
        currentItem.retries,
      );
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
      if (item.status == 'downloading' || item.status == 'pending') {
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

  // Core scheduler with a max limit of 5 concurrent downloads
  void _processNext() {
    if (_activeJobs.length >= 5) {
      debugPrint('[Queue] Concurrency limit (5) reached.');
      return;
    }

    final pendings = state.where((item) => item.status == 'pending').toList();
    if (pendings.isEmpty) return;

    // Sort by priority DESC, then by createdAt ASC (oldest first)
    pendings.sort((a, b) {
      final pCompare = b.priority.compareTo(a.priority);
      if (pCompare != 0) return pCompare;
      return a.createdAt.compareTo(b.createdAt);
    });

    final nextItem = pendings.first;
    _activeJobs.add(nextItem.id);
    _updateItemState(nextItem.id, 'downloading', 0.0);
    
    // Spawn task
    _executeDownload(nextItem);
    
    // Check if we have more slots available
    _processNext();
  }

  Future<void> _executeDownload(QueueItem item) async {
    final startTime = DateTime.now();
    try {
      final submitUrl = item.url.contains('youtube.com/results')
          ? 'ytsearch:${item.title ?? "audio"}'
          : item.url;

      debugPrint('[Queue] Job ${item.id} submitting: $submitUrl');
      final jobId = await _extractionService.submitExtraction(submitUrl, quality: 'high');

      // Poll status
      ExtractionJob? status;
      int pollAttempts = 0;
      while (true) {
        if (!_activeJobs.contains(item.id)) {
          debugPrint('[Queue] Job ${item.id} execution aborted/paused.');
          return;
        }
        pollAttempts++;
        status = await _extractionService.pollStatus(jobId);
        if (status.status == ExtractionStatus.completed) {
          break;
        } else if (status.status == ExtractionStatus.failed) {
          throw Exception(status.error ?? 'Extraction failed on server');
        }

        // Limit polling to prevent infinite loops (max 3 minutes)
        if (pollAttempts >= 90) {
          throw Exception('Polling timeout exceeded');
        }
        await Future.delayed(const Duration(seconds: 2));
      }

      if (status.downloadUrl == null) {
        throw Exception('Download URL was empty');
      }

      // Download actual file
      final localFilePath = await _fileStorageService.getClipFilePath('imported_playlist_songs', jobId);
      final localFile = File(localFilePath);
      if (!await localFile.parent.exists()) {
        await localFile.parent.create(recursive: true);
      }

      debugPrint('[Queue] Job ${item.id} downloading file from: ${status.downloadUrl}');
      await _extractionService.downloadAudio(
        status.downloadUrl!,
        localFilePath,
        onProgress: (p) {
          final elapsed = DateTime.now().difference(startTime).inSeconds;
          if (elapsed > 0) {
            // Assume 4MB audio file for calculations: 4.0 * 1024 = 4096 KB
            final speedKBps = (p * 4096) / elapsed;
            final etaSec = (p > 0 && p < 1.0) ? ((1.0 - p) * elapsed / p).round() : 0;
            _updateItemProgressMetrics(item.id, p, speedKBps, etaSec);
          } else {
            _updateItemProgressMetrics(item.id, p, 0.0, 0);
          }
        },
      );

      // Save to Clip Database
      final clip = Clip(
        id: jobId,
        albumId: 'imported_playlist_songs',
        title: status.title ?? item.title ?? 'Audio Clip',
        filePath: localFilePath,
        durationMs: 180000,
        sourceUrl: item.url,
        sourcePlatform: item.platform,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        artist: item.artist ?? 'ReelTune',
        albumName: item.title ?? 'Imported Tracks',
      );

      await _clipRepository.insertClip(clip);

      // Map to playlist if playlistId is provided
      if (item.playlistId != null) {
        await _playlistRepository.addClipToPlaylist(item.playlistId!, clip.id);
        _ref.read(playlistsProvider.notifier).loadPlaylists();
        _ref.invalidate(playlistClipsProvider(item.playlistId!));
      }

      _updateItemStateMetrics(item.id, 'completed', 1.0, 0.0, 0, item.retries);
      debugPrint('[Queue] Job ${item.id} successfully completed.');
    } catch (e) {
      debugPrint('[Queue] Job ${item.id} failed: $e');
      final currentItem = state.firstWhere((i) => i.id == item.id);
      final nextRetry = currentItem.retries + 1;
      
      if (nextRetry <= 3) {
        debugPrint('[Queue] Job ${item.id} retrying automatically ($nextRetry/3)');
        _updateItemStateMetrics(item.id, 'pending', 0.0, 0.0, 0, nextRetry);
        // Wait 3 seconds before next retry
        await Future.delayed(const Duration(seconds: 3));
      } else {
        _updateItemStateMetrics(
          item.id,
          'failed',
          0.0,
          0.0,
          0,
          currentItem.retries,
          error: e.toString(),
        );
      }
    } finally {
      _activeJobs.remove(item.id);
      _processNext();
    }
  }
}
