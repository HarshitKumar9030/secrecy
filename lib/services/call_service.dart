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
import 'video_sdk_permission_service.dart';

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
  Timer? _callTimeoutTimer;
  
  // Call debouncing to prevent duplicates
  String? _lastProcessedCallId;
  DateTime? _lastCallTime;
  final Set<String> _loggedCallIds = <String>{};
  final Set<String> _declinedCallIds = <String>{};
  Timer? _cleanupTimer;
  
  // Hard block for persistent problematic calls - PRODUCTION VERSION SHOULD BE EMPTY
  final Set<String> _hardBlockedCallIds = {'eabae4b8-f238-431b-a5ac-bca6222f5ec5'};
  
  // Call timeout duration (should match server)
  static const int callTimeoutDuration = 45; // seconds
  static const int ringDuration = 30; // seconds
  
  // Server configuration
  static const String signalingServerUrl = 'http://34.131.45.104:3000';
  
  // Getters
  Stream<Call?> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Call? get currentCall => _currentCall;
  bool get isInCall => _currentCall?.isActive == true;
  WebRTCService get webrtcService => _webrtcService;

  // Initialize call
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

    var call = Call(
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
      // Enable wakelock when initiating call
      await WakelockPlus.enable();
      
      // Set current call immediately for UI
      _currentCall = call;
      _callStateController.add(call);
      
      // Initialize socket if not already connected
      if (_socket == null || !_socket!.connected) {
        initializeSocket();
        await Future.delayed(Duration(milliseconds: 500));
      }
      
      // Update call state to ringing
      call = call.copyWith(state: CallState.ringing);
      _currentCall = call;
      _callStateController.add(call);
      
      // Try Firestore first, but don't fail if it doesn't work
      try {
        await _firestore.collection('calls').doc(callId).set(call.toMap());
        await _updateCallState(callId, CallState.ringing);
      } catch (e) {
        print('⚠️ Firestore failed, continuing with socket-only: $e');
      }
      
      // Start listening to call updates
      _listenToCall(callId);
      
      // Emit call initiation to signaling server
      if (_socket != null && _socket!.connected) {
        _socket!.emit('initiate-call', {
          'roomId': callId,
          'callerId': user.uid,
          'callerName': user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
          'participantIds': participantIds.where((id) => id != user.uid).toList(),
          'isVideo': type == CallType.video,
          'isGroup': groupId != null || (additionalParticipants != null && additionalParticipants.isNotEmpty),
        });
      }
      
      // Start call timeout
      _startCallTimeout(callId);
      
      return callId;
    } catch (e) {
      // Disable wakelock on error
      await WakelockPlus.disable();
      // Clear call state on error
      _currentCall = null;
      _callStateController.add(null);
      rethrow;
    }
  }

  // Initialize socket connection for real-time call events
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
    });
    
    // Listen for incoming calls
    _socket!.on('incoming-call', (data) {
      _handleIncomingCall(data);
    });
    
    // Listen for call accepted
    _socket!.on('call-accepted', (data) {
      _handleCallAccepted(data);
    });
    
    // Listen for call rejected
    _socket!.on('call-rejected', (data) {
      _handleCallRejected(data);
    });
    
    // Listen for call timeout
    _socket!.on('call-timeout', (data) {
      _handleCallTimeout(data);
    });
    
    // Listen for call ended
    _socket!.on('call-ended', (data) {
      _handleCallEnded(data);
    });
    
    // Listen for participant busy
    _socket!.on('participant-busy', (data) {
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
  // Accept incoming call
  Future<void> acceptCall(String callId) async {
    final user = _auth.currentUser;
    if (user == null) return;
    
    debugPrint('📞 Accepting call $callId');
    debugPrint('🔍 Current call state: ${_currentCall?.state}');
    
    // Enable wakelock to keep screen on during call
    await WakelockPlus.enable();
    
    // Stop ringing first
    _stopRinging();
    
    // Update call status to connecting
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(state: CallState.connecting);
      _callStateController.add(_currentCall);
      notifyListeners();
    }    // Initialize WebRTC for the call BEFORE emitting accept
    if (_currentCall != null && _socket != null) {
      debugPrint('Callee initializing WebRTC as non-host');
      
      // Request permissions before initializing WebRTC
      final permissionType = _currentCall!.type == CallType.video ? 
        PermissionType.audioVideo : PermissionType.audio;
      final hasPermissions = await VideoSDKPermissionService.ensurePermissions(permissionType);
      
      if (!hasPermissions) {
        debugPrint('Permissions denied for WebRTC');
        await declineCall(callId);
        return;
      }
        await _webrtcService.initialize(
        socket: _socket!,
        roomId: callId,
        isHost: false,
        enableVideo: _currentCall!.type == CallType.video,
        enableAudio: true,
      );
      
      debugPrint('✅ WebRTC initialized for callee, waiting for ready signal...');
    }
    
    // Join the call room
    joinCallRoom(callId);
    
    // Now emit accept event to server
    if (_socket != null && _socket!.connected) {
      _socket!.emit('accept-call', {
        'roomId': callId,
        'userId': user.uid,
      });
      debugPrint('Emitted accept-call event');
    }
    
    // Update call status to connected
    if (_currentCall?.id == callId) {
      _currentCall = _currentCall!.copyWith(
        state: CallState.connected,
        startedAt: DateTime.now(),
      );
      _callStateController.add(_currentCall);
      notifyListeners();
      debugPrint('Call state updated to connected for callee');
    }
  }

  // Decline call
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
        
        // Add to hard blocked calls to prevent future processing of this call
        _hardBlockedCallIds.add(callId);
        
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

  // End active call
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

  // Ringtone management
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
      }
      
      // Determine status based on call state
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
        id: _uuid.v4(),
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
      );
      
      // Save to Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('call_logs')
          .doc(callLog.id)
          .set(callLog.toMap());
    } catch (e) {
      print('Error logging call: $e');
    }
  }

  // Handle incoming call
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
  }
  // Handle call accepted
  void _handleCallAccepted(Map<String, dynamic> data) async {
    final callId = data['roomId'] as String;
    final acceptedBy = data['acceptedBy'] as String;
    final user = _auth.currentUser;
    
    debugPrint('📞 Call accepted for room $callId by $acceptedBy');
    debugPrint('🔍 Current call ID: ${_currentCall?.id}');
    debugPrint('👤 Current user ID: ${user?.uid}');
    debugPrint('📱 Is this caller: ${_currentCall?.callerId == user?.uid}');
    
    if (_currentCall?.id == callId) {
      // Update call state to connected
      _currentCall = _currentCall!.copyWith(
        state: CallState.connected,
        startedAt: DateTime.now(),
      );
      _callStateController.add(_currentCall);
      
      // Stop any ringing
      _stopRinging();
      _cancelCallTimeout();
        // For the caller (who initiated the call), initialize WebRTC as host
      if (user != null && _currentCall!.callerId == user.uid && _socket != null) {
        debugPrint('🔧 Caller initializing WebRTC as host');
          // Request permissions before initializing WebRTC
        final permissionType = _currentCall!.type == CallType.video ? 
          PermissionType.audioVideo : PermissionType.audio;
        final hasPermissions = await VideoSDKPermissionService.ensurePermissions(permissionType);
          if (!hasPermissions) {
          debugPrint('❌ Permissions denied for WebRTC');
          await endCall(_currentCall!.id, reason: 'Permission denied');
          return;
        }        await _webrtcService.initialize(
          socket: _socket!,
          roomId: callId,
          isHost: true,
          enableVideo: _currentCall!.type == CallType.video,
          enableAudio: true,
        );
        
        debugPrint('✅ WebRTC initialized successfully for caller - waiting for negotiation signal');
      }
      
      notifyListeners();
      debugPrint('🔄 Call state updated to connected for caller');
    } else {
      debugPrint('⚠️ Received call accepted for different call ID');
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
    final endedBy = data['endedBy'] as String;
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
    _cancelCallTimeout();
    
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

  // Cleanup
  void _cleanup() {
    _callSubscription?.cancel();
    _callSubscription = null;
    _currentCall = null;
    _callStateController.add(null);
    _stopRinging();
  }

  // Dispose socket connection
  @override
  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
    _callSubscription?.cancel();
    _callStateController.close();
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
  // Start listening for incoming calls via socket
  void startListeningForIncomingCalls() {
    final user = _auth.currentUser;
    if (user == null) {
      print('❌ Cannot start listening: User not authenticated');
      return;
    }

    // Initialize socket if not connected
    if (_socket == null || !_socket!.connected) {
      print('🔌 Socket not connected, initializing...');
      initializeSocket();
      
      // Give socket time to connect
      Timer(Duration(seconds: 2), () {
        if (_socket != null && _socket!.connected) {
          print('🔔 Starting to listen for incoming calls for user: ${user.uid}');
          _setupSocketListeners();
        } else {
          print('⚠️ Socket connection failed, calls may not work properly');
        }
      });
    } else {
      print('🔔 Starting to listen for incoming calls for user: ${user.uid}');
      _setupSocketListeners();
    }
  }

  void _setupSocketListeners() {
    // Listen for incoming calls
    _socket!.on('incoming-call', (data) => _handleIncomingCall(data as Map<String, dynamic>));
    
    // Listen for call state changes
    _socket!.on('call-ended', (data) {
      final callId = (data as Map<String, dynamic>)['roomId'] as String?;
      if (callId != null && _currentCall?.id == callId) {
        _handleCallEnded(data);
      }
    });

    _socket!.on('call-declined', (data) {
      final callId = (data as Map<String, dynamic>)['roomId'] as String?;
      if (callId != null && _currentCall?.id == callId) {
        _handleCallEnded(data);
      }
    });
    
    print('✅ Successfully started listening for incoming calls');
  }

  // Get call logs stream for chat integration
  Stream<List<CallLog>> getCallLogsStream({String? recipientId, String? groupId}) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }    Query query = _firestore.collection('call_logs');
    
    if (groupId != null) {
      // Group call logs
      query = query.where('groupId', isEqualTo: groupId);
    } else if (recipientId != null) {
      // 1-on-1 call logs - use userId field to get user's logs, then filter client-side
      query = query.where('userId', isEqualTo: user.uid);
    } else {
      // All call logs for user
      query = query.where('userId', isEqualTo: user.uid);
    }

    return query
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      var callLogs = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return CallLog.fromMap(data, doc.id);
      }).toList();
      
      // If we have a specific recipient, filter client-side
      if (recipientId != null) {
        callLogs = callLogs.where((log) => log.participantId == recipientId).toList();
      }
      
      return callLogs;
    });
  }
}
