import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/extraction_service.dart';
import '../../core/storage/file_storage_service.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/clip.dart';
import '../../core/models/playlist.dart';
import '../library/PlaylistRepository.dart';
import '../library/PlaylistsProvider.dart';

enum ImportPhase { idle, fetchingMetadata, resolving, review, saving, completed, error }

enum TrackImportStatus { pending, resolving, resolved, failed }

class TrackImportEntry {
  final String title;
  final String artist;
  final String url;
  final int durationMs;
  final TrackImportStatus status;
  final String? downloadUrl;
  final String? error;

  TrackImportEntry({
    required this.title,
    required this.artist,
    required this.url,
    required this.durationMs,
    this.status = TrackImportStatus.pending,
    this.downloadUrl,
    this.error,
  });

  TrackImportEntry copyWith({
    TrackImportStatus? status,
    String? downloadUrl,
    String? error,
  }) {
    return TrackImportEntry(
      title: title,
      artist: artist,
      url: url,
      durationMs: durationMs,
      status: status ?? this.status,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      error: error ?? this.error,
    );
  }
}

class PlaylistImportState {
  final ImportPhase phase;
  final String? playlistTitle;
  final String? playlistDesc;
  final String? playlistCoverUrl;
  final List<TrackImportEntry> tracks;
  final int resolvedCount;
  final int failedCount;
  final String? errorMessage;

  PlaylistImportState({
    this.phase = ImportPhase.idle,
    this.playlistTitle,
    this.playlistDesc,
    this.playlistCoverUrl,
    this.tracks = const [],
    this.resolvedCount = 0,
    this.failedCount = 0,
    this.errorMessage,
  });

  PlaylistImportState copyWith({
    ImportPhase? phase,
    String? playlistTitle,
    String? playlistDesc,
    String? playlistCoverUrl,
    List<TrackImportEntry>? tracks,
    int? resolvedCount,
    int? failedCount,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlaylistImportState(
      phase: phase ?? this.phase,
      playlistTitle: playlistTitle ?? this.playlistTitle,
      playlistDesc: playlistDesc ?? this.playlistDesc,
      playlistCoverUrl: playlistCoverUrl ?? this.playlistCoverUrl,
      tracks: tracks ?? this.tracks,
      resolvedCount: resolvedCount ?? this.resolvedCount,
      failedCount: failedCount ?? this.failedCount,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final playlistImportProvider = StateNotifierProvider.autoDispose<PlaylistImportNotifier, PlaylistImportState>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final extractionService = ref.watch(extractionServiceProvider);
  final fileStorage = ref.watch(fileStorageServiceProvider);
  final clipRepo = ref.watch(clipRepositoryProvider);
  final playlistRepo = ref.watch(playlistRepositoryProvider);
  return PlaylistImportNotifier(apiClient, extractionService, fileStorage, clipRepo, playlistRepo, ref);
});

class PlaylistImportNotifier extends StateNotifier<PlaylistImportState> {
  final ApiClient _apiClient;
  final ExtractionService _extractionService;
  final FileStorageService _fileStorage;
  final ClipRepository _clipRepo;
  final PlaylistRepository _playlistRepo;
  final Ref _ref;

  bool _isCancelled = false;

  PlaylistImportNotifier(
    this._apiClient,
    this._extractionService,
    this._fileStorage,
    this._clipRepo,
    this._playlistRepo,
    this._ref,
  ) : super(PlaylistImportState());

  Future<void> fetchAndResolvePlaylist(String url, String platform) async {
    _isCancelled = false;
    state = state.copyWith(
      phase: ImportPhase.fetchingMetadata,
      clearError: true,
    );

    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        '/api/playlist/metadata',
        data: {'url': url},
      );

      final data = response.data;
      if (data == null) throw Exception('No data returned from playlist metadata API');

      final playlistTitle = data['title'] as String? ?? 'Imported Playlist';
      final playlistDesc = data['description'] as String?;
      final playlistCoverUrl = data['coverUrl'] as String?;
      final rawTracks = data['tracks'] as List<dynamic>? ?? [];

      final tracks = rawTracks.map((t) {
        final map = Map<String, dynamic>.from(t);
        return TrackImportEntry(
          title: map['title'] as String? ?? 'Unknown Track',
          artist: map['artist'] as String? ?? 'Unknown Artist',
          url: map['url'] as String? ?? '',
          durationMs: map['durationMs'] as int? ?? 180000,
        );
      }).toList();

      state = state.copyWith(
        phase: ImportPhase.resolving,
        playlistTitle: playlistTitle,
        playlistDesc: playlistDesc,
        playlistCoverUrl: playlistCoverUrl,
        tracks: tracks,
      );

      await _resolveAllTracks();
    } catch (e) {
      if (_isCancelled) return;
      state = state.copyWith(
        phase: ImportPhase.error,
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  Future<void> _resolveAllTracks() async {
    final tracks = List<TrackImportEntry>.from(state.tracks);
    if (tracks.isEmpty) {
      state = state.copyWith(phase: ImportPhase.review);
      return;
    }

    // Concurrency control: max 6 parallel resolutions
    const maxConcurrency = 6;
    int nextIndex = 0;
    final activeCount = ValueNotifier<int>(0);
    final completer = Completer<void>();

    Future<void> runNext() async {
      if (_isCancelled || nextIndex >= tracks.length) {
        if (activeCount.value == 0 && !completer.isCompleted) {
          completer.complete();
        }
        return;
      }

      final index = nextIndex++;
      activeCount.value++;

      try {
        await _resolveTrack(index);
      } catch (e) {
        debugPrint('[PlaylistImport] Unexpected error resolving track at $index: $e');
      } finally {
        activeCount.value--;
        if (nextIndex < tracks.length && !_isCancelled) {
          runNext();
        } else if (activeCount.value == 0 && !completer.isCompleted) {
          completer.complete();
        }
      }
    }

    // Spawn initial workers
    for (int i = 0; i < maxConcurrency; i++) {
      runNext();
    }

    await completer.future;

    if (_isCancelled) return;
    state = state.copyWith(phase: ImportPhase.review);
  }

  Future<void> _resolveTrack(int index) async {
    final tracks = List<TrackImportEntry>.from(state.tracks);
    final entry = tracks[index];

    tracks[index] = entry.copyWith(status: TrackImportStatus.resolving);
    state = state.copyWith(tracks: List.unmodifiable(tracks));

    try {
      final submitUrl = entry.url.contains('youtube.com/results')
          ? 'ytsearch:${entry.title} ${entry.artist}'
          : entry.url;

      final submitResponse = await _extractionService.submitExtraction(submitUrl, quality: 'high');
      final jobId = submitResponse.jobId;

      // Poll status with explicit timeout (180 seconds)
      ExtractionJob? status;
      int pollAttempts = 0;
      final pollDeadline = DateTime.now().add(const Duration(seconds: 180));

      while (DateTime.now().isBefore(pollDeadline) && !_isCancelled) {
        pollAttempts++;
        try {
          status = await _extractionService.pollStatus(jobId);
        } catch (pollErr) {
          debugPrint('[PlaylistImport] Poll failed for track $index (attempt $pollAttempts): $pollErr');
          if (pollAttempts > 5) rethrow;
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }

        if (status.status == 'completed') {
          break;
        } else if (status.status == 'failed') {
          throw Exception(status.error ?? 'Extraction failed on server');
        }

        await Future.delayed(const Duration(seconds: 2));
      }

      if (_isCancelled) return;

      if (status == null || status.status != 'completed') {
        throw Exception('Extraction timed out');
      }

      if (status.downloadUrl == null) {
        throw Exception('No download URL returned');
      }

      final updatedTracks = List<TrackImportEntry>.from(state.tracks);
      updatedTracks[index] = entry.copyWith(
        status: TrackImportStatus.resolved,
        downloadUrl: status.downloadUrl,
      );

      final resolvedCount = updatedTracks.where((t) => t.status == TrackImportStatus.resolved).length;
      final failedCount = updatedTracks.where((t) => t.status == TrackImportStatus.failed).length;

      state = state.copyWith(
        tracks: List.unmodifiable(updatedTracks),
        resolvedCount: resolvedCount,
        failedCount: failedCount,
      );
    } catch (e) {
      if (_isCancelled) return;
      final updatedTracks = List<TrackImportEntry>.from(state.tracks);
      updatedTracks[index] = entry.copyWith(
        status: TrackImportStatus.failed,
        error: e.toString().replaceAll('Exception: ', ''),
      );

      final resolvedCount = updatedTracks.where((t) => t.status == TrackImportStatus.resolved).length;
      final failedCount = updatedTracks.where((t) => t.status == TrackImportStatus.failed).length;

      state = state.copyWith(
        tracks: List.unmodifiable(updatedTracks),
        resolvedCount: resolvedCount,
        failedCount: failedCount,
      );
    }
  }

  Future<void> savePlaylistToLibrary() async {
    if (state.tracks.isEmpty) return;

    state = state.copyWith(phase: ImportPhase.saving);

    try {
      final title = state.playlistTitle ?? 'Imported Playlist';
      final desc = state.playlistDesc;
      final playlist = await _playlistRepo.createPlaylist(title, description: desc);

      final resolvedTracks = state.tracks.where((t) => t.status == TrackImportStatus.resolved).toList();
      
      const maxDownloadConcurrency = 6;
      for (int i = 0; i < resolvedTracks.length; i += maxDownloadConcurrency) {
        if (_isCancelled) return;
        final batch = resolvedTracks.sublist(i, (i + maxDownloadConcurrency) < resolvedTracks.length ? (i + maxDownloadConcurrency) : resolvedTracks.length);
        
        await Future.wait(batch.map((track) async {
          if (track.downloadUrl == null) return;
          if (_isCancelled) return;

          try {
            final localId = _ref.read(apiClientProvider).hashCode.toString() + 
                            DateTime.now().millisecondsSinceEpoch.toString() + 
                            track.title.hashCode.toString();
            final localFilePath = await _fileStorage.getClipFilePath('imported_playlist_songs', localId);
            final localFile = File(localFilePath);
            
            if (!await localFile.parent.exists()) {
              await localFile.parent.create(recursive: true);
            }

            // Download file locally
            await _extractionService.downloadAudio(track.downloadUrl!, localFilePath);

            final clip = Clip(
              id: localId,
              albumId: 'imported_playlist_songs',
              title: track.title,
              filePath: localFilePath,
              durationMs: track.durationMs,
              sourceUrl: track.url,
              sourcePlatform: 'playlist_import',
              createdAt: DateTime.now().millisecondsSinceEpoch,
              artist: track.artist,
              albumName: title,
            );

            await _clipRepo.insertClip(clip);
            await _playlistRepo.addClipToPlaylist(playlist.id, clip.id);
          } catch (err) {
            debugPrint('[PlaylistImport] Failed to save track "${track.title}" to library: $err');
          }
        }));
      }

      // Reload playlists in view
      _ref.read(playlistsProvider.notifier).loadPlaylists();
      state = state.copyWith(phase: ImportPhase.completed);
    } catch (e) {
      state = state.copyWith(
        phase: ImportPhase.error,
        errorMessage: 'Failed to save to library: $e',
      );
    }
  }

  void cancel() {
    _isCancelled = true;
    state = state.copyWith(phase: ImportPhase.idle);
  }

  void reset() {
    _isCancelled = false;
    state = PlaylistImportState();
  }

  @override
  void dispose() {
    _isCancelled = true;
    super.dispose();
  }
}
