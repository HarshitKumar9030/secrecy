import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, callLog }

enum MessageStatus { 
  sending,    // Message being sent
  sent,       // Message sent to server
  delivered,  // Message delivered to recipient(s)
  read        // Message read by recipient(s)
}

class Message {
  final String id;
  final String content;
  final MessageType type;
  final String? imageUrl;
  final String? videoUrl;
  final String? thumbnailUrl; // For video thumbnails
  final int? videoDuration; // Video duration in seconds
  final String senderId;
  final String senderEmail;
  final String senderName;
  final String? senderPhotoUrl; // Sender's profile picture
  final String? recipientId; // null for group chat, user ID for private chat
  final String? groupId; // ID of the group if this is a group message
  final DateTime timestamp;
  final bool isEdited;
  final DateTime? editedAt;  final bool isSystemMessage; // For system messages like "User joined group"
  final bool isOptimistic; // For optimistic updates (not yet confirmed by server)
  final MessageStatus status; // Message delivery status
  final Map<String, dynamic>? callLog; // Call log data for call log messages

  Message({
    required this.id,
    required this.content,
    this.type = MessageType.text,
    this.imageUrl,
    this.videoUrl,
    this.thumbnailUrl,
    this.videoDuration,
    required this.senderId,
    required this.senderEmail,
    required this.senderName,
    this.senderPhotoUrl,
    this.recipientId,
    this.groupId,
    required this.timestamp,
    this.isEdited = false,
    this.editedAt,
    this.isSystemMessage = false,
    this.isOptimistic = false,
    this.status = MessageStatus.sending,
    this.callLog,
  });
  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'type': type.toString().split('.').last,
      'imageUrl': imageUrl,
      'videoUrl': videoUrl,
      'thumbnailUrl': thumbnailUrl,
      'videoDuration': videoDuration,
      'senderId': senderId,
      'senderEmail': senderEmail,
      'senderName': senderName,
      'senderPhotoUrl': senderPhotoUrl,
      'recipientId': recipientId,
      'groupId': groupId,
      'timestamp': Timestamp.fromDate(timestamp),
      'isEdited': isEdited,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,      'isSystemMessage': isSystemMessage,
      'isOptimistic': isOptimistic,
      'status': status.toString().split('.').last,
      'callLog': callLog,
    };
  }
  factory Message.fromMap(Map<String, dynamic> map, String id) {
    return Message(
      id: id,
      content: map['content'] ?? map['text'] ?? '', // Handle both 'content' and 'text' fields
      type: MessageType.values.firstWhere(
        (e) => e.toString().split('.').last == (map['type'] ?? 'text'),
        orElse: () => MessageType.text,
      ),
      imageUrl: map['imageUrl'],
      videoUrl: map['videoUrl'],
      thumbnailUrl: map['thumbnailUrl'],
      videoDuration: map['videoDuration'],
      senderId: map['senderId'] ?? '',      senderEmail: map['senderEmail'] ?? '',
      senderName: map['senderName'] ?? '',
      senderPhotoUrl: map['senderPhotoUrl'],
      recipientId: map['recipientId'],
      groupId: map['groupId'],
      timestamp: _parseTimestamp(map['timestamp']),
      isEdited: map['isEdited'] ?? false,
      editedAt: map['editedAt'] != null ? _parseTimestamp(map['editedAt']) : null,
      isSystemMessage: map['isSystemMessage'] ?? false,
      isOptimistic: map['isOptimistic'] ?? false,
      status: MessageStatus.values.firstWhere(
        (e) => e.toString().split('.').last == (map['status'] ?? 'sending'),
        orElse: () => MessageStatus.sending,
      ),
      callLog: map['callLog'],
    );
  }

  static DateTime _parseTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      return timestamp.toDate();
    } else if (timestamp is String) {
      return DateTime.tryParse(timestamp) ?? DateTime.now();
    } else {
      return DateTime.now();
    }
  }  Message copyWith({
    String? id,
    String? content,
    bool? isEdited,
    DateTime? editedAt,
    bool? isOptimistic,
    MessageStatus? status,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      type: type,
      imageUrl: imageUrl,
      videoUrl: videoUrl,
      thumbnailUrl: thumbnailUrl,
      videoDuration: videoDuration,
      senderId: senderId,
      senderEmail: senderEmail,
      senderName: senderName,
      senderPhotoUrl: senderPhotoUrl,
      recipientId: recipientId,
      groupId: groupId,
      timestamp: timestamp,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      isSystemMessage: isSystemMessage,
      isOptimistic: isOptimistic ?? this.isOptimistic,
      status: status ?? this.status,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
