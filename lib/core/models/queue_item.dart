class QueueItem {
  final String id;
  final String url;
  final String? title;
  final String? artist;
  final String platform;
  final String status; // 'pending', 'downloading', 'completed', 'failed', 'paused'
  final double progress;
  final int createdAt;
  final String? error;
  final int priority;
  final double speed; // Download speed in KB/s
  final int eta;      // Estimated remaining seconds
  final int retries;  // Download retry attempts
  final String? playlistId;
  final String? albumId;

  const QueueItem({
    required this.id,
    required this.url,
    this.title,
    this.artist,
    required this.platform,
    required this.status,
    this.progress = 0.0,
    required this.createdAt,
    this.error,
    this.priority = 0,
    this.speed = 0.0,
    this.eta = 0,
    this.retries = 0,
    this.playlistId,
    this.albumId,
  });

  factory QueueItem.fromMap(Map<String, dynamic> map) {
    return QueueItem(
      id: map['id'] as String,
      url: map['url'] as String,
      title: map['title'] as String?,
      artist: map['artist'] as String?,
      platform: map['platform'] as String,
      status: map['status'] as String,
      progress: (map['progress'] as num? ?? 0.0).toDouble(),
      createdAt: map['created_at'] as int,
      error: map['error'] as String?,
      priority: map['priority'] as int? ?? 0,
      speed: (map['speed'] as num? ?? 0.0).toDouble(),
      eta: map['eta'] as int? ?? 0,
      retries: map['retries'] as int? ?? 0,
      playlistId: map['playlist_id'] as String?,
      albumId: map['album_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'artist': artist,
      'platform': platform,
      'status': status,
      'progress': progress,
      'created_at': createdAt,
      'error': error,
      'priority': priority,
      'speed': speed,
      'eta': eta,
      'retries': retries,
      'playlist_id': playlistId,
      'album_id': albumId,
    };
  }

  QueueItem copyWith({
    String? id,
    String? url,
    String? title,
    String? artist,
    String? platform,
    String? status,
    double? progress,
    int? createdAt,
    String? error,
    int? priority,
    double? speed,
    int? eta,
    int? retries,
    String? playlistId,
    String? albumId,
  }) {
    return QueueItem(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      error: error ?? this.error,
      priority: priority ?? this.priority,
      speed: speed ?? this.speed,
      eta: eta ?? this.eta,
      retries: retries ?? this.retries,
      playlistId: playlistId ?? this.playlistId,
      albumId: albumId ?? this.albumId,
    );
  }
}
