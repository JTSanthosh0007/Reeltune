import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';

import '../../core/models/clip.dart';
import '../../main.dart'; // import global audioHandler
import 'audio_handler.dart'; // import ReelTuneAudioHandler

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
  return PlayerNotifier();
});

class PlayerNotifier extends StateNotifier<PlayerState> {
  StreamSubscription<PlaybackState>? _playbackStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  Timer? _sleepTimer;

  PlayerNotifier() : super(const PlayerState()) {
    _initListeners();
  }

  ReelTuneAudioHandler get _handler => audioHandler as ReelTuneAudioHandler;

  void _initListeners() {
    // Listen to playback state from audio_service
    _playbackStateSub = audioHandler.playbackState.listen((stateEvent) {
      if (!mounted) return;

      final isLoading = stateEvent.processingState == AudioProcessingState.loading ||
          stateEvent.processingState == AudioProcessingState.buffering;

      state = state.copyWith(
        isPlaying: stateEvent.playing,
        position: stateEvent.updatePosition,
        isLoading: isLoading,
        speed: stateEvent.speed,
        isLooping: stateEvent.repeatMode == AudioServiceRepeatMode.one,
      );
    });

    // Listen to current media item
    _mediaItemSub = audioHandler.mediaItem.listen((item) {
      if (!mounted || item == null) return;

      // Extract Clip object properties back from MediaItem metadata
      final clip = Clip(
        id: item.id,
        albumId: '', // Detail not needed here
        title: item.title,
        filePath: '', // File path handled by backend
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

  Future<void> playClip(Clip clip) async {
    // Smooth volume fade-in
    await _handler.player.setVolume(0.0);

    final mediaItem = MediaItem(
      id: clip.id,
      title: clip.title,
      album: clip.sourcePlatform ?? 'ReelTune',
      duration: clip.durationMs != null ? Duration(milliseconds: clip.durationMs!) : null,
    );

    await _handler.playFromPath(clip.filePath, mediaItem);

    // Fade-in duration 300ms
    _handler.fadeVolume(1.0, const Duration(milliseconds: 300));
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
    final newPosition = state.position + offset;
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
