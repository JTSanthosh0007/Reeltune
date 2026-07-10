class Playlist {
  final String id;
  final String name;
  final int createdAt;
  final String? description;
  final String? coverImagePath;

  Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.description,
    this.coverImagePath,
  });

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: map['created_at'] as int,
      description: map['description'] as String?,
      coverImagePath: map['cover_image_path'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
      'description': description,
      'cover_image_path': coverImagePath,
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    int? createdAt,
    String? description,
    String? coverImagePath,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      description: description ?? this.description,
      coverImagePath: coverImagePath ?? this.coverImagePath,
    );
  }
}
