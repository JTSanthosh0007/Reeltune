class Playlist {
  final String id;
  final String name;
  final int createdAt;

  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: map['created_at'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
    };
  }
}
