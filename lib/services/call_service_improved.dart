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
import 'webrtc_service_new.dart';
import 'event_bus.dart';

class CallServiceImproved extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  final WebRTCService _webrtcService = WebRTCService();
  
  // Socket connection for signaling
  IO.Socket? _socket;
  
  // Current call state
  Call? _currentCall;
  final StreamController<Call?> _callStateController = StreamController<Call?>.broadcast();
  final StreamController<Map<String, dynamic>> _incomingCallController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Call timers and management
  Timer? _ringtonTimer;
  Timer? _callTimeoutTimer;
  Timer? _callDurationTimer;
  bool _isRinging = false;
  
  // Call management
  final Set<String> _processedCallIds = <String>{};
  final Set<String> _rejectedCallIds = <String>{};
  
  // Configuration
  static const String signalingServerUrl = 'http://34.131.45.104:3000';
  static const int callTimeoutSeconds = 45;
  static const int ringTimeoutSeconds = 30;
  
  // Getters
  Stream<Call?> get callStateStream => _callStateController.stream;
  Stream<Map<String, dynamic>> get incomingCallStream => _incomingCallController.stream;
  Call? get currentCall => _currentCall;
  bool get isInCall => _currentCall?.isActive == true;
  WebRTCService get webrtcService => _webrtcService;

  /// Initialize socket connection
  void initializeSocket([String? serverUrl]) {
    try {
      final url = serverUrl ?? signalingServerUrl;
      debugPrint('🔌 CallService: Connecting to signaling server: $url');
      
      _socket = IO.io(url, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': true,
        'timeout': 10000,
        'reconnection': true,
        'reconnectionAttempts': 5,
        'reconnectionDelay': 1000,
      });
      
      _setupSocketListeners();
      _socket!.connect();
      
    } catch (e) {
      debugPrint('❌ CallService: Failed to initialize socket: $e');
    }
  }

  /// Setup socket event listeners
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    _socket!.on('connect', (_) {
      debugPrint('✅ CallService: Connected to signaling server');
    });
    
    _socket!.on('disconnect', (_) {
      debugPrint('❌ CallService: Disconnected from signaling server');
    });
    
    _socket!.on('incoming-call', _handleIncomingCall);
    _socket!.on('call-accepted', _handleCallAccepted);
    _socket!.on('call-rejected', _handleCallRejected);
    _socket!.on('call-cancelled', _handleCallCancelled);
    _socket!.on('call-timeout', _handleCallTimeout);
    _socket!.on('call-ended', _handleCallEnded);
    _socket!.on('participant-busy', _handleParticipantBusy);
  }

  /// Initiate a call
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

    // Check if already in a call
    if (_currentCall?.isActive == true) {
      throw Exception('Another call is already in progress');
    }

    try {
      await WakelockPlus.enable();
      
      final callId = _uuid.v4();
      final participantIds = [user.uid, recipientId];
      if (additionalParticipants != null) {
        participantIds.addAll(additionalParticipants);
      }
      
      final participantNames = <String, String>{
        user.uid: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
        recipientId: recipientName,
      };

      // Create call object
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

      // Set current call and notify UI
      _updateCallState(call);
      
      // Initialize socket if needed
      if (_socket == null || !_socket!.connected) {
        initializeSocket();
        await _waitForSocketConnection();
      }

      // Save to Firestore (optional, for persistence)
      try {
        await _firestore.collection('calls').doc(callId).set(call.toMap());
      } catch (e) {
        debugPrint('⚠️ CallService: Firestore save failed, continuing: $e');
      }

      // Update to ringing state
      call = call.copyWith(state: CallState.ringing);
      _updateCallState(call);

      // Send call initiation through signaling server
      _socket!.emit('initiate-call', {
        'callId': callId,
        'callerId': user.uid,
        'callerName': user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
        'participantIds': participantIds.where((id) => id != user.uid).toList(),
        'isVideo': type == CallType.video,
        'isGroup': groupId != null || (additionalParticipants?.isNotEmpty ?? false),
      });

      // Start call timeout
      _startCallTimeout(callId);

      debugPrint('✅ CallService: Call initiated: $callId');
      return callId;

    } catch (e) {
      await WakelockPlus.disable();
      _updateCallState(null);
      rethrow;
    }
  }

  /// Accept an incoming call
  Future<void> acceptCall(String callId) async {
    try {
      debugPrint('✅ CallService: Accepting call: $callId');
      
      if (_currentCall?.id != callId) {
        debugPrint('❌ CallService: Cannot accept call - not current call');
        return;
      }

      // Stop ringtone
      _stopRingtone();

      // Update call state to connecting
      final call = _currentCall!.copyWith(
        state: CallState.connecting,
        startedAt: DateTime.now(),
      );
      _updateCallState(call);

      // Enable wakelock
      await WakelockPlus.enable();

      // Send acceptance through signaling server
      _socket?.emit('accept-call', {'callId': callId});

      // Initialize WebRTC as non-initiator
      await _webrtcService.initializeCall(
        socket: _socket!,
        callId: callId,
        isInitiator: false,
        enableVideo: call.type == CallType.video,
        enableAudio: true,
      );

      // Start call duration timer
      _startCallDurationTimer();

      debugPrint('✅ CallService: Call accepted and WebRTC initialized');

    } catch (e) {
      debugPrint('❌ CallService: Failed to accept call: $e');
      await endCall(callId, 'failed');
    }
  }

  /// Decline an incoming call
  Future<void> declineCall(String callId) async {
    try {
      debugPrint('❌ CallService: Declining call: $callId');
      
      _stopRingtone();
      _rejectedCallIds.add(callId);

      // Send decline through signaling server
      _socket?.emit('decline-call', {'callId': callId});

      // Update call state
      if (_currentCall?.id == callId) {
        final call = _currentCall!.copyWith(
          state: CallState.declined,
          endedAt: DateTime.now(),
          endReason: 'declined',
        );
        _updateCallState(call);
        
        // Log the call
        await _logCall(call);
        
        // Clear current call after logging
        _updateCallState(null);
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to decline call: $e');
    }
  }

  /// End an active call
  Future<void> endCall(String callId, [String? reason]) async {
    try {
      debugPrint('🔚 CallService: Ending call: $callId');
      
      _stopAllTimers();
      _stopRingtone();

      // Cleanup WebRTC
      await _webrtcService.cleanup();

      // Send end call signal
      _socket?.emit('end-call', {
        'callId': callId,
        'reason': reason ?? 'ended',
      });

      // Update call state
      if (_currentCall?.id == callId) {
        final endTime = DateTime.now();
        final duration = _currentCall!.startedAt != null 
            ? endTime.difference(_currentCall!.startedAt!).inSeconds 
            : null;

        final call = _currentCall!.copyWith(
          state: CallState.ended,
          endedAt: endTime,
          duration: duration,
          endReason: reason ?? 'ended',
        );
        
        // Log the call before clearing
        await _logCall(call);
        
        _updateCallState(call);
        
        // Clear current call after a brief delay
        Timer(const Duration(seconds: 1), () {
          _updateCallState(null);
        });
      }

      // Disable wakelock
      await WakelockPlus.disable();

      debugPrint('✅ CallService: Call ended successfully');

    } catch (e) {
      debugPrint('❌ CallService: Failed to end call: $e');
    }
  }

  /// Cancel an outgoing call
  Future<void> cancelCall(String callId) async {
    try {
      debugPrint('🚫 CallService: Cancelling call: $callId');
      
      _stopAllTimers();

      // Send cancel signal
      _socket?.emit('cancel-call', {'callId': callId});

      // Update call state
      if (_currentCall?.id == callId) {
        final call = _currentCall!.copyWith(
          state: CallState.cancelled,
          endedAt: DateTime.now(),
          endReason: 'cancelled',
        );
        
        await _logCall(call);
        _updateCallState(null);
      }

      await WakelockPlus.disable();

    } catch (e) {
      debugPrint('❌ CallService: Failed to cancel call: $e');
    }
  }

  // Socket event handlers
  void _handleIncomingCall(dynamic data) async {
    try {
      final callId = data['callId'];
      final callerId = data['callerId'];
      final callerName = data['callerName'];
      final isVideo = data['isVideo'] ?? false;
      final isGroup = data['isGroup'] ?? false;

      debugPrint('📞 CallService: Incoming call: $callId from $callerName');

      // Check if call already processed
      if (_processedCallIds.contains(callId) || _rejectedCallIds.contains(callId)) {
        debugPrint('⚠️ CallService: Call already processed: $callId');
        return;
      }

      // Check if already in a call
      if (_currentCall?.isActive == true) {
        debugPrint('📞 CallService: User busy, rejecting call: $callId');
        _socket?.emit('decline-call', {
          'callId': callId,
          'reason': 'busy',
        });
        return;
      }

      _processedCallIds.add(callId);

      // Create call object
      final call = Call(
        id: callId,
        callerId: callerId,
        callerName: callerName,
        callerEmail: data['callerEmail'] ?? '',
        callerPhotoUrl: data['callerPhotoUrl'],
        participantIds: [callerId, _auth.currentUser!.uid],
        participantNames: {
          callerId: callerName,
          _auth.currentUser!.uid: _auth.currentUser!.displayName ?? 'You',
        },
        groupId: isGroup ? data['groupId'] : null,
        groupName: isGroup ? data['groupName'] : null,
        type: isVideo ? CallType.video : CallType.voice,
        state: CallState.ringing,
        createdAt: DateTime.now(),
      );

      _updateCallState(call);
      _startRingtone();
      _startRingTimeout(callId);

      // Notify UI
      _incomingCallController.add(data);

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle incoming call: $e');
    }
  }

  void _handleCallAccepted(dynamic data) async {
    try {
      final callId = data['callId'];
      debugPrint('✅ CallService: Call accepted: $callId');

      if (_currentCall?.id == callId) {
        _stopAllTimers();

        // Update call state to connecting
        final call = _currentCall!.copyWith(
          state: CallState.connecting,
          startedAt: DateTime.now(),
        );
        _updateCallState(call);

        // Initialize WebRTC as initiator
        await _webrtcService.initializeCall(
          socket: _socket!,
          callId: callId,
          isInitiator: true,
          enableVideo: call.type == CallType.video,
          enableAudio: true,
        );

        _startCallDurationTimer();
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle call accepted: $e');
      await endCall(data['callId'], 'failed');
    }
  }

  void _handleCallRejected(dynamic data) {
    try {
      final callId = data['callId'];
      final reason = data['reason'] ?? 'declined';
      
      debugPrint('❌ CallService: Call rejected: $callId ($reason)');

      if (_currentCall?.id == callId) {
        _stopAllTimers();

        final call = _currentCall!.copyWith(
          state: CallState.declined,
          endedAt: DateTime.now(),
          endReason: reason,
        );

        _logCall(call);
        _updateCallState(null);
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle call rejected: $e');
    }
  }

  void _handleCallCancelled(dynamic data) {
    try {
      final callId = data['callId'];
      debugPrint('🚫 CallService: Call cancelled: $callId');

      if (_currentCall?.id == callId) {
        _stopAllTimers();
        _stopRingtone();

        final call = _currentCall!.copyWith(
          state: CallState.cancelled,
          endedAt: DateTime.now(),
          endReason: 'cancelled',
        );

        _logCall(call);
        _updateCallState(null);
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle call cancelled: $e');
    }
  }

  void _handleCallTimeout(dynamic data) {
    try {
      final callId = data['callId'];
      debugPrint('⏰ CallService: Call timeout: $callId');

      if (_currentCall?.id == callId) {
        _stopAllTimers();
        _stopRingtone();

        final call = _currentCall!.copyWith(
          state: CallState.missed,
          endedAt: DateTime.now(),
          endReason: 'timeout',
        );

        _logCall(call);
        _updateCallState(null);
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle call timeout: $e');
    }
  }

  void _handleCallEnded(dynamic data) {
    try {
      final callId = data['callId'];
      final reason = data['reason'] ?? 'ended';
      
      debugPrint('🔚 CallService: Call ended remotely: $callId ($reason)');

      if (_currentCall?.id == callId) {
        endCall(callId, reason);
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle call ended: $e');
    }
  }

  void _handleParticipantBusy(dynamic data) {
    try {
      final callId = data['callId'];
      debugPrint('📞 CallService: Participant busy: $callId');

      if (_currentCall?.id == callId) {
        _stopAllTimers();

        final call = _currentCall!.copyWith(
          state: CallState.busy,
          endedAt: DateTime.now(),
          endReason: 'busy',
        );

        _logCall(call);
        _updateCallState(null);
      }

    } catch (e) {
      debugPrint('❌ CallService: Failed to handle participant busy: $e');
    }
  }

  // Helper methods
  void _updateCallState(Call? call) {
    _currentCall = call;
    _callStateController.add(call);
    notifyListeners();
  }

  void _startCallTimeout(String callId) {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: callTimeoutSeconds), () {
      debugPrint('⏰ CallService: Call timeout reached for: $callId');
      cancelCall(callId);
    });
  }

  void _startRingTimeout(String callId) {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: ringTimeoutSeconds), () {
      debugPrint('⏰ CallService: Ring timeout reached for: $callId');
      if (_currentCall?.id == callId && _currentCall?.state == CallState.ringing) {
        _stopRingtone();
        
        final call = _currentCall!.copyWith(
          state: CallState.missed,
          endedAt: DateTime.now(),
          endReason: 'timeout',
        );
        
        _logCall(call);
        _updateCallState(null);
      }
    });
  }

  void _startCallDurationTimer() {
    _callDurationTimer?.cancel();
    _callDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentCall?.state == CallState.connected) {
        // Update call duration in UI if needed
        notifyListeners();
      }
    });
  }
  void _startRingtone() {
    if (_isRinging) return;
    
    _isRinging = true;
    
    try {
      FlutterRingtonePlayer().playRingtone();
    } catch (e) {
      debugPrint('❌ CallService: Failed to start ringtone: $e');
    }
  }

  void _stopRingtone() {
    if (!_isRinging) return;
    
    _isRinging = false;
    
    try {
      FlutterRingtonePlayer().stop();
    } catch (e) {
      debugPrint('❌ CallService: Failed to stop ringtone: $e');
    }
  }

  void _stopAllTimers() {
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = null;
    
    _callDurationTimer?.cancel();
    _callDurationTimer = null;
    
    _ringtonTimer?.cancel();
    _ringtonTimer = null;
  }

  Future<void> _waitForSocketConnection() async {
    if (_socket?.connected == true) return;
    
    int attempts = 0;
    while (attempts < 10 && (_socket?.connected != true)) {
      await Future.delayed(const Duration(milliseconds: 500));
      attempts++;
    }
    
    if (_socket?.connected != true) {
      throw Exception('Failed to connect to signaling server');
    }
  }

  /// Log call to Firestore and emit event
  Future<void> _logCall(Call call) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Determine call log type and status
      CallLogType logType;
      CallLogStatus logStatus;

      if (call.callerId == user.uid) {
        logType = CallLogType.outgoing;
      } else {
        logType = CallLogType.incoming;
      }

      switch (call.state) {
        case CallState.connected:
        case CallState.ended:
          logStatus = CallLogStatus.completed;
          break;
        case CallState.declined:
          logStatus = CallLogStatus.declined;
          break;
        case CallState.missed:
          logStatus = CallLogStatus.missed;
          break;
        case CallState.failed:
        case CallState.cancelled:
        case CallState.busy:
          logStatus = CallLogStatus.failed;
          break;
        default:
          logStatus = CallLogStatus.failed;
      }

      // Get other participant info
      final otherParticipantId = call.participantIds.firstWhere(
        (id) => id != user.uid,
        orElse: () => '',
      );
      final otherParticipantName = call.participantNames[otherParticipantId] ?? '';

      final callLog = CallLog(
        id: call.id,
        callId: call.id,
        type: logType,
        status: logStatus,
        isVideo: call.type == CallType.video,
        participantId: otherParticipantId,
        participantName: otherParticipantName,
        participantEmail: call.callerEmail,
        groupId: call.groupId,
        groupName: call.groupName,
        timestamp: call.createdAt,
        duration: call.duration,
        userId: user.uid,
      );

      // Save to Firestore
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('call_logs')
          .doc(call.id)
          .set(callLog.toMap());      // Emit event for other services
      EventBus().emit(CallLogCreatedEvent(
        callLog: callLog.toMap(),
        recipientId: otherParticipantId,
        isGroupCall: call.groupId != null,
        groupId: call.groupId,
      ));

      debugPrint('✅ CallService: Call logged successfully');

    } catch (e) {
      debugPrint('❌ CallService: Failed to log call: $e');
    }
  }

  /// Start listening for incoming calls
  void startListeningForIncomingCalls() {
    final user = _auth.currentUser;
    if (user == null) return;

    debugPrint('🔔 CallService: Starting to listen for incoming calls for user: ${user.uid}');

    if (_socket == null || !_socket!.connected) {
      initializeSocket();
    }

    // Register user for incoming calls
    _socket?.emit('register-user', {'userId': user.uid});

    debugPrint('✅ CallService: Successfully started listening for incoming calls');
  }

  @override
  void dispose() {
    _stopAllTimers();
    _stopRingtone();
    
    _socket?.disconnect();
    _socket?.dispose();
    
    _callStateController.close();
    _incomingCallController.close();
    
    _webrtcService.dispose();
    
    super.dispose();
  }
}
