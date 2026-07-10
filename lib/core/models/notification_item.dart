class NotificationItem {
  final String id;
  final String title;
  final String body;
  final int timestamp; // Milliseconds since epoch
  final bool isRead;
  final String type; // extraction, download, import, update, feature, promotion, reward, error

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'timestamp': timestamp,
      'is_read': isRead ? 1 : 0,
      'type': type,
    };
  }

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      timestamp: map['timestamp'] as int,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      type: map['type'] as String,
    );
  }

  NotificationItem copyWith({
    String? id,
    String? title,
    String? body,
    int? timestamp,
    bool? isRead,
    String? type,
  }) {
    return NotificationItem(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      type: type ?? this.type,
    );
  }
}
