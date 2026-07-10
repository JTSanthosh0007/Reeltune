import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/db/clip_repository.dart';
import '../albums/album_providers.dart';
import '../../main.dart'; // import global audioHandler
import 'audio_handler.dart'; // import ReelTuneAudioHandler

// Position update throttle interval
const _positionThrottleMs = 500;

// --- Player state ---
class PlayerState {
  final Clip? currentClip;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final bool isLooping;
  final bool isLoading;
  final double speed;
  final Duration? sleepTimerRemaining;
  final bool isBassBoostEnabled;
  final bool isTrebleBoostEnabled;
  final bool isVocalEnabled;
  final bool isLoudnessNormalizerEnabled;
  final bool isShuffleEnabled;

  const PlayerState({
    this.currentClip,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isLooping = false,
    this.isLoading = false,
    this.speed = 1.0,
    this.sleepTimerRemaining,
    this.isBassBoostEnabled = false,
    this.isTrebleBoostEnabled = false,
    this.isVocalEnabled = false,
    this.isLoudnessNormalizerEnabled = false,
    this.isShuffleEnabled = false,
  });

  PlayerState copyWith({
    Clip? currentClip,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    bool? isLooping,
    bool? isLoading,
    double? speed,
    Duration? Function()? sleepTimerRemaining,
    bool? isBassBoostEnabled,
    bool? isTrebleBoostEnabled,
    bool? isVocalEnabled,
    bool? isLoudnessNormalizerEnabled,
    bool? isShuffleEnabled,
  }) {
    return PlayerState(
      currentClip: currentClip ?? this.currentClip,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isLooping: isLooping ?? this.isLooping,
      isLoading: isLoading ?? this.isLoading,
      speed: speed ?? this.speed,
      sleepTimerRemaining: sleepTimerRemaining != null ? sleepTimerRemaining() : this.sleepTimerRemaining,
      isBassBoostEnabled: isBassBoostEnabled ?? this.isBassBoostEnabled,
      isTrebleBoostEnabled: isTrebleBoostEnabled ?? this.isTrebleBoostEnabled,
      isVocalEnabled: isVocalEnabled ?? this.isVocalEnabled,
      isLoudnessNormalizerEnabled: isLoudnessNormalizerEnabled ?? this.isLoudnessNormalizerEnabled,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
    );
  }

  bool get hasClip => currentClip != null;

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }
}

// --- Player provider ---
final playerProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier(ref);
});

class PlayerNotifier extends StateNotifier<PlayerState> {
  final Ref _ref;
  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  Timer? _sleepTimer;
  DateTime _lastPositionUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  // Track natural song completion boundaries
  String? _lastClipId;
  Duration _lastPosition = Duration.zero;
  Duration _lastDuration = Duration.zero;

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _initListeners();
  }

  ReelTuneAudioHandler get _handler => audioHandler as ReelTuneAudioHandler;

  void _initListeners() {
    // Listen to playback state from audio_service — throttle position updates
    _playbackStateSub = audioHandler.playbackState.listen((stateEvent) {
      if (!mounted) return;

      final isLoading = stateEvent.processingState == AudioProcessingState.loading ||
          stateEvent.processingState == AudioProcessingState.buffering;

      final now = DateTime.now();
      final positionChanged = stateEvent.updatePosition != state.position;
      
      // Update our position tracker
      _lastPosition = stateEvent.updatePosition;

      // Natural end of the final track in queue
      if (stateEvent.processingState == AudioProcessingState.completed) {
        if (_lastClipId != null) {
          _ref.read(clipRepositoryProvider).updateLastPlayed(_lastClipId!);
          _ref.invalidate(recentClipsProvider);
          _lastClipId = null;
        }
      }

      final shouldThrottle = positionChanged &&
          now.difference(_lastPositionUpdate).inMilliseconds < _positionThrottleMs;

      // Always update play/loading state immediately, but throttle pure position-only updates
      if (shouldThrottle &&
          stateEvent.playing == state.isPlaying &&
          isLoading == state.isLoading) {
        return;
      }

      if (positionChanged) _lastPositionUpdate = now;

      state = state.copyWith(
        isPlaying: stateEvent.playing,
        isLoading: isLoading,
        speed: stateEvent.speed,
        isLooping: stateEvent.repeatMode == AudioServiceRepeatMode.one,
        isShuffleEnabled: stateEvent.shuffleMode == AudioServiceShuffleMode.all,
      );
    });

    // Listen to current media item
    _mediaItemSub = audioHandler.mediaItem.listen((item) {
      if (!mounted) return;

      // Track transition logic: check if the previous track reached completion
      if (item == null) {
        if (_lastClipId != null) {
          final finished = _lastDuration > Duration.zero &&
              (_lastDuration - _lastPosition).inSeconds <= 2;
          if (finished) {
            _ref.read(clipRepositoryProvider).updateLastPlayed(_lastClipId!);
            _ref.invalidate(recentClipsProvider);
          }
        }
        _lastClipId = null;
        _lastDuration = Duration.zero;
      } else {
        if (_lastClipId != null && _lastClipId != item.id) {
          final finished = _lastDuration > Duration.zero &&
              (_lastDuration - _lastPosition).inSeconds <= 2;
          if (finished) {
            _ref.read(clipRepositoryProvider).updateLastPlayed(_lastClipId!);
            _ref.invalidate(recentClipsProvider);
          }
        }
        _lastClipId = item.id;
        _lastDuration = item.duration ?? Duration.zero;
      }

      if (item == null) return;

      // Extract Clip object properties back from MediaItem metadata
      final clip = Clip(
        id: item.id,
        albumId: item.extras?['albumId'] as String? ?? '',
        title: item.title,
        filePath: item.extras?['filePath'] as String? ?? '',
        durationMs: item.duration?.inMilliseconds,
        sourcePlatform: item.album,
        createdAt: 0,
      );

      state = state.copyWith(
        currentClip: clip,
        duration: item.duration ?? Duration.zero,
      );
    });
  }

  Future<void> playQueue(List<Clip> clips, int initialIndex) async {
    if (clips.isEmpty) return;

    // Synchronously set targeted clip to update UI and support instant navigation
    final targetClip = clips[initialIndex];
    state = state.copyWith(
      currentClip: targetClip,
      isLoading: true,
      isPlaying: false,
      duration: targetClip.durationMs != null
          ? Duration(milliseconds: targetClip.durationMs!)
          : Duration.zero,
    );

    // Smooth volume fade-out/mute
    await _handler.player.setVolume(0.0);

    final List<MediaItem> mediaItems = [];
    final List<AudioSource> sources = [];

    // Preload albums to match cover image paths
    final albums = _ref.read(albumsProvider).value ?? [];

    for (final clip in clips) {
      Album? album;
      try {
        album = albums.firstWhere((a) => a.id == clip.albumId);
      } catch (_) {
        album = null;
      }

      final mediaItem = MediaItem(
        id: clip.id,
        title: clip.title,
        album: clip.sourcePlatform ?? 'ReelTune',
        artist: clip.artist ?? 'Unknown Artist',
        duration: clip.durationMs != null ? Duration(milliseconds: clip.durationMs!) : null,
        artUri: album?.coverImagePath != null && album!.coverImagePath!.isNotEmpty
            ? Uri.file(album.coverImagePath!)
            : null,
        extras: {
          'albumId': clip.albumId,
          'filePath': clip.filePath,
        },
      );
      mediaItems.add(mediaItem);
      sources.add(AudioSource.file(clip.filePath, tag: mediaItem));
    }

    // Set the queue on the audio handler
    _handler.queue.add(mediaItems);

    final playlist = ConcatenatingAudioSource(children: sources);
    try {
      await _handler.player.setAudioSource(
        playlist,
        initialIndex: initialIndex,
      );
      _handler.play();
      _handler.fadeVolume(1.0, const Duration(milliseconds: 300));
    } catch (e) {
      _handler.playbackState.add(_handler.playbackState.value.copyWith(
        errorMessage: 'Failed to load audio: $e',
      ));
    }
  }

  Future<void> playClip(Clip clip) async {
    await playQueue([clip], 0);
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      // Fade-out then pause
      await _handler.fadeVolume(0.0, const Duration(milliseconds: 200));
      await audioHandler.pause();
    } else {
      await _handler.player.setVolume(0.0);
      await audioHandler.play();
      await _handler.fadeVolume(1.0, const Duration(milliseconds: 250));
    }
  }

  Future<void> seek(Duration position) async {
    await audioHandler.seek(position);
  }

  Future<void> seekRelative(Duration offset) async {
    final newPosition = _handler.player.position + offset;
    final clampedPosition = Duration(
      milliseconds: newPosition.inMilliseconds.clamp(
        0,
        state.duration.inMilliseconds,
      ),
    );
    await audioHandler.seek(clampedPosition);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await audioHandler.setSpeed(speed);
  }

  void toggleLoop() {
    final nextMode = state.isLooping ? AudioServiceRepeatMode.none : AudioServiceRepeatMode.one;
    audioHandler.setRepeatMode(nextMode);
  }

  void toggleShuffle() {
    final nextMode = state.isShuffleEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all;
    audioHandler.setShuffleMode(nextMode);
  }

  Future<void> skipToNext() async {
    await audioHandler.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await audioHandler.skipToPrevious();
  }

  // Sleep Timer implementation
  void setSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    state = state.copyWith(sleepTimerRemaining: () => duration);

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.sleepTimerRemaining == null) {
        timer.cancel();
        return;
      }

      final newTime = state.sleepTimerRemaining! - const Duration(seconds: 1);
      if (newTime.inSeconds <= 0) {
        timer.cancel();
        state = state.copyWith(sleepTimerRemaining: () => null);
        stop();
      } else {
        state = state.copyWith(sleepTimerRemaining: () => newTime);
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    state = state.copyWith(sleepTimerRemaining: () => null);
  }

  // --- Audio Enhancements ---

  void toggleBassBoost(bool enable) {
    _handler.toggleBassBoost(enable);
    state = state.copyWith(isBassBoostEnabled: enable);
  }

  void toggleTrebleBoost(bool enable) {
    _handler.toggleTrebleBoost(enable);
    state = state.copyWith(isTrebleBoostEnabled: enable);
  }

  void toggleVocalEnhancement(bool enable) {
    _handler.toggleVocalEnhancement(enable);
    state = state.copyWith(isVocalEnabled: enable);
  }

  void toggleLoudnessNormalization(bool enable) {
    _handler.toggleLoudnessNormalization(enable);
    state = state.copyWith(isLoudnessNormalizerEnabled: enable);
  }

  Future<void> stop() async {
    await audioHandler.stop();
    cancelSleepTimer();
    state = const PlayerState();
  }

  @override
  void dispose() {
    _playbackStateSub?.cancel();
    _mediaItemSub?.cancel();
    _sleepTimer?.cancel();
    super.dispose();
  }
}
