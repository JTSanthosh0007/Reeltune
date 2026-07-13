import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/db/clip_repository.dart';
import '../albums/album_providers.dart';
import '../../main.dart'; // import global audioHandler
import 'audio_handler.dart'; // import ReelTuneAudioHandler
import '../../core/constants.dart';
import '../../core/network/music_resolver_service.dart';
import 'package:dio/dio.dart';

// Position update throttle interval
const _positionThrottleMs = 500;

// --- Player state ---
class PlayerState {
  final Clip? currentClip;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final AudioServiceRepeatMode repeatMode;
  final bool isLoading;
  final double speed;
  final Duration? sleepTimerRemaining;
  final bool isBassBoostEnabled;
  final bool isTrebleBoostEnabled;
  final bool isVocalEnabled;
  final bool isLoudnessNormalizerEnabled;
  final bool isShuffleEnabled;
  final String equalizerPreset;
  final List<double> equalizerGains;

  const PlayerState({
    this.currentClip,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.repeatMode = AudioServiceRepeatMode.none,
    this.isLoading = false,
    this.speed = 1.0,
    this.sleepTimerRemaining,
    this.isBassBoostEnabled = false,
    this.isTrebleBoostEnabled = false,
    this.isVocalEnabled = false,
    this.isLoudnessNormalizerEnabled = false,
    this.isShuffleEnabled = false,
    this.equalizerPreset = 'Normal',
    this.equalizerGains = const [0.0, 0.0, 0.0, 0.0, 0.0],
  });

  bool get isLooping => repeatMode == AudioServiceRepeatMode.one;

  PlayerState copyWith({
    Clip? currentClip,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    AudioServiceRepeatMode? repeatMode,
    bool? isLoading,
    double? speed,
    Duration? Function()? sleepTimerRemaining,
    bool? isBassBoostEnabled,
    bool? isTrebleBoostEnabled,
    bool? isVocalEnabled,
    bool? isLoudnessNormalizerEnabled,
    bool? isShuffleEnabled,
    String? equalizerPreset,
    List<double>? equalizerGains,
  }) {
    return PlayerState(
      currentClip: currentClip ?? this.currentClip,
      isPlaying: isPlaying ?? this.isPlaying,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      repeatMode: repeatMode ?? this.repeatMode,
      isLoading: isLoading ?? this.isLoading,
      speed: speed ?? this.speed,
      sleepTimerRemaining: sleepTimerRemaining != null ? sleepTimerRemaining() : this.sleepTimerRemaining,
      isBassBoostEnabled: isBassBoostEnabled ?? this.isBassBoostEnabled,
      isTrebleBoostEnabled: isTrebleBoostEnabled ?? this.isTrebleBoostEnabled,
      isVocalEnabled: isVocalEnabled ?? this.isVocalEnabled,
      isLoudnessNormalizerEnabled: isLoudnessNormalizerEnabled ?? this.isLoudnessNormalizerEnabled,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      equalizerPreset: equalizerPreset ?? this.equalizerPreset,
      equalizerGains: equalizerGains ?? this.equalizerGains,
    );
  }

  bool get hasClip => currentClip != null;

  double get progress {
    if (duration.inMilliseconds == 0) return 0;
    return position.inMilliseconds / duration.inMilliseconds;
  }
}

const Map<String, List<double>> equalizerPresets = {
  'Normal': [0.0, 0.0, 0.0, 0.0, 0.0],
  'Bass Boost': [10.0, 6.0, 0.0, 0.0, 0.0],
  'Treble Boost': [0.0, 0.0, 0.0, 6.0, 10.0],
  'Vocal': [-3.0, 0.0, 7.0, 5.0, -3.0],
  'Rock': [5.0, 3.0, -1.0, 3.0, 5.0],
  'Pop': [-2.0, -1.0, 3.0, 2.0, -1.0],
  'Jazz': [4.0, 2.0, -2.0, 2.0, 4.0],
  'Classical': [5.0, 3.0, -2.0, 4.0, 4.0],
};

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
  String? _lastLoggedClipId;

  List<Clip> _currentQueue = [];
  int _currentIndex = 0;

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _initListeners();
    _restoreQueueState();
    _restoreEqualizerState();

    // Bind audio handler notification actions back to notifier
    _handler.onSkipToNext = () => skipToNext();
    _handler.onSkipToPrevious = () => skipToPrevious();
    _handler.onSkipToQueueItem = (index) => playIndex(index);
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

      // Log immediately when playback starts
      if (stateEvent.playing && state.currentClip != null && state.currentClip!.id != _lastLoggedClipId) {
        _lastLoggedClipId = state.currentClip!.id;
        _ref.read(clipRepositoryProvider).updateLastPlayed(state.currentClip!.id);
        _ref.invalidate(recentClipsProvider);
      }

      final shouldThrottle = positionChanged &&
          now.difference(_lastPositionUpdate).inMilliseconds < _positionThrottleMs;

      // Always update play/loading state immediately, but throttle pure position-only updates
      if (shouldThrottle &&
          stateEvent.playing == state.isPlaying &&
          isLoading == state.isLoading) {
        return;
      }

      if (positionChanged) {
        _lastPositionUpdate = now;
        _savePlaybackPosition();
      }

      state = state.copyWith(
        isPlaying: stateEvent.playing,
        isLoading: isLoading,
        speed: stateEvent.speed,
        repeatMode: stateEvent.repeatMode,
        isShuffleEnabled: stateEvent.shuffleMode == AudioServiceShuffleMode.all,
      );
    });

    // Listen to current media item
    _mediaItemSub = audioHandler.mediaItem.listen((item) {
      if (!mounted) return;

      if (item == null) {
        _lastClipId = null;
        _lastDuration = Duration.zero;
      } else {
        _lastClipId = item.id;
        _lastDuration = item.duration ?? Duration.zero;
        
        // Log immediately if already playing
        if (audioHandler.playbackState.value.playing && item.id != _lastLoggedClipId) {
          _lastLoggedClipId = item.id;
          _ref.read(clipRepositoryProvider).updateLastPlayed(item.id);
          _ref.invalidate(recentClipsProvider);
        }

        // Save current index
        final idx = _handler.player.currentIndex;
        if (idx != null) {
          _saveQueueIndex(idx);
        }
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
    _currentQueue = clips;
    _currentIndex = initialIndex;

    await playIndex(initialIndex);
    await _saveQueueState(clips, initialIndex);
  }

  Future<void> playIndex(int index) async {
    if (_currentQueue.isEmpty || index < 0 || index >= _currentQueue.length) return;
    _currentIndex = index;

    final clip = _currentQueue[index];

    // Synchronously set targeted clip to update UI and support instant navigation
    state = state.copyWith(
      currentClip: clip,
      isLoading: true,
      isPlaying: false,
      duration: clip.durationMs != null
          ? Duration(milliseconds: clip.durationMs!)
          : Duration.zero,
    );

    // Smooth volume fade-out/mute
    await _handler.player.setVolume(0.0);

    // Resolve the stream URL on-device
    final resolver = _ref.read(musicResolverServiceProvider);
    String? resolvedUrl;
    final isOnline = clip.filePath.isEmpty || clip.filePath.startsWith('http://') || clip.filePath.startsWith('https://');

    if (isOnline) {
      debugPrint('[Player] Resolving direct stream URL for online song: ${clip.title}');
      if (clip.sourcePlatform == 'youtube') {
        resolvedUrl = await resolver.resolveYoutubeStreamUrl(clip.id);
      } else {
        resolvedUrl = await resolver.resolveSongQueryToStreamUrl(clip.title, clip.artist ?? '');
      }
    } else {
      resolvedUrl = clip.filePath;
    }

    if (resolvedUrl == null) {
      debugPrint('[Player] Stream resolution failed. Skipping to next.');
      state = state.copyWith(isLoading: false);
      await skipToNext();
      return;
    }

    final List<MediaItem> mediaItems = [];
    final albums = _ref.read(albumsProvider).value ?? [];

    for (final c in _currentQueue) {
      Album? album;
      try {
        album = albums.firstWhere((a) => a.id == c.albumId);
      } catch (_) {
        album = null;
      }

      final isOnlineClip = c.filePath.isEmpty || c.filePath.startsWith('http://') || c.filePath.startsWith('https://');

      final mediaItem = MediaItem(
        id: c.id,
        title: c.title,
        album: c.sourcePlatform ?? 'ReelTune',
        artist: c.artist ?? 'Unknown Artist',
        duration: c.durationMs != null ? Duration(milliseconds: c.durationMs!) : null,
        artUri: album?.coverImagePath != null && album!.coverImagePath!.isNotEmpty
            ? Uri.file(album.coverImagePath!)
            : (isOnlineClip ? Uri.parse('https://i.ytimg.com/vi/${c.id}/hqdefault.jpg') : null),
        extras: {
          'albumId': c.albumId,
          'filePath': c.filePath,
        },
      );
      mediaItem.extras?['sourcePlatform'] = c.sourcePlatform;
      mediaItems.add(mediaItem);
    }

    // Set the queue on the audio handler
    _handler.queue.add(mediaItems);

    final activeMediaItem = mediaItems[index];
    _handler.mediaItem.add(activeMediaItem);

    try {
      final source = isOnline
          ? AudioSource.uri(Uri.parse(resolvedUrl), tag: activeMediaItem)
          : AudioSource.file(resolvedUrl, tag: activeMediaItem);

      await _handler.player.setAudioSource(source);
      _handler.play();
      _handler.fadeVolume(1.0, const Duration(milliseconds: 300));
      await _saveQueueIndex(index);
    } catch (e) {
      debugPrint('[Player] Playback error: $e');
      state = state.copyWith(isLoading: false);
      _handler.playbackState.add(_handler.playbackState.value.copyWith(
        errorMessage: 'Failed to load audio: $e',
      ));
    }
  }

  Future<void> playClip(Clip clip) async {
    await playQueue([clip], 0);
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _currentQueue.length || newIndex < 0 || newIndex >= _currentQueue.length) return;

    final item = _currentQueue.removeAt(oldIndex);
    _currentQueue.insert(newIndex, item);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    // Rebuild mediaItems for audio handler queue
    final List<MediaItem> mediaItems = [];
    final albums = _ref.read(albumsProvider).value ?? [];
    for (final c in _currentQueue) {
      Album? album;
      try {
        album = albums.firstWhere((a) => a.id == c.albumId);
      } catch (_) {
        album = null;
      }
      final isOnlineClip = c.filePath.isEmpty || c.filePath.startsWith('http://') || c.filePath.startsWith('https://');
      mediaItems.add(MediaItem(
        id: c.id,
        title: c.title,
        album: c.sourcePlatform ?? 'ReelTune',
        artist: c.artist ?? 'Unknown Artist',
        duration: c.durationMs != null ? Duration(milliseconds: c.durationMs!) : null,
        artUri: album?.coverImagePath != null && album!.coverImagePath!.isNotEmpty
            ? Uri.file(album.coverImagePath!)
            : (isOnlineClip ? Uri.parse('https://i.ytimg.com/vi/${c.id}/hqdefault.jpg') : null),
        extras: {
          'albumId': c.albumId,
          'filePath': c.filePath,
        },
      ));
    }
    _handler.queue.add(mediaItems);
    await _saveQueueState(_currentQueue, _currentIndex);
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
    final AudioServiceRepeatMode nextMode;
    switch (state.repeatMode) {
      case AudioServiceRepeatMode.none:
        nextMode = AudioServiceRepeatMode.all;
        break;
      case AudioServiceRepeatMode.all:
        nextMode = AudioServiceRepeatMode.one;
        break;
      case AudioServiceRepeatMode.one:
      default:
        nextMode = AudioServiceRepeatMode.none;
        break;
    }
    audioHandler.setRepeatMode(nextMode);
  }

  void toggleShuffle() {
    final nextMode = state.isShuffleEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all;
    audioHandler.setShuffleMode(nextMode);
  }

  Future<void> skipToNext() async {
    if (_currentQueue.isEmpty) return;
    final nextIndex = (_currentIndex + 1) % _currentQueue.length;
    await playIndex(nextIndex);
  }

  Future<void> skipToPrevious() async {
    if (_currentQueue.isEmpty) return;
    final prevIndex = (_currentIndex - 1 + _currentQueue.length) % _currentQueue.length;
    await playIndex(prevIndex);
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

  Future<void> _saveQueueState(List<Clip> clips, int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = clips.map((c) => c.id).toList();
      await prefs.setStringList('reeltune_queue_ids', ids);
      await prefs.setInt('reeltune_queue_index', index);
    } catch (e) {
      debugPrint('Error saving queue state: $e');
    }
  }

  Future<void> _saveQueueIndex(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('reeltune_queue_index', index);
    } catch (e) {
      debugPrint('Error saving queue index: $e');
    }
  }

  Future<void> _savePlaybackPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pos = _handler.player.position.inMilliseconds;
      await prefs.setInt('reeltune_queue_position', pos);
    } catch (e) {
      debugPrint('Error saving position: $e');
    }
  }

  Future<void> _restoreQueueState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIds = prefs.getStringList('reeltune_queue_ids');
      if (savedIds == null || savedIds.isEmpty) return;

      final savedIndex = prefs.getInt('reeltune_queue_index') ?? 0;
      final savedPosition = prefs.getInt('reeltune_queue_position') ?? 0;

      final allClips = await _ref.read(clipRepositoryProvider).getAllClips();
      final Map<String, Clip> clipMap = {for (final c in allClips) c.id: c};
      final List<Clip> restoredClips = [];
      for (final id in savedIds) {
        if (clipMap.containsKey(id)) {
          restoredClips.add(clipMap[id]!);
        }
      }

      if (restoredClips.isEmpty) return;

      _currentQueue = restoredClips;
      _currentIndex = savedIndex;

      final clip = restoredClips[savedIndex];
      String? resolvedUrl;
      final isOnline = clip.filePath.isEmpty || clip.filePath.startsWith('http://') || clip.filePath.startsWith('https://');

      if (isOnline) {
        final resolver = _ref.read(musicResolverServiceProvider);
        if (clip.sourcePlatform == 'youtube') {
          resolvedUrl = await resolver.resolveYoutubeStreamUrl(clip.id);
        } else {
          resolvedUrl = await resolver.resolveSongQueryToStreamUrl(clip.title, clip.artist ?? '');
        }
      } else {
        resolvedUrl = clip.filePath;
      }

      if (resolvedUrl != null) {
        final activeMediaItem = MediaItem(
          id: clip.id,
          title: clip.title,
          album: clip.sourcePlatform ?? 'ReelTune',
          artist: clip.artist ?? 'Unknown Artist',
          duration: clip.durationMs != null ? Duration(milliseconds: clip.durationMs!) : null,
          extras: {
            'albumId': clip.albumId,
            'filePath': clip.filePath,
          },
        );

        final List<MediaItem> mediaItems = [];
        final albums = _ref.read(albumsProvider).value ?? [];
        for (final c in restoredClips) {
          Album? album;
          try {
            album = albums.firstWhere((a) => a.id == c.albumId);
          } catch (_) {}
          final isOnlineClip = c.filePath.isEmpty || c.filePath.startsWith('http://') || c.filePath.startsWith('https://');
          mediaItems.add(MediaItem(
            id: c.id,
            title: c.title,
            album: c.sourcePlatform ?? 'ReelTune',
            artist: c.artist ?? 'Unknown Artist',
            duration: c.durationMs != null ? Duration(milliseconds: c.durationMs!) : null,
            artUri: album?.coverImagePath != null && album!.coverImagePath!.isNotEmpty
                ? Uri.file(album.coverImagePath!)
                : (isOnlineClip ? Uri.parse('https://i.ytimg.com/vi/${c.id}/hqdefault.jpg') : null),
            extras: {
              'albumId': c.albumId,
              'filePath': c.filePath,
            },
          ));
        }

        _handler.queue.add(mediaItems);
        _handler.mediaItem.add(activeMediaItem);

        final source = isOnline
            ? AudioSource.uri(Uri.parse(resolvedUrl), tag: activeMediaItem)
            : AudioSource.file(resolvedUrl, tag: activeMediaItem);

        await _handler.player.setAudioSource(
          source,
          initialPosition: Duration(milliseconds: savedPosition),
        );

        state = state.copyWith(
          currentClip: clip,
          position: Duration(milliseconds: savedPosition),
          duration: clip.durationMs != null
              ? Duration(milliseconds: clip.durationMs!)
              : Duration.zero,
        );
      }
    } catch (e) {
      debugPrint('Error restoring queue state: $e');
    }
  }

  void setEqualizerPreset(String preset) {
    if (preset == 'Custom') {
      state = state.copyWith(equalizerPreset: preset);
      return;
    }
    final gains = equalizerPresets[preset] ?? const [0.0, 0.0, 0.0, 0.0, 0.0];
    _handler.setEqualizerPresetGains(gains);
    state = state.copyWith(
      equalizerPreset: preset,
      equalizerGains: gains,
    );
    _saveEqualizerState();
  }

  void setEqualizerBandGain(int band, double gain) {
    _handler.setEqualizerBand(band, gain);
    final nextGains = List<double>.from(state.equalizerGains);
    if (band < nextGains.length) {
      nextGains[band] = gain;
    }
    state = state.copyWith(
      equalizerPreset: 'Custom',
      equalizerGains: nextGains,
    );
    _saveEqualizerState();
  }

  Future<void> _saveEqualizerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('reeltune_eq_preset', state.equalizerPreset);
      final gainsStr = state.equalizerGains.map((g) => g.toString()).toList();
      await prefs.setStringList('reeltune_eq_gains', gainsStr);
    } catch (e) {
      debugPrint('Error saving EQ: $e');
    }
  }

  Future<void> _restoreEqualizerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preset = prefs.getString('reeltune_eq_preset') ?? 'Normal';
      final gainsStr = prefs.getStringList('reeltune_eq_gains');
      List<double> gains = const [0.0, 0.0, 0.0, 0.0, 0.0];
      if (gainsStr != null && gainsStr.length == 5) {
        gains = gainsStr.map((s) => double.tryParse(s) ?? 0.0).toList();
      } else if (equalizerPresets.containsKey(preset)) {
        gains = equalizerPresets[preset]!;
      }

      _handler.setEqualizerPresetGains(gains);
      state = state.copyWith(
        equalizerPreset: preset,
        equalizerGains: gains,
      );
    } catch (e) {
      debugPrint('Error restoring EQ: $e');
    }
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

// ResolvedYoutubeAudioSource removed. Single direct AudioSource used instead.
