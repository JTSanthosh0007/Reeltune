import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/album_repository.dart';
import '../../core/db/clip_repository.dart';
import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../albums/album_providers.dart';
import 'LocalAudioRepository.dart';

enum ImportStatus { idle, scanning, success, failure }

class ImportState {
  final ImportStatus status;
  final int scannedCount;
  final String? errorMessage;

  ImportState({
    required this.status,
    this.scannedCount = 0,
    this.errorMessage,
  });

  ImportState copyWith({
    ImportStatus? status,
    int? scannedCount,
    String? errorMessage,
  }) {
    return ImportState(
      status: status ?? this.status,
      scannedCount: scannedCount ?? this.scannedCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final importProvider = StateNotifierProvider<ImportNotifier, ImportState>((ref) {
  return ImportNotifier(
    ref.watch(localAudioRepositoryProvider),
    ref.watch(clipRepositoryProvider),
    ref.watch(albumRepositoryProvider),
    ref,
  );
});

class ImportNotifier extends StateNotifier<ImportState> {
  final LocalAudioRepository _localAudioRepo;
  final ClipRepository _clipRepo;
  final AlbumRepository _albumRepo;
  final Ref _ref;

  ImportNotifier(
    this._localAudioRepo,
    this._clipRepo,
    this._albumRepo,
    this._ref,
  ) : super(ImportState(status: ImportStatus.idle));

  Future<void> scanAndImportLocalSongs() async {
    state = state.copyWith(status: ImportStatus.scanning, scannedCount: 0);

    try {
      // 1. Get or create fallback Device Songs album
      final albums = await _albumRepo.getAllAlbums();
      Album? fallbackAlbum = albums.firstWhere(
        (a) => a.name.toLowerCase() == 'device songs',
        orElse: () => Album(id: '', name: '', createdAt: 0),
      );

      if (fallbackAlbum.id.isEmpty) {
        fallbackAlbum = await _albumRepo.createAlbum(
          'Device Songs',
          coverColor: '0xFF4CAF50', // Premium Green matching ReelTune theme
        );
      }

      // 2. Scan storage songs
      final songs = await _localAudioRepo.scanDeviceSongs(
        defaultAlbumId: fallbackAlbum.id.isEmpty ? 'device_songs' : fallbackAlbum.id,
      );

      if (songs.isEmpty) {
        state = state.copyWith(status: ImportStatus.success, scannedCount: 0);
        return;
      }

      int importCount = 0;
      // Group dynamically by their original album name
      final Map<String, Album> albumCache = {};
      for (final a in await _albumRepo.getAllAlbums()) {
        albumCache[a.name.toLowerCase()] = a;
      }

      for (final song in songs) {
        String targetAlbumId = song.albumId;
        final rawAlbumName = song.albumName;

        if (rawAlbumName != null && rawAlbumName.isNotEmpty && rawAlbumName.toLowerCase() != 'unknown album') {
          final cacheKey = rawAlbumName.toLowerCase();
          if (albumCache.containsKey(cacheKey)) {
            targetAlbumId = albumCache[cacheKey]!.id;
          } else {
            // Create a new album representing the local MediaStore album!
            final newAlbum = await _albumRepo.createAlbum(rawAlbumName);
            albumCache[cacheKey] = newAlbum;
            targetAlbumId = newAlbum.id;
          }
        }

        // Insert song into database
        final clipToInsert = song.copyWith(albumId: targetAlbumId);
        await _clipRepo.insertClip(clipToInsert);
        importCount++;
      }

      // Invalidate album list provider to refresh UI
      _ref.invalidate(albumsProvider);

      state = state.copyWith(
        status: ImportStatus.success,
        scannedCount: importCount,
      );
    } catch (e) {
      state = state.copyWith(
        status: ImportStatus.failure,
        errorMessage: e.toString(),
      );
    }
  }
}
