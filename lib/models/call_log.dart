import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

enum CallLogType { incoming, outgoing, missed }
enum CallLogStatus { completed, missed, declined, failed }

class CallLog {
  final String id;
  final String callId;
  final CallLogType type;
  final CallLogStatus status;
  final bool isVideo;
  final String participantId; // For 1-on-1 calls
  final String participantName;
  final String participantEmail;
  final String? groupId; // For group calls
  final String? groupName;
  final DateTime timestamp;
  final int? duration; // in seconds, null for missed/failed calls
  final String userId; // The user this log belongs to

  CallLog({
    required this.id,
    required this.callId,
    required this.type,
    required this.status,
    required this.isVideo,
    required this.participantId,
    required this.participantName,
    required this.participantEmail,
    this.groupId,
    this.groupName,
    required this.timestamp,
    this.duration,
    required this.userId,
  });

  factory CallLog.fromMap(Map<String, dynamic> map, String id) {
    return CallLog(
      id: id,
      callId: map['callId'] ?? '',
      type: CallLogType.values.firstWhere(
        (e) => e.toString() == 'CallLogType.${map['type']}',
        orElse: () => CallLogType.incoming,
      ),
      status: CallLogStatus.values.firstWhere(
        (e) => e.toString() == 'CallLogStatus.${map['status']}',
        orElse: () => CallLogStatus.completed,
      ),
      isVideo: map['isVideo'] ?? false,
      participantId: map['participantId'] ?? '',
      participantName: map['participantName'] ?? '',
      participantEmail: map['participantEmail'] ?? '',
      groupId: map['groupId'],
      groupName: map['groupName'],
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      duration: map['duration'],
      userId: map['userId'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'type': type.toString().split('.').last,
      'status': status.toString().split('.').last,
      'isVideo': isVideo,
      'participantId': participantId,
      'participantName': participantName,
      'participantEmail': participantEmail,
      'groupId': groupId,
      'groupName': groupName,
      'timestamp': Timestamp.fromDate(timestamp),
      'duration': duration,
      'userId': userId,
    };
  }

  String get formattedDuration {
    if (duration == null) return '';
    
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String get displayTitle {
    if (groupName != null) {
      return groupName!;
    }
    return participantName.isNotEmpty ? participantName : participantEmail.split('@')[0];
  }

  String get statusText {
    switch (status) {
      case CallLogStatus.completed:
        return formattedDuration;
      case CallLogStatus.missed:
        return 'Missed';
      case CallLogStatus.declined:
        return 'Declined';
      case CallLogStatus.failed:
        return 'Failed';
    }
  }

  IconData get statusIcon {
    if (status == CallLogStatus.missed) {
      return type == CallLogType.incoming ? Icons.call_received : Icons.call_made;
    }
    
    return isVideo ? Icons.videocam : Icons.call;
  }

  Color get statusColor {
    switch (status) {
      case CallLogStatus.completed:
        return const Color(0xFF0F8B0F);
      case CallLogStatus.missed:
        return const Color(0xFFE03E3E);
      case CallLogStatus.declined:
        return const Color(0xFFFF8800);
      case CallLogStatus.failed:
        return const Color(0xFFE03E3E);
    }
  }
}
