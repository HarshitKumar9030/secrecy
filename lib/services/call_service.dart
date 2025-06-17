import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:uuid/uuid.dart';
import '../models/call_model.dart';
import '../models/call_log.dart';

class CallService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();
  
  // Current call state
  Call? _currentCall;
  StreamSubscription<DocumentSnapshot>? _callSubscription;
  final StreamController<Call?> _callStateController = StreamController<Call?>.broadcast();
  
  // Ringtone management
  bool _isRinging = false;
  Timer? _ringingTimer;
  
  Stream<Call?> get callStateStream => _callStateController.stream;
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

  // Accept incoming call
  Future<void> acceptCall(String callId) async {
    try {
      await _updateCallState(callId, CallState.connecting);
      _stopRingtone();
      
      // Simulate connection process
      await Future.delayed(const Duration(seconds: 2));
      await _updateCallState(callId, CallState.connected, startedAt: DateTime.now());
    } catch (e) {
      print('Error accepting call: $e');
      await endCall(callId, 'connection_failed');
    }
  }

  // Decline incoming call
  Future<void> declineCall(String callId) async {
    try {
      await _updateCallState(callId, CallState.declined, endedAt: DateTime.now());
      _stopRingtone();
      await _createCallLog(callId, CallLogStatus.declined);
    } catch (e) {
      print('Error declining call: $e');
    }
  }
  // End call
  Future<void> endCall(String callId, [String? reason]) async {
    try {
      final endTime = DateTime.now();
      await _updateCallState(callId, CallState.ended, endedAt: endTime, endReason: reason);
      _stopRingtone();
      
      // Always create call log regardless of call duration
      CallLogStatus logStatus;
      if (_currentCall?.startedAt != null) {
        // Call was connected - calculate duration
        final duration = endTime.difference(_currentCall!.startedAt!).inSeconds;
        await _firestore.collection('calls').doc(callId).update({
          'duration': duration,
        });
        logStatus = CallLogStatus.completed;
      } else if (reason == 'declined') {
        logStatus = CallLogStatus.declined;
      } else if (reason == 'failed') {
        logStatus = CallLogStatus.failed;
      } else {
        // Call ended before being answered (including instant hangups)
        logStatus = CallLogStatus.missed;
      }
      
      // Create call log for all scenarios
      await _createCallLog(callId, logStatus);
      
    } catch (e) {
      print('Error ending call: $e');
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

  void dispose() {
    _cleanup();
    _callStateController.close();
  }
}
