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

  LocalStreamServer? _streamServer;

  PlayerNotifier(this._ref) : super(const PlayerState()) {
    _initServer();
    _initListeners();
    _restoreQueueState();
    _restoreEqualizerState();
  }

  Future<void> _initServer() async {
    _streamServer = LocalStreamServer(_ref.read(musicResolverServiceProvider));
    await _streamServer!.start();
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

    for (int i = 0; i < clips.length; i++) {
      final clip = clips[i];
      Album? album;
      try {
        album = albums.firstWhere((a) => a.id == clip.albumId);
      } catch (_) {
        album = null;
      }

      final isOnline = clip.filePath.isEmpty || clip.filePath.startsWith('http://') || clip.filePath.startsWith('https://');

      final mediaItem = MediaItem(
        id: clip.id,
        title: clip.title,
        album: clip.sourcePlatform ?? 'ReelTune',
        artist: clip.artist ?? 'Unknown Artist',
        duration: clip.durationMs != null ? Duration(milliseconds: clip.durationMs!) : null,
        artUri: album?.coverImagePath != null && album!.coverImagePath!.isNotEmpty
            ? Uri.file(album.coverImagePath!)
            : (isOnline ? Uri.parse('https://i.ytimg.com/vi/${clip.id}/hqdefault.jpg') : null),
        extras: {
          'albumId': clip.albumId,
          'filePath': clip.filePath,
        },
      );
      mediaItem.extras?['sourcePlatform'] = clip.sourcePlatform;
      mediaItems.add(mediaItem);

      if (isOnline) {
        final localUrl = _streamServer?.getUrl(clip) ?? '';
        sources.add(AudioSource.uri(Uri.parse(localUrl), tag: mediaItem));
      } else {
        sources.add(AudioSource.file(clip.filePath, tag: mediaItem));
      }
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
      _saveQueueState(clips, initialIndex);
    } catch (e) {
      _handler.playbackState.add(_handler.playbackState.value.copyWith(
        errorMessage: 'Failed to load audio: $e',
      ));
    }
  }

  Future<void> playClip(Clip clip) async {
    await playQueue([clip], 0);
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    await _handler.moveQueueItem(oldIndex, newIndex);
    try {
      final currentQueue = _handler.queue.value;
      final allClips = await _ref.read(clipRepositoryProvider).getAllClips();
      final Map<String, Clip> clipMap = {for (final c in allClips) c.id: c};
      final List<Clip> restoredClips = [];
      for (final item in currentQueue) {
        if (clipMap.containsKey(item.id)) {
          restoredClips.add(clipMap[item.id]!);
        }
      }
      final activeIndex = _handler.player.currentIndex ?? 0;
      await _saveQueueState(restoredClips, activeIndex);
    } catch (e) {
      debugPrint('Error saving moved queue: $e');
    }
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

      final List<MediaItem> mediaItems = [];
      final List<AudioSource> sources = [];

      final albums = _ref.read(albumsProvider).value ?? [];

      for (final clip in restoredClips) {
        Album? album;
        try {
          album = albums.firstWhere((a) => a.id == clip.albumId);
        } catch (_) {}

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
        final isOnline = clip.filePath.isEmpty || clip.filePath.startsWith('http://') || clip.filePath.startsWith('https://');
        mediaItems.add(mediaItem);

        if (isOnline) {
          final localUrl = _streamServer?.getUrl(clip) ?? '';
          sources.add(AudioSource.uri(Uri.parse(localUrl), tag: mediaItem));
        } else {
          sources.add(AudioSource.file(clip.filePath, tag: mediaItem));
        }
      }

      _handler.queue.add(mediaItems);
      final playlist = ConcatenatingAudioSource(children: sources);
      
      await _handler.player.setAudioSource(
        playlist,
        initialIndex: savedIndex,
        initialPosition: Duration(milliseconds: savedPosition),
      );
      
      if (savedIndex < restoredClips.length) {
        final targetClip = restoredClips[savedIndex];
        state = state.copyWith(
          currentClip: targetClip,
          position: Duration(milliseconds: savedPosition),
          duration: targetClip.durationMs != null
              ? Duration(milliseconds: targetClip.durationMs!)
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
    _streamServer?.stop();
    super.dispose();
  }
}

class LocalStreamServer {
  HttpServer? _server;
  final MusicResolverService resolver;

  LocalStreamServer(this.resolver);

  Future<void> start() async {
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      debugPrint('[LocalStreamServer] Running on port ${_server!.port}');

      _server!.listen((HttpRequest request) async {
        try {
          final path = request.uri.path;
          if (path == '/stream') {
            final id = request.uri.queryParameters['id'] ?? '';
            final platform = request.uri.queryParameters['platform'] ?? '';
            final title = request.uri.queryParameters['title'] ?? '';
            final artist = request.uri.queryParameters['artist'] ?? '';

            debugPrint('[LocalStreamServer] Resolving stream query for "$title" - $artist ($platform)');
            String? streamUrl;
            if (platform == 'youtube') {
              streamUrl = await resolver.resolveYoutubeStreamUrl(id);
            } else {
              streamUrl = await resolver.resolveSongQueryToStreamUrl(title, artist);
            }

            if (streamUrl != null) {
              request.response.statusCode = HttpStatus.temporaryRedirect;
              request.response.headers.set(HttpHeaders.locationHeader, streamUrl);
              await request.response.close();
              debugPrint('[LocalStreamServer] 307 Redirect -> $streamUrl');
            } else {
              request.response.statusCode = HttpStatus.notFound;
              await request.response.close();
            }
          } else {
            request.response.statusCode = HttpStatus.notFound;
            await request.response.close();
          }
        } catch (e) {
          debugPrint('[LocalStreamServer] Request handler error: $e');
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
        }
      });
    } catch (e) {
      debugPrint('[LocalStreamServer] Failed to bind to loopback port: $e');
    }
  }

  String getUrl(Clip clip) {
    final port = _server?.port ?? 8080;
    return 'http://127.0.0.1:$port/stream?id=${clip.id}&platform=${clip.sourcePlatform}&title=${Uri.encodeComponent(clip.title)}&artist=${Uri.encodeComponent(clip.artist ?? "")}';
  }

  void stop() {
    _server?.close();
  }
}
