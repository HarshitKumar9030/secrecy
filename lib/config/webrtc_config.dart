class WebRTCConfig {
  // Your VM's signaling server URL
  // TODO: Replace with your actual VM's IP/domain
  static const String signalingServerUrl = 'ws://YOUR_VM_IP:3000';
  
  // STUN/TURN servers for NAT traversal
  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ]
      },
      // TODO: Add your TURN server if needed for better connectivity
      // {
      //   'urls': 'turn:YOUR_TURN_SERVER:3478',
      //   'username': 'your_username',
      //   'credential': 'your_password'
      // }
    ]
  };
  
  // Media constraints
  static const Map<String, dynamic> mediaConstraints = {
    'audio': true,
    'video': {
      'mandatory': {
        'minWidth': '320',
        'minHeight': '240',
        'minFrameRate': '30',
      },
      'facingMode': 'user',
      'optional': [],
    }
  };
  
  // Audio only constraints
  static const Map<String, dynamic> audioOnlyConstraints = {
    'audio': true,
    'video': false,
  };
  
  // Generate a unique room ID
  static String generateRoomId(String callId) {
    return 'secrecy_$callId';
  }
}

// NOTE: You'll need to set up a Node.js signaling server on your VM
// I'll provide the server code in the next step
