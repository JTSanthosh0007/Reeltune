class Clip {
  final String id;
  final String albumId;
  final String title;
  final String filePath;
  final int? durationMs;
  final String? sourceUrl;
  final String? sourcePlatform;
  final int createdAt;

  const Clip({
    required this.id,
    required this.albumId,
    required this.title,
    required this.filePath,
    this.durationMs,
    this.sourceUrl,
    this.sourcePlatform,
    required this.createdAt,
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
