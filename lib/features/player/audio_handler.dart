import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

Future<AudioHandler> initAudioHandler() async {
  return await AudioService.init(
    builder: () => ReelTuneAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.reeltune.app.channel.audio',
      androidNotificationChannelName: 'ReelTune Playback',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true,
      androidNotificationIcon: 'drawable/ic_notification',
      notificationColor: Color(0xFF10B981), // Emerald green
    ),
  );
}

class ReelTuneAudioHandler extends BaseAudioHandler {
  late final AudioPlayer _player;

  // Equalizer and audio effects (Android-only native effects, simulated on iOS)
  AndroidEqualizer? _equalizer;
  AndroidLoudnessEnhancer? _loudnessEnhancer;

  ReelTuneAudioHandler() {
    _initEffects();
    _initPlayer();
    _initAudioSession();
  }

  AudioPlayer get player => _player;

  void _initPlayer() {
    // Forward playback states
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Watch position
    _player.positionStream.listen((pos) {
      if (mediaItem.value != null) {
        playbackState.add(playbackState.value.copyWith(
          updatePosition: pos,
        ));
      }
    });

    // Listen to current sequence index changes to update active metadata
    _player.currentIndexStream.listen((index) {
      if (index != null && _player.sequence != null && index < _player.sequence!.length) {
        final source = _player.sequence![index];
        if (source.tag is MediaItem) {
          mediaItem.add(source.tag as MediaItem);
        }
      }
    });

    // Dynamically update active MediaItem duration from player's stream
    _player.durationStream.listen((duration) {
      final currentItem = mediaItem.value;
      if (currentItem != null && duration != null && currentItem.duration != duration) {
        mediaItem.add(currentItem.copyWith(duration: duration));
      }
    });

    // Listen to processing state to handle completion
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Handle interruptions (phone calls, etc.) gracefully
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(0.2);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.pause:
            play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Handle audio becoming noisy (headphones unplugged)
    session.becomingNoisyEventStream.listen((_) {
      pause();
    });
  }

  void _initEffects() {
    try {
      _equalizer = AndroidEqualizer();
      _loudnessEnhancer = AndroidLoudnessEnhancer();
      
      final pipeline = AudioPipeline(
        androidAudioEffects: [
          _equalizer!,
          _loudnessEnhancer!,
        ],
      );
      _player = AudioPlayer(audioPipeline: pipeline);

      // Enable the effects explicitly so Android applies them
      _equalizer!.setEnabled(true).then((_) {
        debugPrint('Equalizer effect pipeline enabled successfully');
      }).catchError((err) {
        debugPrint('Warning: Equalizer effect failed to enable: $err');
      });

      _loudnessEnhancer!.setEnabled(true).then((_) {
        debugPrint('Loudness enhancement pipeline enabled successfully');
      }).catchError((err) {
        debugPrint('Warning: Loudness enhancer failed to enable: $err');
      });

    } catch (e) {
      // Audio effects pipeline not supported on this platform/version, fallback gracefully
      _equalizer = null;
      _loudnessEnhancer = null;
      _player = AudioPlayer();
    }
  }

  // --- Audio Engine Capabilities ---

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() => _player.seekToNext();

  @override
  Future<void> skipToPrevious() => _player.seekToPrevious();

  @override
  Future<void> stop() async {
    await _player.stop();
    await playbackState.firstWhere((state) => state.processingState == AudioProcessingState.idle);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        await _player.setLoopMode(LoopMode.off);
        break;
      case AudioServiceRepeatMode.one:
        await _player.setLoopMode(LoopMode.one);
        break;
      case AudioServiceRepeatMode.all:
        await _player.setLoopMode(LoopMode.all);
        break;
      case AudioServiceRepeatMode.group:
        break;
    }
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final bool enableShuffle = shuffleMode == AudioServiceShuffleMode.all;
    await _player.setShuffleModeEnabled(enableShuffle);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  ConcatenatingAudioSource? get playlistSource => _player.audioSource as ConcatenatingAudioSource?;

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final playlist = playlistSource;
    if (playlist == null) return;
    final source = AudioSource.file(mediaItem.extras?['filePath'] as String? ?? '', tag: mediaItem);
    await playlist.add(source);
    final newQueue = List<MediaItem>.from(queue.value)..add(mediaItem);
    queue.add(newQueue);
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final playlist = playlistSource;
    if (playlist == null) return;
    final index = queue.value.indexWhere((item) => item.id == mediaItem.id);
    if (index != -1) {
      await playlist.removeAt(index);
      final newQueue = List<MediaItem>.from(queue.value)..removeAt(index);
      queue.add(newQueue);
    }
  }

  Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    final playlist = playlistSource;
    if (playlist == null) return;
    await playlist.move(oldIndex, newIndex);
    final newQueue = List<MediaItem>.from(queue.value);
    final item = newQueue.removeAt(oldIndex);
    newQueue.insert(newIndex, item);
    queue.add(newQueue);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= queue.value.length) return;
    await _player.seek(Duration.zero, index: index);
  }

  // Play a specific item from path
  Future<void> playFromPath(String path, MediaItem item) async {
    mediaItem.add(item);
    try {
      final source = AudioSource.file(
        path,
        tag: item,
      );
      await _player.setAudioSource(source);
      play();
    } catch (e) {
      playbackState.add(playbackState.value.copyWith(
        errorMessage: 'Failed to load audio: $e',
      ));
    }
  }

  // Fade volume in/out
  Future<void> fadeVolume(double target, Duration duration) async {
    final double start = _player.volume;
    final int steps = 20;
    final double stepValue = (target - start) / steps;
    final Duration stepDuration = Duration(milliseconds: duration.inMilliseconds ~/ steps);

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(stepDuration);
      await _player.setVolume((start + stepValue * i).clamp(0.0, 1.0));
    }
  }

  // Enhancements Control (Equalizer & Bass Boost wrapper)
  void setEqualizerBand(int bandIndex, double gain) {
    final eq = _equalizer;
    if (eq == null) return;
    eq.parameters.then((params) {
      if (bandIndex < params.bands.length) {
        params.bands[bandIndex].setGain(gain);
      }
    });
  }

  void setEqualizerPresetGains(List<double> gains) {
    final eq = _equalizer;
    if (eq == null) return;
    eq.parameters.then((params) {
      for (int i = 0; i < gains.length; i++) {
        if (i < params.bands.length) {
          params.bands[i].setGain(gains[i]);
        }
      }
    });
  }

  void toggleBassBoost(bool enabled) {
    // Approximate Bass Boost by setting low frequencies (bands 0 and 1)
    final eq = _equalizer;
    if (eq == null) return;
    eq.parameters.then((params) {
      if (params.bands.length >= 2) {
        params.bands[0].setGain(enabled ? 12.0 : 0.0);
        params.bands[1].setGain(enabled ? 8.0 : 0.0);
      }
    });
  }

  void toggleTrebleBoost(bool enabled) {
    // Boost high frequencies (usually bands 3 and 4 in standard 5-band EQ)
    final eq = _equalizer;
    if (eq == null) return;
    eq.parameters.then((params) {
      final len = params.bands.length;
      if (len >= 5) {
        params.bands[len - 2].setGain(enabled ? 8.0 : 0.0);
        params.bands[len - 1].setGain(enabled ? 12.0 : 0.0);
      }
    });
  }

  void toggleVocalEnhancement(bool enabled) {
    // Boost mid-range frequencies (voice spectrum ~1kHz to 3kHz, bands 2 and 3)
    final eq = _equalizer;
    if (eq == null) return;
    eq.parameters.then((params) {
      final len = params.bands.length;
      if (len >= 5) {
        params.bands[1].setGain(enabled ? -2.0 : 0.0);
        params.bands[2].setGain(enabled ? 10.0 : 0.0);
        params.bands[3].setGain(enabled ? 8.0 : 0.0);
      }
    });
  }

  void toggleLoudnessNormalization(bool enabled) {
    final enhancer = _loudnessEnhancer;
    if (enhancer == null) return;
    enhancer.setEnabled(enabled);
    if (enabled) {
      enhancer.setTargetGain(1500); // 15 dB enhancement
    }
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      repeatMode: const {
        LoopMode.off: AudioServiceRepeatMode.none,
        LoopMode.one: AudioServiceRepeatMode.one,
        LoopMode.all: AudioServiceRepeatMode.all,
      }[_player.loopMode] ?? AudioServiceRepeatMode.none,
      shuffleMode: _player.shuffleModeEnabled
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
      queueIndex: event.currentIndex,
    );
  }
}
