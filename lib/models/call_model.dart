import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { voice, video }
enum CallStatus { calling, ringing, answered, ended, declined, missed }

class CallModel {
  final String callId;
  final String callerId;
  final String callerName;
  final String callerEmail;
  final List<String> participantIds; // For group calls
  final CallType callType;
  final CallStatus status;
  final DateTime createdAt;
  final DateTime? answeredAt;
  final DateTime? endedAt;
  final int? duration; // in seconds
  final String? groupId; // For group calls
  final String? groupName; // For group calls
  final bool isGroupCall;
  final String? roomId; // WebRTC room/channel ID
  final Map<String, dynamic>? iceServers; // ICE servers configuration

  CallModel({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerEmail,
    required this.participantIds,
    required this.callType,
    required this.status,
    required this.createdAt,
    this.answeredAt,
    this.endedAt,
    this.duration,
    this.groupId,
    this.groupName,
    required this.isGroupCall,
    this.roomId,
    this.iceServers,
  });

  factory CallModel.fromMap(Map<String, dynamic> map) {
    return CallModel(
      callId: map['callId'] ?? '',
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerEmail: map['callerEmail'] ?? '',
      participantIds: List<String>.from(map['participantIds'] ?? []),
      callType: CallType.values.firstWhere(
        (e) => e.toString() == 'CallType.${map['callType']}',
        orElse: () => CallType.voice,
      ),
      status: CallStatus.values.firstWhere(
        (e) => e.toString() == 'CallStatus.${map['status']}',
        orElse: () => CallStatus.calling,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      answeredAt: map['answeredAt'] != null 
          ? (map['answeredAt'] as Timestamp).toDate() 
          : null,
      endedAt: map['endedAt'] != null 
          ? (map['endedAt'] as Timestamp).toDate() 
          : null,
      duration: map['duration'],
      groupId: map['groupId'],
      groupName: map['groupName'],
      isGroupCall: map['isGroupCall'] ?? false,
      roomId: map['roomId'],
      iceServers: map['iceServers'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'callerEmail': callerEmail,
      'participantIds': participantIds,
      'callType': callType.toString().split('.').last,
      'status': status.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'answeredAt': answeredAt != null ? Timestamp.fromDate(answeredAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'duration': duration,
      'groupId': groupId,
      'groupName': groupName,
      'isGroupCall': isGroupCall,
      'roomId': roomId,
      'iceServers': iceServers,
    };
  }

  CallModel copyWith({
    String? callId,
    String? callerId,
    String? callerName,
    String? callerEmail,
    List<String>? participantIds,
    CallType? callType,
    CallStatus? status,
    DateTime? createdAt,
    DateTime? answeredAt,
    DateTime? endedAt,
    int? duration,
    String? groupId,
    String? groupName,
    bool? isGroupCall,
    String? roomId,
    Map<String, dynamic>? iceServers,
  }) {
    return CallModel(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerEmail: callerEmail ?? this.callerEmail,
      participantIds: participantIds ?? this.participantIds,
      callType: callType ?? this.callType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      answeredAt: answeredAt ?? this.answeredAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      isGroupCall: isGroupCall ?? this.isGroupCall,
      roomId: roomId ?? this.roomId,
      iceServers: iceServers ?? this.iceServers,
    );
  }
}
