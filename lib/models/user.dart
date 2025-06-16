class ChatUser {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? bio;
  final String? status; // Available, Busy, Away, etc.
  final DateTime lastSeen;
  final bool isOnline;
  final DateTime? joinedAt;

  ChatUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.status,
    required this.lastSeen,
    this.isOnline = false,
    this.joinedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'bio': bio,
      'status': status,
      'lastSeen': lastSeen.toIso8601String(),
      'isOnline': isOnline,
      'joinedAt': joinedAt?.toIso8601String(),
    };
  }

  factory ChatUser.fromMap(Map<String, dynamic> map, String id) {
    return ChatUser(
      id: id,
      email: map['email'] ?? '',
      displayName: map['displayName'] ?? '',
      photoUrl: map['photoUrl'],
      bio: map['bio'],
      status: map['status'],
      lastSeen: DateTime.tryParse(map['lastSeen'] ?? '') ?? DateTime.now(),
      isOnline: map['isOnline'] ?? false,
      joinedAt: map['joinedAt'] != null ? DateTime.tryParse(map['joinedAt']) : null,
    );
  }

  ChatUser copyWith({
    String? displayName,
    String? photoUrl,
    String? bio,
    String? status,
    DateTime? lastSeen,
    bool? isOnline,
  }) {
    return ChatUser(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      isOnline: isOnline ?? this.isOnline,
      joinedAt: joinedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatUser && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
