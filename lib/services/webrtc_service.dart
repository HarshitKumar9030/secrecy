import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/webrtc_config.dart';
import '../models/call_model.dart';

class WebRTCService {
  static final WebRTCService _instance = WebRTCService._internal();
  factory WebRTCService() => _instance;
  WebRTCService._internal();

  // Socket.IO connection to signaling server
  IO.Socket? _socket;
  
  // WebRTC peer connection
  RTCPeerConnection? _peerConnection;
  
  // Local and remote streams
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  
  // Stream controllers for UI updates
  final _localStreamController = StreamController<MediaStream?>.broadcast();
  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _connectionStateController = StreamController<RTCPeerConnectionState>.broadcast();
  
  // Getters for streams
  Stream<MediaStream?> get localStream => _localStreamController.stream;
  Stream<MediaStream?> get remoteStream => _remoteStreamController.stream;
  Stream<RTCPeerConnectionState> get connectionState => _connectionStateController.stream;
  
  // Current call info
  CallModel? _currentCall;
  bool _isInCall = false;
  
  bool get isInCall => _isInCall;
  CallModel? get currentCall => _currentCall;

  /// Initialize WebRTC service
  Future<void> initialize() async {
    try {
      // Connect to signaling server
      await _connectToSignalingServer();
      
      if (kDebugMode) {
        print('WebRTC Service initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing WebRTC service: $e');
      }
      rethrow;
    }
  }

  /// Connect to the signaling server
  Future<void> _connectToSignalingServer() async {
    try {
      _socket = IO.io(
        WebRTCConfig.signalingServerUrl,
        IO.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .build(),
      );

      _socket?.on('connect', (_) {
        if (kDebugMode) {
          print('Connected to signaling server');
        }
      });

      _socket?.on('disconnect', (_) {
        if (kDebugMode) {
          print('Disconnected from signaling server');
        }
      });

      // Handle incoming call offer
      _socket?.on('offer', (data) async {
        await _handleOffer(data);
      });

      // Handle incoming call answer
      _socket?.on('answer', (data) async {
        await _handleAnswer(data);
      });

      // Handle ICE candidates
      _socket?.on('ice-candidate', (data) async {
        await _handleIceCandidate(data);
      });

      // Handle call end
      _socket?.on('call-ended', (_) {
        endCall();
      });

      _socket?.connect();
    } catch (e) {
      if (kDebugMode) {
        print('Error connecting to signaling server: $e');
      }
      rethrow;
    }
  }

  /// Start a call (voice or video)
  Future<void> startCall({
    required CallModel call,
    required bool isVideo,
  }) async {
    try {
      _currentCall = call;
      _isInCall = true;

      // Create peer connection
      await _createPeerConnection();

      // Get user media
      await _getUserMedia(isVideo: isVideo);

      // Create and send offer
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer through signaling server
      _socket?.emit('offer', {
        'roomId': call.roomId,
        'offer': offer.toMap(),
        'callerId': call.callerId,
        'participantIds': call.participantIds,
      });

      if (kDebugMode) {
        print('Call started with room ID: ${call.roomId}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error starting call: $e');
      }
      await endCall();
      rethrow;
    }
  }

  /// Answer an incoming call
  Future<void> answerCall({
    required CallModel call,
    required bool isVideo,
  }) async {
    try {
      _currentCall = call;
      _isInCall = true;

      // Create peer connection
      await _createPeerConnection();

      // Get user media
      await _getUserMedia(isVideo: isVideo);

      if (kDebugMode) {
        print('Call answered for room ID: ${call.roomId}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error answering call: $e');
      }
      await endCall();
      rethrow;
    }
  }

  /// End the current call
  Future<void> endCall() async {
    try {
      // Notify signaling server
      if (_currentCall != null) {
        _socket?.emit('end-call', {
          'roomId': _currentCall!.roomId,
        });
      }

      // Clean up local stream
      if (_localStream != null) {
        _localStream!.getTracks().forEach((track) {
          track.stop();
        });
        await _localStream!.dispose();
        _localStream = null;
        _localStreamController.add(null);
      }

      // Clean up remote stream
      if (_remoteStream != null) {
        await _remoteStream!.dispose();
        _remoteStream = null;
        _remoteStreamController.add(null);
      }

      // Close peer connection
      if (_peerConnection != null) {
        await _peerConnection!.close();
        _peerConnection = null;
      }

      _currentCall = null;
      _isInCall = false;

      if (kDebugMode) {
        print('Call ended');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error ending call: $e');
      }
    }
  }

  /// Create peer connection
  Future<void> _createPeerConnection() async {
    try {
      _peerConnection = await createPeerConnection(WebRTCConfig.iceServers);

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        _socket?.emit('ice-candidate', {
          'roomId': _currentCall!.roomId,
          'candidate': candidate.toMap(),
        });
      };

      // Handle remote stream
      _peerConnection!.onAddStream = (MediaStream stream) {
        _remoteStream = stream;
        _remoteStreamController.add(stream);
      };

      // Handle connection state changes
      _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
        _connectionStateController.add(state);
        if (kDebugMode) {
          print('Connection state: $state');
        }
      };
    } catch (e) {
      if (kDebugMode) {
        print('Error creating peer connection: $e');
      }
      rethrow;
    }
  }

  /// Get user media (camera/microphone)
  Future<void> _getUserMedia({required bool isVideo}) async {
    try {
      final constraints = isVideo 
          ? WebRTCConfig.mediaConstraints 
          : WebRTCConfig.audioOnlyConstraints;

      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStreamController.add(_localStream);

      // Add stream to peer connection
      if (_peerConnection != null && _localStream != null) {
        await _peerConnection!.addStream(_localStream!);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user media: $e');
      }
      rethrow;
    }
  }

  /// Handle incoming offer
  Future<void> _handleOffer(dynamic data) async {
    try {
      if (_peerConnection == null) return;

      RTCSessionDescription offer = RTCSessionDescription(
        data['offer']['sdp'],
        data['offer']['type'],
      );

      await _peerConnection!.setRemoteDescription(offer);

      // Create and send answer
      RTCSessionDescription answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      _socket?.emit('answer', {
        'roomId': data['roomId'],
        'answer': answer.toMap(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error handling offer: $e');
      }
    }
  }

  /// Handle incoming answer
  Future<void> _handleAnswer(dynamic data) async {
    try {
      if (_peerConnection == null) return;

      RTCSessionDescription answer = RTCSessionDescription(
        data['answer']['sdp'],
        data['answer']['type'],
      );

      await _peerConnection!.setRemoteDescription(answer);
    } catch (e) {
      if (kDebugMode) {
        print('Error handling answer: $e');
      }
    }
  }

  /// Handle ICE candidate
  Future<void> _handleIceCandidate(dynamic data) async {
    try {
      if (_peerConnection == null) return;

      RTCIceCandidate candidate = RTCIceCandidate(
        data['candidate']['candidate'],
        data['candidate']['sdpMid'],
        data['candidate']['sdpMLineIndex'],
      );

      await _peerConnection!.addCandidate(candidate);
    } catch (e) {
      if (kDebugMode) {
        print('Error handling ICE candidate: $e');
      }
    }
  }

  /// Toggle camera (front/back)
  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().first;
      await Helper.switchCamera(videoTrack);
    }
  }

  /// Toggle microphone mute
  Future<void> toggleMicrophone() async {
    if (_localStream != null) {
      final audioTrack = _localStream!.getAudioTracks().first;
      audioTrack.enabled = !audioTrack.enabled;
    }
  }

  /// Toggle camera on/off
  Future<void> toggleCamera() async {
    if (_localStream != null) {
      final videoTrack = _localStream!.getVideoTracks().first;
      videoTrack.enabled = !videoTrack.enabled;
    }
  }

  /// Dispose resources
  void dispose() {
    endCall();
    _socket?.disconnect();
    _localStreamController.close();
    _remoteStreamController.close();
    _connectionStateController.close();
  }
}
