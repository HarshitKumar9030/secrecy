import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:uuid/uuid.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/call_model.dart';
import '../models/call_log.dart';
import 'webrtc_service.dart';

class CallService extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  final WebRTCService _webrtcService = WebRTCService();
  
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
  Timer? _callTimeoutTimer;  // Call debouncing to prevent duplicates
  String? _lastProcessedCallId;
  DateTime? _lastCallTime;
  final Set<String> _loggedCallIds = <String>{};
  final Set<String> _declinedCallIds = <String>{};
  Timer? _cleanupTimer;
  
  // Hard block for persistent problematic calls
  final Set<String> _hardBlockedCallIds = {'eabae4b8-f238-431b-a5ac-bca6222f5ec5'};
    // Call timeout duration (should match server)
  static const int callTimeoutDuration = 45; // seconds
  static const int ringDuration = 30; // seconds
  
  // Server configuration - replace YOUR_VM_IP with actual server IP
  static const String signalingServerUrl = 'http://34.131.45.104:3000';
    Stream<Call?> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Call? get currentCall => _currentCall;
  bool get isInCall => _currentCall?.isActive == true;
  WebRTCService get webrtcService => _webrtcService;
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
    print('🔵 CallService.initiateCall() started');
    print('   recipientId: $recipientId');
    print('   recipientName: $recipientName');
    print('   type: $type');
    
    final user = _auth.currentUser;
    if (user == null) {
      print('❌ User not authenticated');
      throw Exception('User not authenticated');
    }

    if (_currentCall?.isActive == true) {
      print('❌ Another call already in progress');
      throw Exception('Another call is already in progress');
    }

    final callId = _uuid.v4();
    print('📞 Generated call ID: $callId');
    
    List<String> participantIds = [user.uid, recipientId];
    Map<String, String> participantNames = {
      user.uid: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
      recipientId: recipientName,
    };

    if (additionalParticipants != null) {
      participantIds.addAll(additionalParticipants);
    }    var call = Call(
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

    print('📱 Created call object with state: ${call.state}');

    try {
      // Enable wakelock when initiating call
      await WakelockPlus.enable();
      print('🔓 Wakelock enabled');
      
      // Set current call immediately for UI
      _currentCall = call;
      _callStateController.add(call);
      print('🎯 Call state updated to: ${call.state}');
      
      // Initialize socket if not already connected
      if (_socket == null || !_socket!.connected) {
        print('🔌 Initializing socket connection...');
        initializeSocket();
        await Future.delayed(Duration(milliseconds: 500)); // Give socket time to connect
      }
      
      // Update call state to ringing
      call = call.copyWith(state: CallState.ringing);
      _currentCall = call;
      _callStateController.add(call);
      print('📞 Call state updated to: ${call.state}');
      
      // Try Firestore first, but don't fail if it doesn't work
      try {
        await _firestore.collection('calls').doc(callId).set(call.toMap());
        await _updateCallState(callId, CallState.ringing);
        print('✅ Call saved to Firestore');
      } catch (e) {
        print('⚠️ Firestore failed, continuing with socket-only: $e');
      }
      
      // Start listening to call updates (local only if Firestore fails)
      _listenToCall(callId);
      
      // Emit call initiation to signaling server
      if (_socket != null && _socket!.connected) {
        print('📡 Emitting call to socket server...');
        _socket!.emit('initiate-call', {
          'roomId': callId,
          'callerId': user.uid,
          'callerName': user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
          'participantIds': participantIds.where((id) => id != user.uid).toList(),
          'isVideo': type == CallType.video,
          'isGroup': groupId != null || (additionalParticipants != null && additionalParticipants.isNotEmpty),
        });
        print('✅ Call initiated via socket');
      } else {
        print('❌ Socket not connected, call may not work properly');
      }

      // Start call timeout
      _startCallTimeout(callId);
      print('⏱️ Call timeout started');

      print('🎉 Call initiation completed successfully');
      return callId;
    } catch (e) {
      print('❌ Error initiating call: $e');
      // Disable wakelock on error
      await WakelockPlus.disable();
      // Clear call state on error
      _currentCall = null;
      _callStateController.add(null);
      rethrow;
    }
  }  // Initialize socket connection for real-time call events
  void initializeSocket([String? serverUrl]) {
    final url = serverUrl ?? signalingServerUrl;
    _socket = IO.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });
    
    _socket!.connect();
      // Start periodic cleanup of old call IDs (but preserve hard blocks)
    _cleanupTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _loggedCallIds.clear();
      _declinedCallIds.clear();
      // Note: _hardBlockedCallIds is NOT cleared - these persist
      print('🧹 Cleaned up old call IDs (hard blocks preserved)');
    });
    
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
  }    // Accept incoming call
  Future<void> acceptCall(String callId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // Enable wakelock to keep screen on during call
    await WakelockPlus.enable();
    
    // Join the call room
    joinCallRoom(callId);
    
    if (_socket != null && _socket!.connected) {
      _socket!.emit('accept-call', {
        'roomId': callId,
        'userId': user.uid,
      });
    }
    
    // Initialize WebRTC for the call
    if (_currentCall != null && _socket != null) {
      await _webrtcService.initialize(
        socket: _socket!,
        roomId: callId,
        isHost: false, // Receiver is not the host
        enableVideo: _currentCall!.type == CallType.video,
        enableAudio: true,
      );
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
      notifyListeners();
    }
  }
    // Reject/decline incoming call
  Future<void> rejectCall(String callId, {String reason = 'declined'}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // Disable wakelock
    await WakelockPlus.disable();
    
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
    notifyListeners();
  }    // End active call
  Future<void> endCall(String callId, {String reason = 'ended'}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    // End WebRTC call
    await _webrtcService.endCall();
    
    // Disable wakelock when call ends
    await WakelockPlus.disable();
    
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
      
      // Reset debouncing variables
      _lastProcessedCallId = null;
      _lastCallTime = null;
      
      notifyListeners();
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
          _startRinging();
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
          _startRinging();
          
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
  }  // Decline call
  Future<void> declineCall(String callId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      // Disable wakelock
      await WakelockPlus.disable();
      
      // Stop ringing
      _stopRinging();
      
      // Emit decline event to server
      if (_socket != null && _socket!.connected) {
        _socket!.emit('call-decline', {
          'roomId': callId,
          'userId': user.uid,
        });
      }
        // Update current call state
      if (_currentCall?.id == callId) {
        // Add to declined calls set
        _declinedCallIds.add(callId);
        
        _currentCall = _currentCall?.copyWith(
          state: CallState.declined,
          endedAt: DateTime.now(),
          endReason: 'declined',
        );
          // Log call
        if (_currentCall != null) {
          await _logCall(_currentCall!);
        }
            // Clear current call
      _currentCall = null;
      _callStateController.add(null);
      
      // Reset debouncing variables but keep declined call ID
      _lastProcessedCallId = null;
      _lastCallTime = null;
      
      notifyListeners();
      }
      
      print('Call declined: $callId');
    } catch (e) {
      print('Error declining call: $e');
    }
  }
  // Ringtone management with better error handling
  void _startRinging() {
    if (_isRinging) {
      print('🔔 Already ringing, skipping...');
      return;
    }
    
    _isRinging = true;
    
    try {
      FlutterRingtonePlayer().playRingtone();
      print('🔔 Ringtone started');
      
      // Auto-stop after 30 seconds
      _ringingTimer = Timer(const Duration(seconds: 30), () {
        print('🔔 Ringtone auto-stopped after 30 seconds');
        _stopRinging();
      });
    } catch (e) {
      print('❌ Error playing ringtone: $e');
      _isRinging = false;
    }
  }

  void _stopRinging() {
    if (!_isRinging) return;
    _isRinging = false;
    
    try {
      FlutterRingtonePlayer().stop();
      _ringingTimer?.cancel();
      _ringingTimer = null;
      print('🔔 Ringtone stopped');
    } catch (e) {
      print('❌ Error stopping ringtone: $e');
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
    }).toList();  }

  // Cleanup
  void _cleanup() {
    _callSubscription?.cancel();
    _callSubscription = null;
    _currentCall = null;
    _callStateController.add(null);
    _stopRinging();
  }
  
  // Log call to call history
  Future<void> _logCall(Call call) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      
      // Determine the other participant for 1-on-1 calls
      String participantId = '';
      String participantName = '';
      String participantEmail = '';
        if (!call.isGroupCall && call.participantIds.isNotEmpty) {
        // For 1-on-1 calls, find the other participant
        for (int i = 0; i < call.participantIds.length; i++) {
          if (call.participantIds[i] != user.uid) {
            participantId = call.participantIds[i];
            participantName = call.participantNames[call.participantIds[i]] ?? '';
            participantEmail = participantId; // Fallback
            break;
          }
        }
      }

      // Determine call log type based on current user's role
      CallLogType logType = CallLogType.incoming;
      if (call.callerId == user.uid) {
        logType = CallLogType.outgoing;
      }      // Determine status based on call state
      CallLogStatus logStatus = CallLogStatus.completed;
      if (call.state == CallState.ended) {
        switch (call.endReason) {
          case 'declined':
            logStatus = CallLogStatus.declined;
            break;
          case 'timeout':
          case 'noAnswer':
            logStatus = CallLogStatus.missed;
            break;
          case 'failed':
          case 'networkError':
            logStatus = CallLogStatus.failed;
            break;
          default:
            logStatus = CallLogStatus.completed;
        }
      } else if (call.state == CallState.declined) {
        logStatus = CallLogStatus.declined;
      } else if (call.state == CallState.missed) {
        logStatus = CallLogStatus.missed;
      } else if (call.state == CallState.failed) {
        logStatus = CallLogStatus.failed;
      }
        // Create call log entry
      final callLog = CallLog(
        id: _uuid.v4(), // Generate a proper ID
        callId: call.id,
        type: logType,
        status: logStatus,
        isVideo: call.type == CallType.video,
        participantId: call.isGroupCall ? '' : participantId,
        participantName: call.isGroupCall ? '' : participantName,
        participantEmail: call.isGroupCall ? '' : participantEmail,
        groupId: call.isGroupCall ? call.groupId : null,
        groupName: call.isGroupCall ? call.groupName : null,
        timestamp: call.createdAt,
        duration: call.duration,
        userId: user.uid,
      );        // Save to Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('call_logs')
          .doc(callLog.id)
          .set(callLog.toMap());
          
      // Also add the call log to the chat if it's a 1:1 call
      if (!call.isGroupCall && call.participantIds.length == 2) {
        final otherUserId = call.participantIds.firstWhere((id) => id != user.uid);
        final chatId = _getChatId(user.uid, otherUserId);
        
        // Ensure chatId is not empty before adding to chat
        if (chatId.isNotEmpty) {
          await _addCallLogToChat(chatId, callLog);
        } else {
          print('❌ Cannot add call log to chat: chatId is empty');
        }
      }
    } catch (e) {
      print('Error logging call: $e');
    }
  }
  
  // Helper method to generate consistent chat ID for 1:1 chats
  String _getChatId(String userId1, String userId2) {
    final sortedIds = [userId1, userId2]..sort();
    return '${sortedIds[0]}_${sortedIds[1]}';
  }
  // Add call log to chat messages
  Future<void> _addCallLogToChat(String chatId, CallLog callLog) async {
    try {
      // Validate inputs
      if (chatId.isEmpty) {
        print('❌ Cannot add call log: chatId is empty');
        return;
      }
      
      // Prevent duplicate call logs
      if (_loggedCallIds.contains(callLog.callId)) {
        print('🚫 Call log already added for call: ${callLog.callId}');
        return;
      }
      
      _loggedCallIds.add(callLog.callId);
      
      // Generate a proper document ID if callLog.id is empty
      String documentId = callLog.id.isNotEmpty ? callLog.id : _uuid.v4();
      
      final callLogData = {
        'id': documentId,
        'callId': callLog.callId,
        'type': callLog.type.toString().split('.').last,
        'status': callLog.status.toString().split('.').last,
        'isVideo': callLog.isVideo,
        'participantId': callLog.participantId,
        'participantName': callLog.participantName,
        'participantEmail': callLog.participantEmail,
        'groupId': callLog.groupId,
        'groupName': callLog.groupName,
        'timestamp': Timestamp.fromDate(callLog.timestamp),
        'duration': callLog.duration,
        'userId': callLog.userId,
        'messageType': 'call_log', // Special type to identify call logs
        'senderId': callLog.userId,
        'senderName': callLog.participantName,
        'senderEmail': callLog.participantEmail,
      };

      // Add to the chat's messages collection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(documentId)
          .set(callLogData);

      print('✅ Call log added to chat: $chatId');
    } catch (e) {
      print('❌ Error adding call log to chat: $e');
    }
  }  // Handle incoming call
  void _handleIncomingCall(Map<String, dynamic> data) {
    try {
      final callId = data['roomId'] as String;
      final callerId = data['callerId'] as String;
      final callerName = data['callerName'] as String;
      final isVideo = data['isVideo'] as bool? ?? false;
      final isGroup = data['isGroup'] as bool? ?? false;
      final participantIds = List<String>.from(data['participantIds'] ?? []);
        // Check for hard blocked calls (persistent problematic calls)
      if (_hardBlockedCallIds.contains(callId)) {
        print('🚫 HARD BLOCKED call ignored: $callId');
        return;
      }
      
      // Debounce duplicate calls
      final now = DateTime.now();
      if (_lastProcessedCallId == callId && 
          _lastCallTime != null && 
          now.difference(_lastCallTime!).inSeconds < 5) {
        print('🚫 Duplicate call ignored: $callId');
        return;
      }
      
      // Check if this call was already declined
      if (_declinedCallIds.contains(callId)) {
        print('🚫 Already declined call ignored: $callId');
        return;
      }
      
      _lastProcessedCallId = callId;
      _lastCallTime = now;
      
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
        print('❌ User is busy, declined incoming call: $callId');
        return;
      }

      // Create incoming call object
      final call = Call(
        id: callId,
        callerId: callerId,
        callerName: callerName,
        callerEmail: '',
        type: isVideo ? CallType.video : CallType.voice,
        state: CallState.ringing,
        createdAt: DateTime.now(),
        participantIds: [callerId, ..._auth.currentUser?.uid != null ? [_auth.currentUser!.uid] : [], ...participantIds],
        participantNames: {
          callerId: callerName,
          if (_auth.currentUser?.uid != null) _auth.currentUser!.uid: _auth.currentUser?.displayName ?? '',
        },
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
      
      print('📞 Incoming call handled: $callId from $callerName');
    } catch (e) {
      print('❌ Error handling incoming call: $e');
    }
  }// Handle call accepted
  void _handleCallAccepted(Map<String, dynamic> data) async {
    final callId = data['roomId'] as String;
    
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        state: CallState.connected,
        startedAt: DateTime.now(),
      );
      _callStateController.add(_currentCall);
      
      // Join the call room
      joinCallRoom(callId);
      
      // Initialize WebRTC for the call (caller side)
      if (_socket != null) {
        await _webrtcService.initialize(
          socket: _socket!,
          roomId: callId,
          isHost: true, // Caller is the host
          enableVideo: _currentCall!.type == CallType.video,
          enableAudio: true,
        );
      }
      
      // Stop any ringing
      _stopRinging();
      _cancelCallTimeout();
      
      notifyListeners();
    }
  }
  
  // Handle call rejected
  void _handleCallRejected(Map<String, dynamic> data) {
    final callId = data['roomId'] as String;
    final rejectedBy = data['rejectedBy'] as String;
    final reason = data['reason'] as String? ?? 'declined';
    
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        state: CallState.declined,
        endReason: reason,
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
        state: CallState.missed,
        endReason: reason,
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
        state: CallState.ended,
        endedAt: DateTime.now(),
        endReason: reason,
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
    _callTimeoutTimer = null;  }

  // Dispose socket connection
  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _callSubscription?.cancel();    _callStateController.close();
    _incomingCallController.close();
    _stopRinging();
    _cancelCallTimeout();
    _cleanupTimer?.cancel();
    super.dispose();
  }

  // Join call room for WebRTC
  void joinCallRoom(String callId) {
    final user = _auth.currentUser;
    if (user != null && _socket != null && _socket!.connected) {
      _socket!.emit('join-room', {
        'roomId': callId,
        'userId': user.uid,
        'userName': user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
      });
    }
  }

  // Force terminate a persistent call (emergency cleanup)
  Future<void> forceTerminateCall(String callId) async {
    final user = _auth.currentUser;
    if (user == null) return;
      print('🚨 Force terminating persistent call: $callId');
    
    // Add to hard blocked calls to prevent any future processing
    _hardBlockedCallIds.add(callId);
    
    // Add to declined calls to prevent future processing
    _declinedCallIds.add(callId);
    
    // End WebRTC call
    await _webrtcService.endCall();
    
    // Stop all sounds and timers
    _stopRinging();
    _cancelCallTimeout();
    
    // Disable wakelock
    await WakelockPlus.disable();
    
    // Send multiple termination signals to server
    if (_socket != null && _socket!.connected) {
      // Send end call signal
      _socket!.emit('end-call', {
        'roomId': callId,
        'endedBy': user.uid,
        'reason': 'force_terminated',
      });
      
      // Send call decline signal
      _socket!.emit('call-decline', {
        'roomId': callId,
        'userId': user.uid,
        'reason': 'force_terminated',
      });
      
      // Send call rejected signal
      _socket!.emit('call-rejected', {
        'roomId': callId,
        'rejectedBy': user.uid,
        'reason': 'force_terminated',
      });
      
      // Leave the room
      _socket!.emit('leave-room', {
        'roomId': callId,
        'userId': user.uid,
      });
    }
    
    // Clear current call state
    _currentCall = null;
    _callStateController.add(null);
    
    // Reset all debouncing variables
    _lastProcessedCallId = null;
    _lastCallTime = null;
    
    notifyListeners();
    
    print('✅ Call $callId force terminated');
  }

  // Debug method - call this from console to immediately clear persistent call
  void clearPersistentCall() {
    print('🚨 EMERGENCY: Clearing persistent call');
    forceTerminateCall('eabae4b8-f238-431b-a5ac-bca6222f5ec5');
  }

  // Debug method - call this to immediately block the persistent call
  void blockPersistentCall() {
    print('🚨 EMERGENCY: Blocking persistent call');
    hardBlockCallId('eabae4b8-f238-431b-a5ac-bca6222f5ec5');
    forceTerminateCall('eabae4b8-f238-431b-a5ac-bca6222f5ec5');
  }

  // Add a call ID to the hard block list
  void hardBlockCallId(String callId) {
    _hardBlockedCallIds.add(callId);
    _declinedCallIds.add(callId);
    print('🚫 Call ID $callId added to hard block list');
  }
}
