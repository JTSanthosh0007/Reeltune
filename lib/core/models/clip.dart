class Clip {
  final String id;
  final String albumId;
  final String title;
  final String filePath;
  final int? durationMs;
  final String? sourceUrl;
  final String? sourcePlatform;
  final int createdAt;
  final String? artist;
  final String? albumName;
  final int? bitrate;
  final int? fileSize;
  final String? genre;
  final int? year;
  final int? trackNumber;
  final bool isFavorite;
  final int? lastPlayedAt;

  const Clip({
    required this.id,
    required this.albumId,
    required this.title,
    required this.filePath,
    this.durationMs,
    this.sourceUrl,
    this.sourcePlatform,
    required this.createdAt,
    this.artist,
    this.albumName,
    this.bitrate,
    this.fileSize,
    this.genre,
    this.year,
    this.trackNumber,
    this.isFavorite = false,
    this.lastPlayedAt,
  });

  factory Clip.fromMap(Map<String, dynamic> map) {
    return Clip(
      id: map['id'] as String,
      albumId: map['album_id'] as String,
      title: map['title'] as String,
      filePath: map['file_path'] as String,
      durationMs: map['duration_ms'] as int?,
      sourceUrl: map['source_url'] as String?,
      sourcePlatform: map['source_platform'] as String?,
      createdAt: map['created_at'] as int,
      artist: map['artist'] as String?,
      albumName: map['album_name'] as String?,
      bitrate: map['bitrate'] as int?,
      fileSize: map['file_size'] as int?,
      genre: map['genre'] as String?,
      year: map['year'] as int?,
      trackNumber: map['track_number'] as int?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      lastPlayedAt: map['last_played_at'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'album_id': albumId,
      'title': title,
      'file_path': filePath,
      'duration_ms': durationMs,
      'source_url': sourceUrl,
      'source_platform': sourcePlatform,
      'created_at': createdAt,
      'artist': artist,
      'album_name': albumName,
      'bitrate': bitrate,
      'file_size': fileSize,
      'genre': genre,
      'year': year,
      'track_number': trackNumber,
      'is_favorite': isFavorite ? 1 : 0,
      'last_played_at': lastPlayedAt,
    };
  }

  Clip copyWith({
    String? id,
    String? albumId,
    String? title,
    String? filePath,
    int? durationMs,
    String? sourceUrl,
    String? sourcePlatform,
    int? createdAt,
    String? artist,
    String? albumName,
    int? bitrate,
    int? fileSize,
    String? genre,
    int? year,
    int? trackNumber,
    bool? isFavorite,
    int? lastPlayedAt,
  }) {
    return Clip(
      id: id ?? this.id,
      albumId: albumId ?? this.albumId,
      title: title ?? this.title,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourcePlatform: sourcePlatform ?? this.sourcePlatform,
      createdAt: createdAt ?? this.createdAt,
      artist: artist ?? this.artist,
      albumName: albumName ?? this.albumName,
      bitrate: bitrate ?? this.bitrate,
      fileSize: fileSize ?? this.fileSize,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      trackNumber: trackNumber ?? this.trackNumber,
      isFavorite: isFavorite ?? this.isFavorite,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }

  String get formattedDuration {
    if (durationMs == null) return '--:--';
    final duration = Duration(milliseconds: durationMs!);
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String get platformIcon {
    switch (sourcePlatform) {
      case 'instagram':
        return '📷';
      case 'tiktok':
        return '🎵';
      case 'youtube':
        return '▶️';
      default:
        return '🎧';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Clip && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
