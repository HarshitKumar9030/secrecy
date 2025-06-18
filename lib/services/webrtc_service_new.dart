import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum WebRTCState {
  idle,
  initializing,
  ready,
  signaling,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
  closed
}

class WebRTCService extends ChangeNotifier {
  // Core WebRTC components
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // State management
  WebRTCState _state = WebRTCState.idle;
  bool _disposed = false;
  String? _currentCallId;
  
  // Configuration
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };
  
  // Socket and signaling
  IO.Socket? _socket;
  bool _isInitiator = false;
  
  // Media settings
  bool _isVideoEnabled = true;
  bool _isAudioEnabled = true;
  bool _isFrontCamera = true;
  
  // ICE candidate queue for proper timing
  final List<RTCIceCandidate> _pendingIceCandidates = [];
  bool _remoteDescriptionSet = false;
  
  // Connection monitoring
  Timer? _connectionMonitor;
  int _reconnectAttempts = 0;
  static const int maxReconnectAttempts = 3;
  
  // Getters
  WebRTCState get state => _state;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isAudioEnabled => _isAudioEnabled;
  bool get isFrontCamera => _isFrontCamera;
  bool get isConnected => _state == WebRTCState.connected;
  String? get currentCallId => _currentCallId;

  /// Initialize WebRTC for a call
  Future<void> initializeCall({
    required IO.Socket socket,
    required String callId,
    required bool isInitiator,
    required bool enableVideo,
    required bool enableAudio,
  }) async {
    try {
      debugPrint('🚀 WebRTC: Initializing call $callId (initiator: $isInitiator)');
      
      if (_state != WebRTCState.idle) {
        await cleanup();
      }
      
      _setState(WebRTCState.initializing);
      
      _socket = socket;
      _currentCallId = callId;
      _isInitiator = isInitiator;
      _isVideoEnabled = enableVideo;
      _isAudioEnabled = enableAudio;
      
      // Setup socket listeners
      _setupSocketListeners();
      
      // Get user media first
      await _getUserMedia();
      
      // Create peer connection
      await _createPeerConnection();
      
      // Add local stream to peer connection
      await _addLocalStreamToPeerConnection();
      
      _setState(WebRTCState.ready);
      
      // If we're the initiator, start the signaling process
      if (_isInitiator) {
        // Small delay to ensure both sides are ready
        await Future.delayed(const Duration(milliseconds: 500));
        await _createOffer();
      }
      
      debugPrint('✅ WebRTC: Initialization complete');
      
    } catch (e) {
      debugPrint('❌ WebRTC: Initialization failed: $e');
      _setState(WebRTCState.failed);
      rethrow;
    }
  }

  /// Set the current state and notify listeners
  void _setState(WebRTCState newState) {
    if (_disposed) return;
    
    final oldState = _state;
    _state = newState;
    
    debugPrint('🔄 WebRTC: State changed from $oldState to $newState');
    
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Setup socket listeners for signaling
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    _socket!.on('webrtc-offer', _handleOffer);
    _socket!.on('webrtc-answer', _handleAnswer);
    _socket!.on('webrtc-ice-candidate', _handleIceCandidate);
    _socket!.on('webrtc-error', _handleWebRTCError);
  }

  /// Get user media with simplified constraints
  Future<void> _getUserMedia() async {
    try {
      debugPrint('🎥 WebRTC: Requesting user media (video: $_isVideoEnabled, audio: $_isAudioEnabled)');
      
      final mediaConstraints = <String, dynamic>{
        'audio': _isAudioEnabled ? {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        } : false,
        'video': _isVideoEnabled ? {
          'facingMode': _isFrontCamera ? 'user' : 'environment',
          'width': {'ideal': 640, 'max': 1280},
          'height': {'ideal': 480, 'max': 720},
          'frameRate': {'ideal': 24, 'max': 30},
        } : false,
      };
      
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      if (_localStream == null) {
        throw Exception('Failed to get user media');
      }
      
      debugPrint('✅ WebRTC: Got local stream with ${_localStream!.getTracks().length} tracks');
      
      // Verify tracks
      for (final track in _localStream!.getTracks()) {
        debugPrint('📹 Track: ${track.kind}, enabled: ${track.enabled}, id: ${track.id}');
      }
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to get user media: $e');
      
      // Try fallback with minimal constraints
      if (_isVideoEnabled) {
        debugPrint('🔄 WebRTC: Trying fallback constraints...');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({
            'audio': _isAudioEnabled,
            'video': _isVideoEnabled ? {'facingMode': 'user'} : false,
          });
          debugPrint('✅ WebRTC: Fallback media stream obtained');
        } catch (fallbackError) {
          debugPrint('❌ WebRTC: Fallback also failed: $fallbackError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  /// Create peer connection with proper configuration
  Future<void> _createPeerConnection() async {
    try {
      debugPrint('🔗 WebRTC: Creating peer connection');
      
      _peerConnection = await createPeerConnection(_iceServers);
      
      // Setup event handlers
      _peerConnection!.onIceCandidate = _onIceCandidate;
      _peerConnection!.onIceConnectionState = _onIceConnectionStateChange;
      _peerConnection!.onConnectionState = _onConnectionStateChange;
      _peerConnection!.onSignalingState = _onSignalingStateChange;
      _peerConnection!.onTrack = _onTrack;
      _peerConnection!.onAddStream = _onAddStream; // Fallback for older implementations
      
      debugPrint('✅ WebRTC: Peer connection created');
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to create peer connection: $e');
      rethrow;
    }
  }

  /// Add local stream to peer connection
  Future<void> _addLocalStreamToPeerConnection() async {
    if (_peerConnection == null || _localStream == null) return;
    
    try {
      debugPrint('➕ WebRTC: Adding local stream to peer connection');
      
      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
        debugPrint('➕ WebRTC: Added ${track.kind} track');
      }
      
      debugPrint('✅ WebRTC: All tracks added to peer connection');
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to add tracks: $e');
      rethrow;
    }
  }

  /// Create and send offer (initiator only)
  Future<void> _createOffer() async {
    if (_peerConnection == null) return;
    
    try {
      debugPrint('📤 WebRTC: Creating offer');
      _setState(WebRTCState.signaling);
      
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _isVideoEnabled,
      });
      
      await _peerConnection!.setLocalDescription(offer);
      debugPrint('✅ WebRTC: Local description set');
      
      // Send offer through signaling server
      _socket?.emit('webrtc-offer', {
        'callId': _currentCallId,
        'offer': offer.toMap(),
      });
      
      debugPrint('📡 WebRTC: Offer sent');
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to create offer: $e');
      _setState(WebRTCState.failed);
      rethrow;
    }
  }

  /// Handle incoming offer
  void _handleOffer(dynamic data) async {
    if (_peerConnection == null) return;
    
    try {
      debugPrint('📨 WebRTC: Received offer');
      _setState(WebRTCState.signaling);
      
      final offer = RTCSessionDescription(
        data['offer']['sdp'],
        data['offer']['type'],
      );
      
      await _peerConnection!.setRemoteDescription(offer);
      _remoteDescriptionSet = true;
      debugPrint('✅ WebRTC: Remote description set');
      
      // Process any pending ICE candidates
      await _processPendingIceCandidates();
      
      // Create answer
      final answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _isVideoEnabled,
      });
      
      await _peerConnection!.setLocalDescription(answer);
      debugPrint('✅ WebRTC: Answer created and local description set');
      
      // Send answer
      _socket?.emit('webrtc-answer', {
        'callId': _currentCallId,
        'answer': answer.toMap(),
      });
      
      debugPrint('📡 WebRTC: Answer sent');
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to handle offer: $e');
      _setState(WebRTCState.failed);
    }
  }

  /// Handle incoming answer
  void _handleAnswer(dynamic data) async {
    if (_peerConnection == null) return;
    
    try {
      debugPrint('📨 WebRTC: Received answer');
      
      final answer = RTCSessionDescription(
        data['answer']['sdp'],
        data['answer']['type'],
      );
      
      await _peerConnection!.setRemoteDescription(answer);
      _remoteDescriptionSet = true;
      debugPrint('✅ WebRTC: Answer processed');
      
      // Process any pending ICE candidates
      await _processPendingIceCandidates();
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to handle answer: $e');
      _setState(WebRTCState.failed);
    }
  }

  /// Handle incoming ICE candidate
  void _handleIceCandidate(dynamic data) async {
    try {
      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      
      if (_remoteDescriptionSet) {
        await _peerConnection?.addCandidate(candidate);
        debugPrint('✅ WebRTC: ICE candidate added immediately');
      } else {
        _pendingIceCandidates.add(candidate);
        debugPrint('⏳ WebRTC: ICE candidate queued (${_pendingIceCandidates.length} pending)');
      }
      
    } catch (e) {
      debugPrint('❌ WebRTC: Failed to handle ICE candidate: $e');
    }
  }

  /// Process pending ICE candidates
  Future<void> _processPendingIceCandidates() async {
    if (_pendingIceCandidates.isEmpty) return;
    
    debugPrint('🔄 WebRTC: Processing ${_pendingIceCandidates.length} pending ICE candidates');
    
    for (final candidate in _pendingIceCandidates) {
      try {
        await _peerConnection?.addCandidate(candidate);
      } catch (e) {
        debugPrint('❌ WebRTC: Failed to add pending candidate: $e');
      }
    }
    
    _pendingIceCandidates.clear();
    debugPrint('✅ WebRTC: All pending ICE candidates processed');
  }

  /// Handle WebRTC errors from signaling
  void _handleWebRTCError(dynamic data) {
    debugPrint('❌ WebRTC: Received error from signaling: ${data['error']}');
    _setState(WebRTCState.failed);
  }

  // Event handlers
  void _onIceCandidate(RTCIceCandidate candidate) {
    debugPrint('🧊 WebRTC: Sending ICE candidate');
    _socket?.emit('webrtc-ice-candidate', {
      'callId': _currentCallId,
      'candidate': candidate.toMap(),
    });
  }

  void _onIceConnectionStateChange(RTCIceConnectionState state) {
    debugPrint('🧊 WebRTC: ICE connection state: $state');
    
    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        _setState(WebRTCState.connected);
        _startConnectionMonitoring();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        _setState(WebRTCState.disconnected);
        _attemptReconnection();
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _setState(WebRTCState.failed);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateClosed:
        _setState(WebRTCState.closed);
        break;
      default:
        break;
    }
  }

  void _onConnectionStateChange(RTCPeerConnectionState state) {
    debugPrint('🔗 WebRTC: Peer connection state: $state');
    
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _setState(WebRTCState.connected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        _setState(WebRTCState.connecting);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        _setState(WebRTCState.disconnected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        _setState(WebRTCState.failed);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _setState(WebRTCState.closed);
        break;
      default:
        break;
    }
  }

  void _onSignalingStateChange(RTCSignalingState state) {
    debugPrint('📡 WebRTC: Signaling state: $state');
  }

  void _onTrack(RTCTrackEvent event) {
    debugPrint('📹 WebRTC: Received remote track');
    if (event.streams.isNotEmpty) {
      _remoteStream = event.streams[0];
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  void _onAddStream(MediaStream stream) {
    debugPrint('📹 WebRTC: Received remote stream (fallback)');
    _remoteStream = stream;
    if (!_disposed) {
      notifyListeners();
    }
  }

  /// Start monitoring connection health
  void _startConnectionMonitoring() {
    _connectionMonitor?.cancel();
    _connectionMonitor = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkConnectionHealth();
    });
  }
  /// Check connection health
  Future<void> _checkConnectionHealth() async {
    if (_peerConnection == null) return;
    
    try {
      await _peerConnection!.getStats();
      // Connection is healthy if we can get stats without error
      debugPrint('📊 WebRTC: Connection health check passed');
    } catch (e) {
      debugPrint('❌ WebRTC: Connection health check failed: $e');
    }
  }

  /// Attempt to reconnect
  void _attemptReconnection() {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      debugPrint('❌ WebRTC: Max reconnection attempts reached');
      _setState(WebRTCState.failed);
      return;
    }
    
    _reconnectAttempts++;
    _setState(WebRTCState.reconnecting);
    
    debugPrint('🔄 WebRTC: Attempting reconnection (${_reconnectAttempts}/$maxReconnectAttempts)');
    
    // Implement reconnection logic here
    // For now, just set to failed after delay
    Timer(const Duration(seconds: 3), () {
      if (_state == WebRTCState.reconnecting) {
        _setState(WebRTCState.failed);
      }
    });
  }

  // Media control methods
  Future<void> toggleVideo() async {
    if (_localStream == null) return;
    
    _isVideoEnabled = !_isVideoEnabled;
    
    final videoTracks = _localStream!.getVideoTracks();
    for (final track in videoTracks) {
      track.enabled = _isVideoEnabled;
    }
    
    debugPrint('📹 WebRTC: Video toggled to $_isVideoEnabled');
    notifyListeners();
  }

  Future<void> toggleAudio() async {
    if (_localStream == null) return;
    
    _isAudioEnabled = !_isAudioEnabled;
    
    final audioTracks = _localStream!.getAudioTracks();
    for (final track in audioTracks) {
      track.enabled = _isAudioEnabled;
    }
    
    debugPrint('🎵 WebRTC: Audio toggled to $_isAudioEnabled');
    notifyListeners();
  }

  Future<void> switchCamera() async {
    if (_localStream == null || !_isVideoEnabled) return;
    
    _isFrontCamera = !_isFrontCamera;
    
    final videoTracks = _localStream!.getVideoTracks();
    for (final track in videoTracks) {
      await track.switchCamera();
    }
    
    debugPrint('📷 WebRTC: Camera switched to ${_isFrontCamera ? 'front' : 'back'}');
    notifyListeners();
  }

  /// Cleanup WebRTC resources
  Future<void> cleanup() async {
    try {
      debugPrint('🧹 WebRTC: Starting cleanup');
      
      _setState(WebRTCState.closed);
      
      // Cancel timers
      _connectionMonitor?.cancel();
      _connectionMonitor = null;
      
      // Remove socket listeners
      if (_socket != null) {
        _socket!.off('webrtc-offer');
        _socket!.off('webrtc-answer');
        _socket!.off('webrtc-ice-candidate');
        _socket!.off('webrtc-error');
      }
      
      // Stop and dispose local stream
      if (_localStream != null) {
        for (final track in _localStream!.getTracks()) {
          await track.stop();
        }
        await _localStream!.dispose();
        _localStream = null;
      }
      
      // Dispose remote stream
      if (_remoteStream != null) {
        await _remoteStream!.dispose();
        _remoteStream = null;
      }
      
      // Close peer connection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }
      
      // Clear state
      _currentCallId = null;
      _remoteDescriptionSet = false;
      _pendingIceCandidates.clear();
      _reconnectAttempts = 0;
      
      _setState(WebRTCState.idle);
      
      debugPrint('✅ WebRTC: Cleanup complete');
      
    } catch (e) {
      debugPrint('❌ WebRTC: Error during cleanup: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cleanup();
    super.dispose();
  }
}
