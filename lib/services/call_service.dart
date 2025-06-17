import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:uuid/uuid.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/call_model.dart';
import '../models/call_log.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  
  // Socket connection for real-time call events
  IO.Socket? _socket;
  
  // Current call state
  Call? _currentCall;
  StreamSubscription<DocumentSnapshot>? _callSubscription;
  final StreamController<Call?> _callStateController = StreamController<Call?>.broadcast();
  final StreamController<Map<String, dynamic>> _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Ringtone management
  bool _isRinging = false;
  Timer? _ringingTimer;
  Timer? _callTimeoutTimer;
  
  // Call timeout duration (should match server)
  static const int callTimeoutDuration = 45; // seconds
  static const int ringDuration = 30; // seconds
  
  Stream<Call?> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Call? get currentCall => _currentCall;
  bool get isInCall => _currentCall?.isActive == true;

  // Initialize call for 1-on-1 chat
  Future<String> initiateCall({
    required String recipientId,
    required String recipientName,
    required String recipientEmail,
    required CallType type,
    String? groupId,
    String? groupName,
    List<String>? additionalParticipants,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    if (_currentCall?.isActive == true) {
      throw Exception('Another call is already in progress');
    }

    final callId = _uuid.v4();
    List<String> participantIds = [user.uid, recipientId];
    Map<String, String> participantNames = {
      user.uid: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
      recipientId: recipientName,
    };

    if (additionalParticipants != null) {
      participantIds.addAll(additionalParticipants);
    }

    final call = Call(
      id: callId,
      callerId: user.uid,
      callerName: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
      callerEmail: user.email ?? '',
      callerPhotoUrl: user.photoURL,
      participantIds: participantIds,
      participantNames: participantNames,
      groupId: groupId,
      groupName: groupName,
      type: type,
      state: CallState.initiating,
      createdAt: DateTime.now(),
    );

    try {
      // Create call document
      await _firestore.collection('calls').doc(callId).set(call.toMap());
      
      // Update call state to ringing
      await _updateCallState(callId, CallState.ringing);
      
      // Start listening to call updates
      _listenToCall(callId);
      
      return callId;
    } catch (e) {
      print('Error initiating call: $e');
      rethrow;
    }
  }

  // Initialize socket connection for real-time call events
  void initializeSocket(String serverUrl) {
    _socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });
    
    _socket!.connect();
    
    // Listen for incoming calls
    _socket!.on('incoming-call', (data) {
      print('Incoming call received: $data');
      _handleIncomingCall(data);
    });
    
    // Listen for call accepted
    _socket!.on('call-accepted', (data) {
      print('Call accepted: $data');
      _handleCallAccepted(data);
    });
    
    // Listen for call rejected
    _socket!.on('call-rejected', (data) {
      print('Call rejected: $data');
      _handleCallRejected(data);
    });
    
    // Listen for call timeout
    _socket!.on('call-timeout', (data) {
      print('Call timeout: $data');
      _handleCallTimeout(data);
    });
    
    // Listen for call ended
    _socket!.on('call-ended', (data) {
      print('Call ended: $data');
      _handleCallEnded(data);
    });
    
    // Listen for participant busy
    _socket!.on('participant-busy', (data) {
      print('Participant busy: $data');
      _handleParticipantBusy(data);
    });
    
    // Listen for video/audio toggles
    _socket!.on('participant-video-toggle', (data) {
      _handleVideoToggle(data);
    });
    
    _socket!.on('participant-audio-toggle', (data) {
      _handleAudioToggle(data);
    });
    
    // Identify user to server
    final user = _auth.currentUser;
    if (user != null) {
      _socket!.emit('identify', {
        'userId': user.uid,
        'userEmail': user.email,
      });
    }
  }
  
  // Enhanced call initiation with socket support
  Future<String> initiateCallWithSocket({
    required String recipientId,
    required String recipientName,
    required String recipientEmail,
    required CallType type,
    String? groupId,
    String? groupName,
    List<String>? additionalParticipants,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    if (_currentCall?.isActive == true) {
      throw Exception('Another call is already in progress');
    }

    final callId = _uuid.v4();
    List<String> participantIds = [recipientId];
    
    if (additionalParticipants != null) {
      participantIds.addAll(additionalParticipants);
    }
    
    final isVideo = type == CallType.video;
    final isGroup = groupId != null || (additionalParticipants?.isNotEmpty == true);
      // Create call object
    final call = Call(
      id: callId,
      callerId: user.uid,
      callerName: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
      callerEmail: user.email ?? '',
      type: type,
      state: CallState.ringing,
      createdAt: DateTime.now(),
      participantIds: [user.uid, ...participantIds],
      participantNames: {
        user.uid: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
        recipientId: recipientName,
      },
      groupId: groupId,
      groupName: groupName,
    );
    
    _currentCall = call;
    _callStateController.add(call);
    
    // Initiate call via socket
    if (_socket != null && _socket!.connected) {
      _socket!.emit('initiate-call', {
        'roomId': callId,
        'callerId': user.uid,
        'callerName': user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
        'participantIds': participantIds,
        'isVideo': isVideo,
        'isGroup': isGroup,
      });
      
      // Start call timeout
      _startCallTimeout(callId);
    } else {
      // Fallback to Firestore method
      return initiateCall(
        recipientId: recipientId,
        recipientName: recipientName,
        recipientEmail: recipientEmail,
        type: type,
        groupId: groupId,
        groupName: groupName,
        additionalParticipants: additionalParticipants,
      );
    }
    
    return callId;
  }
  
  // Accept incoming call
  Future<void> acceptCall(String callId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    if (_socket != null && _socket!.connected) {
      _socket!.emit('accept-call', {
        'roomId': callId,
        'userId': user.uid,
      });
    }
    
    // Stop ringing
    _stopRinging();
      // Update call status
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        state: CallState.connected,
        startedAt: DateTime.now(),
      );
      _callStateController.add(_currentCall);
    }
  }
  
  // Reject/decline incoming call
  Future<void> rejectCall(String callId, {String reason = 'declined'}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    if (_socket != null && _socket!.connected) {
      _socket!.emit('reject-call', {
        'roomId': callId,
        'userId': user.uid,
        'reason': reason,
      });
    }
    
    // Stop ringing
    _stopRinging();
    
    // Clear current call
    _currentCall = null;
    _callStateController.add(null);
  }
  
  // End active call
  Future<void> endCall(String callId, {String reason = 'ended'}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    if (_socket != null && _socket!.connected) {
      _socket!.emit('end-call', {
        'roomId': callId,
        'endedBy': user.uid,
        'reason': reason,
      });
    }
    
    // Stop ringing and cleanup
    _stopRinging();
    _cancelCallTimeout();
      // Update call status
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        state: CallState.ended,
        endedAt: DateTime.now(),
        endReason: reason,
      );
      
      // Log the call
      await _logCall(_currentCall!);
      
      _currentCall = null;
      _callStateController.add(null);
    }
  }
  
  // Toggle video during call
  Future<void> toggleVideo(String callId, bool isVideoEnabled) async {
    if (_socket != null && _socket!.connected) {
      final user = _auth.currentUser;
      if (user != null) {
        _socket!.emit('toggle-video', {
          'roomId': callId,
          'userId': user.uid,
          'isVideoEnabled': isVideoEnabled,
        });
      }
    }
  }
  
  // Toggle audio during call
  Future<void> toggleAudio(String callId, bool isAudioEnabled) async {
    if (_socket != null && _socket!.connected) {
      final user = _auth.currentUser;
      if (user != null) {
        _socket!.emit('toggle-audio', {
          'roomId': callId,
          'userId': user.uid,
          'isAudioEnabled': isAudioEnabled,
        });
      }
    }
  }
  
  // Listen to call updates
  void _listenToCall(String callId) {
    _callSubscription?.cancel();
    _callSubscription = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final call = Call.fromMap(snapshot.data()!, snapshot.id);
        _currentCall = call;
        _callStateController.add(call);
        
        // Handle incoming call
        final user = _auth.currentUser;
        if (user != null && 
            call.callerId != user.uid && 
            call.participantIds.contains(user.uid) &&
            call.state == CallState.ringing) {
          _startRingtone();
        }
        
        // Handle call end
        if (call.isEnded) {
          _cleanup();
        }
      }
    });
  }
  // Start listening for incoming calls globally
  void startListeningForIncomingCalls() {
    final user = _auth.currentUser;
    if (user == null) return;

    _firestore.collection('calls')
        .where('participantIds', arrayContains: user.uid)
        .where('state', isEqualTo: 'ringing')
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final call = Call.fromMap(doc.data(), doc.id);
        
        // Only handle incoming calls (not calls we initiated)
        if (call.callerId != user.uid) {
          _currentCall = call;
          _callStateController.add(call);
          _startRingtone();
          
          // Set up listener for this specific call
          _listenToCall(call.id);
          break; // Only handle one incoming call at a time
        }
      }
    });
  }

  // Update call state
  Future<void> _updateCallState(
    String callId, 
    CallState state, {
    DateTime? startedAt,
    DateTime? endedAt,
    String? endReason,
  }) async {
    final updateData = <String, dynamic>{
      'state': state.toString().split('.').last,
    };
    
    if (startedAt != null) {
      updateData['startedAt'] = Timestamp.fromDate(startedAt);
    }
    
    if (endedAt != null) {
      updateData['endedAt'] = Timestamp.fromDate(endedAt);
    }
    
    if (endReason != null) {
      updateData['endReason'] = endReason;
    }
    
    await _firestore.collection('calls').doc(callId).update(updateData);
  }

  // Create call log
  Future<void> _createCallLog(String callId, CallLogStatus status) async {
    final call = _currentCall;
    if (call == null) return;
    
    final user = _auth.currentUser;
    if (user == null) return;

    // Create call log for each participant
    for (final participantId in call.participantIds) {
      final isIncoming = call.callerId != participantId;
      final otherParticipant = call.participantIds.firstWhere(
        (id) => id != participantId,
        orElse: () => call.callerId,
      );
      
      final callLog = CallLog(
        id: '${callId}_$participantId',
        callId: callId,
        type: isIncoming ? CallLogType.incoming : CallLogType.outgoing,
        status: status,
        isVideo: call.isVideoCall,
        participantId: otherParticipant,
        participantName: call.participantNames[otherParticipant] ?? '',
        participantEmail: call.callerEmail,
        groupId: call.groupId,
        groupName: call.groupName,
        timestamp: call.createdAt,
        duration: call.duration,
        userId: participantId,
      );
      
      await _firestore
          .collection('call_logs')
          .doc(callLog.id)
          .set(callLog.toMap());
    }
  }
  // Ringtone management
  void _startRingtone() {
    if (_isRinging) return;
    _isRinging = true;
    
    try {
      FlutterRingtonePlayer().playRingtone();
      
      // Auto-stop after 30 seconds
      _ringingTimer = Timer(const Duration(seconds: 30), () {
        _stopRingtone();
      });
    } catch (e) {
      print('Error playing ringtone: $e');
    }
  }

  void _stopRingtone() {
    if (!_isRinging) return;
    _isRinging = false;
    
    try {
      FlutterRingtonePlayer().stop();
      _ringingTimer?.cancel();
      _ringingTimer = null;
    } catch (e) {
      print('Error stopping ringtone: $e');
    }
  }

  // Check for missed calls
  void checkForMissedCalls() {
    final user = _auth.currentUser;
    if (user == null) return;

    _firestore
        .collection('calls')
        .where('participantIds', arrayContains: user.uid)
        .where('state', isEqualTo: 'ringing')
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final call = Call.fromMap(doc.data(), doc.id);
        
        // If call has been ringing for more than 30 seconds, mark as missed
        if (DateTime.now().difference(call.createdAt).inSeconds > 30) {
          _updateCallState(call.id, CallState.missed, endedAt: DateTime.now());
        }
      }
    });
  }  // Get call logs for a specific chat
  Stream<List<CallLog>> getCallLogsStream({String? recipientId, String? groupId}) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    if (groupId != null) {
      // Group call logs
      return _firestore.collection('call_logs')
          .where('groupId', isEqualTo: groupId)
          .orderBy('startedAt', descending: true)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return CallLog.fromMap(data, doc.id);
        }).toList();
      });
    } else if (recipientId != null) {
      // Private call logs - get calls involving current user
      return _firestore.collection('call_logs')
          .where('participants', arrayContains: user.uid)
          .orderBy('startedAt', descending: true)
          .snapshots()
          .map((snapshot) {
        // Filter client-side to get calls between current user and recipient
        return snapshot.docs
            .map((doc) {
              final data = doc.data();
              return CallLog.fromMap(data, doc.id);
            })
            .where((callLog) {
              final participants = List<String>.from(
                (snapshot.docs.firstWhere((doc) => doc.id == callLog.id).data()['participants'] as List? ?? [])
              );
              return participants.contains(recipientId);
            })
            .toList();
      });
    } else {
      // General chat - no call logs
      return Stream.value([]);
    }
  }

  // Get call logs for a specific chat (future version)
  Future<List<CallLog>> getCallLogs({String? recipientId, String? groupId, int limit = 50}) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    Query query = _firestore.collection('call_logs');

    if (groupId != null) {
      // Group call logs
      query = query.where('groupId', isEqualTo: groupId);
    } else if (recipientId != null) {
      // Private call logs - get calls between current user and recipient
      query = query.where('participants', arrayContains: user.uid)
          .where('participants', arrayContains: recipientId);
    } else {
      // General chat - no call logs
      return [];
    }

    final snapshot = await query
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return CallLog.fromMap(data, doc.id);
    }).toList();
  }

  // Cleanup
  void _cleanup() {
    _callSubscription?.cancel();
    _callSubscription = null;
    _currentCall = null;
    _callStateController.add(null);
    _stopRingtone();
  }

  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> data) {
    final callId = data['roomId'] as String;
    final callerId = data['callerId'] as String;
    final callerName = data['callerName'] as String;
    final isVideo = data['isVideo'] as bool? ?? false;
    final isGroup = data['isGroup'] as bool? ?? false;
    final participantIds = List<String>.from(data['participantIds'] ?? []);
    
    // Check if user is already in a call
    if (_currentCall?.isActive == true) {
      // User is busy, notify server
      if (_socket != null && _socket!.connected) {
        final user = _auth.currentUser;
        if (user != null) {
          _socket!.emit('call-busy', {
            'roomId': callId,
            'userId': user.uid,
          });
        }
      }
      return;
    }
    
    // Create incoming call object
    final call = Call(
      id: callId,
      initiatorId: callerId,
      initiatorName: callerName,
      recipientId: _auth.currentUser?.uid ?? '',
      recipientName: '',
      type: isVideo ? CallType.video : CallType.audio,
      status: CallStatus.ringing,
      createdAt: DateTime.now(),
      isActive: false,
      participantIds: [callerId, ..._auth.currentUser?.uid != null ? [_auth.currentUser!.uid] : [], ...participantIds],
      groupId: isGroup ? callId : null,
      groupName: isGroup ? 'Group Call' : null,
    );
    
    _currentCall = call;
    _callStateController.add(call);
    
    // Start ringing
    _startRinging();
    
    // Emit to incoming call stream for UI
    _incomingCallController.add({
      'call': call,
      'action': 'incoming',
    });
  }
  
  // Handle call accepted
  void _handleCallAccepted(Map<String, dynamic> data) {
    final callId = data['roomId'] as String;
    final acceptedBy = data['acceptedBy'] as String;
    
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        status: CallStatus.active,
        isActive: true,
        acceptedAt: DateTime.now(),
      );
      _callStateController.add(_currentCall);
      
      // Stop any ringing
      _stopRinging();
      _cancelCallTimeout();
    }
  }
  
  // Handle call rejected
  void _handleCallRejected(Map<String, dynamic> data) {
    final callId = data['roomId'] as String;
    final rejectedBy = data['rejectedBy'] as String;
    final reason = data['reason'] as String? ?? 'declined';
    
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        status: CallStatus.rejected,
        isActive: false,
      );
      
      // Log the call
      _logCall(_currentCall!);
      
      // Stop ringing and cleanup
      _stopRinging();
      _cancelCallTimeout();
      
      // Clear current call
      _currentCall = null;
      _callStateController.add(null);
      
      // Notify UI
      _incomingCallController.add({
        'action': 'rejected',
        'reason': reason,
        'rejectedBy': rejectedBy,
      });
    }
  }
  
  // Handle call timeout
  void _handleCallTimeout(Map<String, dynamic> data) {
    final callId = data['roomId'] as String;
    final reason = data['reason'] as String? ?? 'no_answer';
    
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        status: CallStatus.missed,
        isActive: false,
      );
      
      // Log the call
      _logCall(_currentCall!);
      
      // Stop ringing and cleanup
      _stopRinging();
      _cancelCallTimeout();
      
      // Clear current call
      _currentCall = null;
      _callStateController.add(null);
      
      // Notify UI
      _incomingCallController.add({
        'action': 'timeout',
        'reason': reason,
      });
    }
  }
  
  // Handle call ended
  void _handleCallEnded(Map<String, dynamic> data) {
    final callId = data['roomId'] as String;
    final endedBy = data['endedBy'] as String?;
    final reason = data['reason'] as String? ?? 'ended';
    
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        status: CallStatus.ended,
        isActive: false,
        endedAt: DateTime.now(),
      );
      
      // Log the call
      _logCall(_currentCall!);
      
      // Stop ringing and cleanup
      _stopRinging();
      _cancelCallTimeout();
      
      // Clear current call
      _currentCall = null;
      _callStateController.add(null);
      
      // Notify UI
      _incomingCallController.add({
        'action': 'ended',
        'reason': reason,
        'endedBy': endedBy,
      });
    }
  }
  
  // Handle participant busy
  void _handleParticipantBusy(Map<String, dynamic> data) {
    final busyUserId = data['busyUserId'] as String;
    
    // Notify UI that participant is busy
    _incomingCallController.add({
      'action': 'participant_busy',
      'busyUserId': busyUserId,
    });
  }
  
  // Handle video toggle
  void _handleVideoToggle(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final isVideoEnabled = data['isVideoEnabled'] as bool;
    
    // Notify UI about video toggle
    _incomingCallController.add({
      'action': 'video_toggle',
      'userId': userId,
      'isVideoEnabled': isVideoEnabled,
    });
  }
  
  // Handle audio toggle
  void _handleAudioToggle(Map<String, dynamic> data) {
    final userId = data['userId'] as String;
    final isAudioEnabled = data['isAudioEnabled'] as bool;
    
    // Notify UI about audio toggle
    _incomingCallController.add({
      'action': 'audio_toggle',
      'userId': userId,
      'isAudioEnabled': isAudioEnabled,
    });
  }
  
  // Start call timeout timer
  void _startCallTimeout(String callId) {
    _cancelCallTimeout(); // Cancel any existing timeout
    
    _callTimeoutTimer = Timer(Duration(seconds: callTimeoutDuration), () {
      // Call timed out
      _handleCallTimeout({
        'roomId': callId,
        'reason': 'timeout',
      });
    });
  }
  
  // Cancel call timeout timer
  void _cancelCallTimeout() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
  }
  
  // Enhanced ringing with timeout
  void _startRinging() {
    if (_isRinging) return;
    
    _isRinging = true;
    FlutterRingtonePlayer.playRingtone();
    
    // Auto-stop ringing after ring duration
    _ringingTimer = Timer(Duration(seconds: ringDuration), () {
      _stopRinging();
    });
  }
  
  // Stop ringing
  void _stopRinging() {
    if (!_isRinging) return;
    
    _isRinging = false;
    FlutterRingtonePlayer.stop();
    _ringingTimer?.cancel();
    _ringingTimer = null;
  }
  
  // Dispose socket connection
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _callSubscription?.cancel();
    _callStateController.close();
    _incomingCallController.close();
    _stopRinging();
    _cancelCallTimeout();
  }
}
