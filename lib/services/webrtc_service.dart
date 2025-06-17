import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebRTCService extends ChangeNotifier {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };
  
  final Map<String, dynamic> _configuration = {
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ]
  };
  
  IO.Socket? _socket;
  String? _roomId;
  bool _isHost = false;
  bool _isVideoEnabled = true;
  bool _isAudioEnabled = true;
  bool _isFrontCameraEnabled = true;
  
  // Getters
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isAudioEnabled => _isAudioEnabled;
  bool get isFrontCameraEnabled => _isFrontCameraEnabled;
  bool get isConnected => _peerConnection?.connectionState == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
  
  // Initialize WebRTC connection
  Future<void> initialize({
    required IO.Socket socket,
    required String roomId,
    required bool isHost,
    required bool enableVideo,
    required bool enableAudio,
  }) async {
    try {
      _socket = socket;
      _roomId = roomId;
      _isHost = isHost;
      _isVideoEnabled = enableVideo;
      _isAudioEnabled = enableAudio;
      
      // Setup socket listeners
      _setupSocketListeners();
      
      // Create peer connection
      await _createPeerConnection();
      
      // Get user media
      await _getUserMedia();
      
      // If host, create offer
      if (_isHost) {
        await _createOffer();
      }
      
      debugPrint('WebRTC initialized successfully');
    } catch (e) {
      debugPrint('Error initializing WebRTC: $e');
      rethrow;
    }
  }
    // Setup socket event listeners
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    _socket!.on('offer', (data) async {
      debugPrint('Received WebRTC offer');
      await _handleOffer(data);
    });
    
    _socket!.on('answer', (data) async {
      debugPrint('Received WebRTC answer');
      await _handleAnswer(data);
    });
    
    _socket!.on('ice-candidate', (data) async {
      debugPrint('Received ICE candidate');
      await _handleIceCandidate(data);
    });
    
    // Listen for participant video/audio toggles
    _socket!.on('participant-video-toggle', (data) {
      debugPrint('Participant toggled video: ${data['isVideoEnabled']}');
      notifyListeners();
    });
    
    _socket!.on('participant-audio-toggle', (data) {
      debugPrint('Participant toggled audio: ${data['isAudioEnabled']}');
      notifyListeners();
    });
  }
  
  // Create peer connection
  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection(_iceServers, _configuration);
      // Handle ice candidates
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint('Sending ICE candidate');
      _socket?.emit('ice-candidate', {
        'roomId': _roomId,
        'candidate': candidate.toMap(),
      });
    };
    
    // Handle remote stream
    _peerConnection!.onAddStream = (MediaStream stream) {
      debugPrint('Received remote stream');
      _remoteStream = stream;
      notifyListeners();
    };
    
    // Handle connection state changes
    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('Connection state: $state');
      notifyListeners();
    };
    
    // Handle ice connection state changes
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('ICE connection state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        // Handle reconnection or cleanup
        debugPrint('ICE connection failed or disconnected');
      }
    };
  }
  
  // Get user media (camera and microphone)
  Future<void> _getUserMedia() async {
    final Map<String, dynamic> mediaConstraints = {
      'audio': _isAudioEnabled,
      'video': _isVideoEnabled ? {
        'facingMode': _isFrontCameraEnabled ? 'user' : 'environment',
        'width': 640,
        'height': 480,
      } : false,
    };
    
    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      // Add local stream to peer connection
      if (_peerConnection != null && _localStream != null) {
        await _peerConnection!.addStream(_localStream!);
      }
      
      notifyListeners();
      debugPrint('Local media stream obtained');
    } catch (e) {
      debugPrint('Error getting user media: $e');
      rethrow;
    }
  }
  
  // Create offer (host)
  Future<void> _createOffer() async {
    try {
      RTCSessionDescription offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _isVideoEnabled,
      });
        await _peerConnection!.setLocalDescription(offer);
      
      _socket?.emit('offer', {
        'roomId': _roomId,
        'offer': offer.toMap(),
        'callerId': _socket?.id, // Add caller identification
        'participantIds': [], // Will be filled by call service
      });
      
      debugPrint('Offer created and sent');
    } catch (e) {
      debugPrint('Error creating offer: $e');
    }
  }
  
  // Handle incoming offer
  Future<void> _handleOffer(dynamic data) async {
    try {
      final offer = RTCSessionDescription(
        data['offer']['sdp'],
        data['offer']['type'],
      );
      
      await _peerConnection!.setRemoteDescription(offer);
      
      // Create answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _isVideoEnabled,
      });
        await _peerConnection!.setLocalDescription(answer);
      
      _socket?.emit('answer', {
        'roomId': _roomId,
        'answer': answer.toMap(),
      });
      
      debugPrint('Answer created and sent');
    } catch (e) {
      debugPrint('Error handling offer: $e');
    }
  }
  
  // Handle incoming answer
  Future<void> _handleAnswer(dynamic data) async {
    try {
      final answer = RTCSessionDescription(
        data['answer']['sdp'],
        data['answer']['type'],
      );
      
      await _peerConnection!.setRemoteDescription(answer);
      debugPrint('Answer set successfully');
    } catch (e) {
      debugPrint('Error handling answer: $e');
    }
  }
  
  // Handle incoming ICE candidate
  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      final candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );
      
      await _peerConnection!.addCandidate(candidate);
      debugPrint('ICE candidate added');
    } catch (e) {
      debugPrint('Error handling ICE candidate: $e');
    }
  }
  
  // Toggle video
  Future<void> toggleVideo() async {
    if (_localStream != null) {
      _isVideoEnabled = !_isVideoEnabled;
      
      final videoTracks = _localStream!.getVideoTracks();
      for (final track in videoTracks) {
        track.enabled = _isVideoEnabled;
      }
        // Notify peers about video toggle
      _socket?.emit('toggle-video', {
        'roomId': _roomId,
        'userId': _socket?.id,
        'isVideoEnabled': _isVideoEnabled,
      });
      
      notifyListeners();
      debugPrint('Video toggled: $_isVideoEnabled');
    }
  }
  
  // Toggle audio
  Future<void> toggleAudio() async {
    if (_localStream != null) {
      _isAudioEnabled = !_isAudioEnabled;
      
      final audioTracks = _localStream!.getAudioTracks();
      for (final track in audioTracks) {
        track.enabled = _isAudioEnabled;
      }
        // Notify peers about audio toggle
      _socket?.emit('toggle-audio', {
        'roomId': _roomId,
        'userId': _socket?.id,
        'isAudioEnabled': _isAudioEnabled,
      });
      
      notifyListeners();
      debugPrint('Audio toggled: $_isAudioEnabled');
    }
  }
  
  // Switch camera
  Future<void> switchCamera() async {
    if (_localStream != null && _isVideoEnabled) {
      _isFrontCameraEnabled = !_isFrontCameraEnabled;
      
      final videoTracks = _localStream!.getVideoTracks();
      for (final track in videoTracks) {
        await track.switchCamera();
      }
      
      notifyListeners();
      debugPrint('Camera switched: front = $_isFrontCameraEnabled');
    }
  }
  
  // End call and cleanup
  Future<void> endCall() async {
    try {
      // Stop local stream
      if (_localStream != null) {
        await _localStream!.dispose();
        _localStream = null;
      }
      
      // Stop remote stream
      if (_remoteStream != null) {
        await _remoteStream!.dispose();
        _remoteStream = null;
      }
      
      // Close peer connection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }
        // Remove socket listeners
      _socket?.off('offer');
      _socket?.off('answer');
      _socket?.off('ice-candidate');
      _socket?.off('participant-video-toggle');
      _socket?.off('participant-audio-toggle');
      
      _socket = null;
      _roomId = null;
      
      notifyListeners();
      debugPrint('WebRTC call ended and cleaned up');
    } catch (e) {
      debugPrint('Error ending WebRTC call: $e');
    }
  }
  
  @override
  void dispose() {
    endCall();
    super.dispose();
  }
}
