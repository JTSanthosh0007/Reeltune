import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/db/clip_repository.dart';
import '../../core/db/album_repository.dart';
import '../../core/db/queue_repository.dart';
import '../library/PlaylistRepository.dart';

import '../../core/models/clip.dart';
import '../../core/models/album.dart';
import '../../core/models/playlist.dart';
import '../../core/models/queue_item.dart';

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final clipRepo = ref.watch(clipRepositoryProvider);
  final albumRepo = ref.watch(albumRepositoryProvider);
  final playlistRepo = ref.watch(playlistRepositoryProvider);
  final queueRepo = ref.watch(queueRepositoryProvider);
  return SearchNotifier(clipRepo, albumRepo, playlistRepo, queueRepo);
});

class SearchState {
  final String query;
  final bool isLoading;
  final List<String> history;
  final List<Clip> songs;
  final List<Album> albums;
  final List<Playlist> playlists;
  final List<String> artists;
  final List<QueueItem> queue;

  SearchState({
    required this.query,
    required this.isLoading,
    required this.history,
    required this.songs,
    required this.albums,
    required this.playlists,
    required this.artists,
    required this.queue,
  });

  factory SearchState.initial() => SearchState(
        query: '',
        isLoading: false,
        history: [],
        songs: [],
        albums: [],
        playlists: [],
        artists: [],
        queue: [],
      );

  SearchState copyWith({
    String? query,
    bool? isLoading,
    List<String>? history,
    List<Clip>? songs,
    List<Album>? albums,
    List<Playlist>? playlists,
    List<String>? artists,
    List<QueueItem>? queue,
  }) {
    return SearchState(
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      history: history ?? this.history,
      songs: songs ?? this.songs,
      albums: albums ?? this.albums,
      playlists: playlists ?? this.playlists,
      artists: artists ?? this.artists,
      queue: queue ?? this.queue,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final ClipRepository _clipRepo;
  final AlbumRepository _albumRepo;
  final PlaylistRepository _playlistRepo;
  final QueueRepository _queueRepo;
  Timer? _debounce;

  SearchNotifier(
    this._clipRepo,
    this._albumRepo,
    this._playlistRepo,
    this._queueRepo,
  ) : super(SearchState.initial()) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('search_history') ?? [];
      state = state.copyWith(history: history);
    } catch (_) {}
  }

  Future<void> addToHistory(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = List<String>.from(state.history);
      history.remove(clean);
      history.insert(0, clean);
      final trimmed = history.take(20).toList();
      await prefs.setStringList('search_history', trimmed);
      state = state.copyWith(history: trimmed);
    } catch (_) {}
  }

  Future<void> removeFromHistory(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = List<String>.from(state.history);
      history.remove(query);
      await prefs.setStringList('search_history', history);
      state = state.copyWith(history: history);
    } catch (_) {}
  }

  Future<void> clearAllHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('search_history');
      state = state.copyWith(history: []);
    } catch (_) {}
  }

  void onQueryChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce?.cancel();
    state = state.copyWith(query: query, isLoading: query.isNotEmpty);

    if (query.trim().isEmpty) {
      state = state.copyWith(
        isLoading: false,
        songs: [],
        albums: [],
        playlists: [],
        artists: [],
        queue: [],
      );
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;

    try {
      final startTime = DateTime.now();

      final results = await Future.wait([
        _clipRepo.searchClips(cleanQuery),
        _albumRepo.searchAlbums(cleanQuery),
        _playlistRepo.searchPlaylists(cleanQuery),
        _queueRepo.getAllQueueItems(),
      ]);

      final allClips = results[0] as List<Clip>;
      final albums = results[1] as List<Album>;
      final playlists = results[2] as List<Playlist>;
      final allQueue = results[3] as List<QueueItem>;

      // Sort clips by scoring algorithm (Best Match -> Recent -> Favorite)
      allClips.sort((a, b) => _scoreClip(b, cleanQuery).compareTo(_scoreClip(a, cleanQuery)));

      // Filter queue items in memory
      final filteredQueue = allQueue.where((item) {
        final title = (item.title ?? '').toLowerCase();
        final artist = (item.artist ?? '').toLowerCase();
        final q = cleanQuery.toLowerCase();
        return title.contains(q) || artist.contains(q);
      }).toList();

      // Extract unique artists
      final matchingArtists = <String>{};
      for (final clip in allClips) {
        if (clip.artist != null &&
            clip.artist!.isNotEmpty &&
            clip.artist!.toLowerCase().contains(cleanQuery.toLowerCase()) &&
            clip.artist != 'Unknown Artist') {
          matchingArtists.add(clip.artist!);
        }
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('[UniversalSearch] Search completed in ${elapsed}ms');

      state = state.copyWith(
        isLoading: false,
        songs: allClips,
        albums: albums,
        playlists: playlists,
        artists: matchingArtists.toList(),
        queue: filteredQueue,
      );
    } catch (e) {
      debugPrint('[UniversalSearch] Search error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  int _scoreClip(Clip clip, String query) {
    final q = query.toLowerCase();
    final title = clip.title.toLowerCase();
    final artist = (clip.artist ?? '').toLowerCase();
    final album = (clip.albumName ?? '').toLowerCase();
    final genre = (clip.genre ?? '').toLowerCase();

    int score = 0;
    
    if (title == q) score += 100;
    else if (title.startsWith(q)) score += 50;
    else if (title.contains(q)) score += 20;

    if (artist == q) score += 80;
    else if (artist.startsWith(q)) score += 40;
    else if (artist.contains(q)) score += 15;

    if (album == q) score += 60;
    else if (album.startsWith(q)) score += 30;
    else if (album.contains(q)) score += 10;

    if (genre.contains(q)) score += 5;

    // Boost priority
    if (clip.isFavorite) score += 10;
    
    if (clip.lastPlayedAt != null) {
      final ageDays = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(clip.lastPlayedAt!)).inDays;
      if (ageDays < 10) {
        score += (10 - ageDays) * 2;
      }
    }

    return score;
  }
}
