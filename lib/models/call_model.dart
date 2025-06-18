import 'package:cloud_firestore/cloud_firestore.dart';

enum CallType { voice, video }
enum CallState { 
  // Call initiation states
  initiating,     // Call is being set up
  ringing,        // Call is ringing on recipient end
  
  // WebRTC negotiation states  
  connecting,     // WebRTC signaling in progress (offer/answer/ICE)
  connected,      // WebRTC peer connection established
  
  // Call termination states
  ended,          // Call ended normally
  declined,       // Call was declined by recipient
  missed,         // Call was not answered (timeout)
  failed,         // Call failed due to technical issues
  busy,           // Recipient is busy
  cancelled       // Call was cancelled by caller
}

class Call {
  final String id;
  final String callerId;
  final String callerName;
  final String callerEmail;
  final String? callerPhotoUrl;
  final List<String> participantIds;
  final Map<String, String> participantNames;
  final String? groupId;
  final String? groupName;
  final CallType type;
  final CallState state;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int? duration; // in seconds
  final String? endReason;

  Call({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.callerEmail,
    this.callerPhotoUrl,
    required this.participantIds,
    required this.participantNames,
    this.groupId,
    this.groupName,
    required this.type,
    required this.state,
    required this.createdAt,
    this.startedAt,
    this.endedAt,
    this.duration,
    this.endReason,
  });

  factory Call.fromMap(Map<String, dynamic> map, String id) {
    return Call(
      id: id,
      callerId: map['callerId'] ?? '',
      callerName: map['callerName'] ?? '',
      callerEmail: map['callerEmail'] ?? '',
      callerPhotoUrl: map['callerPhotoUrl'],
      participantIds: List<String>.from(map['participantIds'] ?? []),
      participantNames: Map<String, String>.from(map['participantNames'] ?? {}),
      groupId: map['groupId'],
      groupName: map['groupName'],
      type: CallType.values.firstWhere(
        (e) => e.toString() == 'CallType.${map['type']}',
        orElse: () => CallType.voice,
      ),
      state: CallState.values.firstWhere(
        (e) => e.toString() == 'CallState.${map['state']}',
        orElse: () => CallState.ended,
      ),
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      startedAt: map['startedAt'] != null ? (map['startedAt'] as Timestamp).toDate() : null,
      endedAt: map['endedAt'] != null ? (map['endedAt'] as Timestamp).toDate() : null,
      duration: map['duration'],
      endReason: map['endReason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerEmail': callerEmail,
      'callerPhotoUrl': callerPhotoUrl,
      'participantIds': participantIds,
      'participantNames': participantNames,
      'groupId': groupId,
      'groupName': groupName,
      'type': type.toString().split('.').last,
      'state': state.toString().split('.').last,
      'createdAt': Timestamp.fromDate(createdAt),
      'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
      'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      'duration': duration,
      'endReason': endReason,
    };
  }

  Call copyWith({
    String? id,
    String? callerId,
    String? callerName,
    String? callerEmail,
    String? callerPhotoUrl,
    List<String>? participantIds,
    Map<String, String>? participantNames,
    String? groupId,
    String? groupName,
    CallType? type,
    CallState? state,
    DateTime? createdAt,
    DateTime? startedAt,
    DateTime? endedAt,
    int? duration,
    String? endReason,
  }) {
    return Call(
      id: id ?? this.id,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerEmail: callerEmail ?? this.callerEmail,
      callerPhotoUrl: callerPhotoUrl ?? this.callerPhotoUrl,
      participantIds: participantIds ?? this.participantIds,
      participantNames: participantNames ?? this.participantNames,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      type: type ?? this.type,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      endReason: endReason ?? this.endReason,
    );
  }

  bool get isGroupCall => groupId != null;
  bool get isVideoCall => type == CallType.video;
  bool get isActive => state == CallState.ringing || state == CallState.connecting || state == CallState.connected;
  bool get isEnded => state == CallState.ended || state == CallState.declined || state == CallState.missed || state == CallState.failed;

  String get displayName {
    if (isGroupCall) {
      return groupName ?? 'Group Call';
    }
    return callerName.isNotEmpty ? callerName : callerEmail.split('@')[0];
  }

  String get formattedDuration {
    if (duration == null) return '';
    
    final minutes = duration! ~/ 60;
    final seconds = duration! % 60;
    
    if (minutes > 0) {
      return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
    } else {
      return '${seconds}s';
    }
  }
}
