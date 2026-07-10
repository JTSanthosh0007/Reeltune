import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/constants.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/clip.dart';
import '../../core/network/api_client.dart';
import '../../core/network/extraction_service.dart';
import '../../core/storage/file_storage_service.dart';
import '../albums/album_providers.dart';
import '../notifications/notifications_provider.dart';
import '../settings/settings_screen.dart';

// --- Extraction flow state ---
enum ExtractionStep {
  idle,
  submitting,
  extracting,
  downloading,
  pickAlbum,
  saving,
  done,
  error,
}

class ExtractionFlowState {
  final ExtractionStep step;
  final String? url;
  final String? localPath;
  final String platform;
  final String? jobId;
  final double downloadProgress;
  final String? errorMessage;
  final String? savedFilePath;
  final String? generatedTitle;
  final int? verifiedDurationMs;

  const ExtractionFlowState({
    this.step = ExtractionStep.idle,
    this.url,
    this.localPath,
    this.platform = 'local',
    this.jobId,
    this.downloadProgress = 0,
    this.errorMessage,
    this.savedFilePath,
    this.generatedTitle,
    this.verifiedDurationMs,
  });

  ExtractionFlowState copyWith({
    ExtractionStep? step,
    String? url,
    String? localPath,
    String? platform,
    String? jobId,
    double? downloadProgress,
    String? errorMessage,
    String? savedFilePath,
    String? generatedTitle,
    int? verifiedDurationMs,
  }) {
    return ExtractionFlowState(
      step: step ?? this.step,
      url: url ?? this.url,
      localPath: localPath ?? this.localPath,
      platform: platform ?? this.platform,
      jobId: jobId ?? this.jobId,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      errorMessage: errorMessage ?? this.errorMessage,
      savedFilePath: savedFilePath ?? this.savedFilePath,
      generatedTitle: generatedTitle ?? this.generatedTitle,
      verifiedDurationMs: verifiedDurationMs ?? this.verifiedDurationMs,
    );
  }
}

// --- Extraction flow provider ---
final extractionFlowProvider =
    StateNotifierProvider<ExtractionFlowNotifier, ExtractionFlowState>((ref) {
  return ExtractionFlowNotifier(ref);
});

class ExtractionFlowNotifier extends StateNotifier<ExtractionFlowState> {
  final Ref _ref;
  Timer? _pollTimer;

  ExtractionFlowNotifier(this._ref) : super(const ExtractionFlowState());

  Future<void> startExtraction({
    String? url,
    String? localPath,
    required String platform,
  }) async {
    final title = url != null
        ? ExtractionService.generateTitle(url)
        : 'Local Audio • ${DateTime.now().month}/${DateTime.now().day}';

    state = ExtractionFlowState(
      step: ExtractionStep.submitting,
      url: url,
      localPath: localPath,
      platform: platform,
      generatedTitle: title,
    );

    if (url != null) {
      // Server-side extraction for URLs
      await _extractFromUrl(url);
    } else if (localPath != null) {
      // Validate local file integrity and extract duration
      try {
        final testPlayer = AudioPlayer();
        final duration = await testPlayer.setFilePath(localPath);
        await testPlayer.dispose();

        state = state.copyWith(
          step: ExtractionStep.pickAlbum,
          savedFilePath: localPath,
          verifiedDurationMs: duration?.inMilliseconds,
        );
      } catch (e) {
        state = state.copyWith(
          step: ExtractionStep.error,
          errorMessage: 'Invalid or corrupt local video file.',
        );
      }
    }
  }

  Future<void> _extractFromUrl(String url) async {
    try {
      final extractionService = _ref.read(extractionServiceProvider);
      final qualityText = _ref.read(playbackQualityProvider);

      String cleanQuality = 'high';
      if (qualityText.toLowerCase().contains('96')) {
        cleanQuality = 'low';
      } else if (qualityText.toLowerCase().contains('160') || qualityText.toLowerCase().contains('128')) {
        cleanQuality = 'medium';
      } else if (qualityText.toLowerCase().contains('320') || qualityText.toLowerCase().contains('192')) {
        cleanQuality = 'high';
      } else if (qualityText.toLowerCase().contains('original')) {
        cleanQuality = 'original';
      }

      // Submit extraction job
      final jobId = await extractionService.submitExtraction(url, quality: cleanQuality);
      state = state.copyWith(
        step: ExtractionStep.extracting,
        jobId: jobId,
      );

      // Start polling
      _startPolling(jobId);
    } on ApiException catch (e, stack) {
      debugPrintStack(stackTrace: stack, label: 'ApiException in _extractFromUrl');
      state = state.copyWith(
        step: ExtractionStep.error,
        errorMessage: e.message,
      );
    } catch (e, stack) {
      debugPrintStack(stackTrace: stack, label: 'Error in _extractFromUrl');
      state = state.copyWith(
        step: ExtractionStep.error,
        errorMessage: 'Failed to start extraction: $e',
      );
    }
  }

  void _startPolling(String jobId) {
    int attempts = 0;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(AppConstants.pollInterval, (timer) async {
      attempts++;
      if (attempts > AppConstants.maxPollAttempts) {
        timer.cancel();
        state = state.copyWith(
          step: ExtractionStep.error,
          errorMessage: 'Extraction timed out. Please try again.',
        );
        return;
      }

      try {
        final extractionService = _ref.read(extractionServiceProvider);
        final job = await extractionService.pollStatus(jobId);

        switch (job.status) {
          case ExtractionStatus.completed:
            timer.cancel();
            if (job.downloadUrl != null) {
              await _downloadAudio(job.downloadUrl!, job.title);
            } else {
              state = state.copyWith(
                step: ExtractionStep.error,
                errorMessage: 'No download URL received.',
              );
            }
            break;
          case ExtractionStatus.failed:
            timer.cancel();
            state = state.copyWith(
              step: ExtractionStep.error,
              errorMessage: job.error ?? 'Extraction failed.',
            );
            break;
          case ExtractionStatus.processing:
          case ExtractionStatus.pending:
            // Keep polling
            break;
        }
      } catch (e, stack) {
        debugPrintStack(stackTrace: stack, label: 'Error in _startPolling');
        // Retry on transient errors
        if (attempts > 3) {
          timer.cancel();
          String errMsg = 'Connection error: $e';
          if (e is ApiException) {
            errMsg = e.message;
          }
          state = state.copyWith(
            step: ExtractionStep.error,
            errorMessage: errMsg,
          );
        }
      }
    });
  }

  Future<void> _downloadAudio(String downloadUrl, String? title) async {
    try {
      state = state.copyWith(step: ExtractionStep.downloading);

      final extractionService = _ref.read(extractionServiceProvider);
      final fileService = _ref.read(fileStorageServiceProvider);

      // Create a temp path for download
      final baseDir = await fileService.baseDirectory;
      final tempPath = '${baseDir.path}/temp_download.mp3';

      await extractionService.downloadAudio(
        downloadUrl,
        tempPath,
        onProgress: (progress) {
          state = state.copyWith(downloadProgress: progress);
        },
      );

      // --- Verify File Integrity ---
      final file = File(tempPath);
      if (!await file.exists() || await file.length() < 1000) {
        throw Exception('Downloaded audio file is corrupted or empty.');
      }

      // Confirm codec parsing and extract exact track duration
      final testPlayer = AudioPlayer();
      Duration? duration;
      try {
        duration = await testPlayer.setFilePath(tempPath);
      } catch (e) {
        throw Exception('File is not a valid audio container.');
      } finally {
        await testPlayer.dispose();
      }

      state = state.copyWith(
        step: ExtractionStep.pickAlbum,
        savedFilePath: tempPath,
        generatedTitle: title ?? state.generatedTitle,
        verifiedDurationMs: duration?.inMilliseconds,
      );
    } catch (e, stack) {
      debugPrintStack(stackTrace: stack, label: 'Error in _downloadAudio');
      state = state.copyWith(
        step: ExtractionStep.error,
        errorMessage: 'Download/Validation failed: ${e.toString().replaceAll('Exception: ', '')}',
      );
    }
  }

  Future<Clip?> saveToAlbum(String albumId) async {
    if (state.savedFilePath == null) return null;

    try {
      state = state.copyWith(step: ExtractionStep.saving);

      final clipRepo = _ref.read(clipRepositoryProvider);
      final fileService = _ref.read(fileStorageServiceProvider);

      // Create clip in DB first to get ID
      final clip = await clipRepo.createClip(
        albumId: albumId,
        title: state.generatedTitle ?? 'Audio Clip',
        filePath: '', // Will update after copying
        durationMs: state.verifiedDurationMs,
        sourceUrl: state.url,
        sourcePlatform: state.platform,
      );

      // Copy file to album directory
      final finalPath = await fileService.copyToAlbum(
        state.savedFilePath!,
        albumId,
        clip.id,
      );

      // Update clip with final path
      final updatedClip = clip.copyWith(filePath: finalPath);
      await clipRepo.updateClip(updatedClip);

      // Refresh albums
      _ref.read(albumsProvider.notifier).refresh();

      state = state.copyWith(step: ExtractionStep.done);

      _ref.read(notificationsProvider.notifier).addNotification(
        title: 'Extraction Completed 🎉',
        body: 'Successfully extracted and saved "${clip.title}" to album.',
        type: 'extraction',
      );

      return updatedClip;
    } catch (e, stack) {
      debugPrintStack(stackTrace: stack, label: 'Error in saveToAlbum');
      state = state.copyWith(
        step: ExtractionStep.error,
        errorMessage: 'Failed to save clip: $e',
      );

      _ref.read(notificationsProvider.notifier).addNotification(
        title: 'Extraction Failed ❌',
        body: 'Failed to save extracted track: $e',
        type: 'error',
      );

      return null;
    }
  }

  void retry() {
    if (state.url != null) {
      startExtraction(url: state.url, platform: state.platform);
    }
  }

  void reset() {
    _pollTimer?.cancel();
    state = const ExtractionFlowState();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }
}
