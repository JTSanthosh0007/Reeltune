import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/clip.dart';

final musicResolverServiceProvider = Provider<MusicResolverService>((ref) {
  return MusicResolverService();
});

class MusicResolverService {
  final _yt = YoutubeExplode();
  final _dio = Dio();

  String decodeHtmlEntities(String? str) {
    if (str == null) return '';
    return str
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&apos;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&middot;', '·');
  }

  /// Search YouTube Music directly from client
  Future<List<Clip>> searchYoutube(String query) async {
    try {
      final searchList = await _yt.search.search(query);
      final List<Clip> results = [];
      for (final video in searchList) {
        results.add(Clip(
          id: video.id.value,
          albumId: 'online',
          title: video.title,
          filePath: '',
          durationMs: video.duration?.inMilliseconds ?? 180000,
          sourceUrl: video.url,
          sourcePlatform: 'youtube',
          artist: video.author,
          albumName: 'YouTube Music',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      return results;
    } catch (e) {
      debugPrint('MusicResolverService.searchYoutube error: $e');
      return [];
    }
  }

  /// Search JioSaavn autocomplete API directly from client
  Future<List<Clip>> searchJioSaavn(String query) async {
    try {
      final saavnUrl = 'https://www.jiosaavn.com/api.php?__call=autocomplete.get&query=${Uri.encodeComponent(query)}&_format=json&_marker=0';
      final response = await _dio.get(
        saavnUrl,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['songs'] != null && data['songs']['data'] != null) {
          final songList = data['songs']['data'] as List<dynamic>;
          return songList.map<Clip>((item) {
            final song = item as Map<String, dynamic>;
            final rawImage = song['image'] as String? ?? '';
            final imageUrl = rawImage.replaceAll('50x50', '500x500').replaceAll('150x150', '500x500');
            final cleanTitle = decodeHtmlEntities(song['title'] as String?);
            final cleanArtist = decodeHtmlEntities(song['description'] as String? ?? 'Unknown Artist');

            return Clip(
              id: song['id'] as String? ?? UniqueKey().toString(),
              albumId: 'online',
              title: cleanTitle,
              filePath: '', // Empty path indicates online stream
              durationMs: 180000, // Default duration, resolved on play
              sourceUrl: song['url'] as String? ?? '',
              sourcePlatform: 'jiosaavn',
              artist: cleanArtist,
              albumName: decodeHtmlEntities(song['album'] as String? ?? 'JioSaavn'),
              genre: imageUrl,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('MusicResolverService.searchJioSaavn error: $e');
    }
    return [];
  }

  /// Search iTunes API directly from client
  Future<List<Clip>> searchAppleMusic(String query) async {
    try {
      final appleUrl = 'https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=10';
      final response = await _dio.get(appleUrl);

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        if (data is Map<String, dynamic> && data['results'] != null) {
          final results = data['results'] as List<dynamic>;
          return results.map<Clip>((item) {
            final track = item as Map<String, dynamic>;
            final rawImage = track['artworkUrl100'] as String? ?? '';
            final imageUrl = rawImage.replaceAll('100x100bb', '600x600bb');
            final cleanTitle = decodeHtmlEntities(track['trackName'] as String?);
            final cleanArtist = decodeHtmlEntities(track['artistName'] as String? ?? 'Unknown Artist');

            return Clip(
              id: (track['trackId']?.toString()) ?? UniqueKey().toString(),
              albumId: 'online',
              title: cleanTitle,
              filePath: '',
              durationMs: ((track['trackTimeMillis'] as num? ?? 180000)).toInt(),
              sourceUrl: track['trackViewUrl'] as String? ?? '',
              sourcePlatform: 'applemusic',
              artist: cleanArtist,
              albumName: decodeHtmlEntities(track['collectionName'] as String? ?? 'Apple Music'),
              genre: imageUrl,
              createdAt: DateTime.now().millisecondsSinceEpoch,
            );
          }).toList();
        }
      }
    } catch (e) {
      debugPrint('MusicResolverService.searchAppleMusic error: $e');
    }
    return [];
  }

  /// Resolve YouTube Direct Audio Stream URL for any videoId
  Future<String?> resolveYoutubeStreamUrl(String videoId) async {
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioOnlyStream = manifest.audioOnly.withHighestBitrate();
      return audioOnlyStream.url.toString();
    } catch (e) {
      debugPrint('MusicResolverService.resolveYoutubeStreamUrl error: $e');
      return null;
    }
  }

  /// Search YouTube for track, and resolve direct audio stream url
  Future<String?> resolveSongQueryToStreamUrl(String title, String artist) async {
    try {
      final query = '$title $artist';
      final searchList = await _yt.search.search(query);
      if (searchList.isNotEmpty) {
        final topVideo = searchList.first;
        return await resolveYoutubeStreamUrl(topVideo.id.value);
      }
    } catch (e) {
      debugPrint('MusicResolverService.resolveSongQueryToStreamUrl error: $e');
    }
    return null;
  }

  void dispose() {
    _yt.close();
  }
}
