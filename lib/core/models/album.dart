class Album {
  final String id;
  final String name;
  final int createdAt;
  final String? coverColor;
  final int clipCount;

  const Album({
    required this.id,
    required this.name,
    required this.createdAt,
    this.coverColor,
    this.clipCount = 0,
  });

  factory Album.fromMap(Map<String, dynamic> map, {int clipCount = 0}) {
    return Album(
      id: map['id'] as String,
      name: map['name'] as String,
      createdAt: map['created_at'] as int,
      coverColor: map['cover_color'] as String?,
      clipCount: clipCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'created_at': createdAt,
      'cover_color': coverColor,
    };
  }

  Album copyWith({
    String? id,
    String? name,
    int? createdAt,
    String? coverColor,
    int? clipCount,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      coverColor: coverColor ?? this.coverColor,
      clipCount: clipCount ?? this.clipCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Album && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
