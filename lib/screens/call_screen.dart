import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';
import '../services/auth_service.dart';

class CallScreen extends StatefulWidget {
  final Call call;

  const CallScreen({super.key, required this.call});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  @override
  void initState() {
    super.initState();
    
    // Initialize animations
    _pulseController = AnimationController(
      duration: const Duration(seconds: 1, milliseconds: 500),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Start animations for ringing state
    if (widget.call.state == CallState.ringing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.user;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F3),
      body: StreamBuilder<Call?>(
        stream: context.read<CallService>().callStateStream,
        initialData: widget.call,
        builder: (context, snapshot) {
          final call = snapshot.data ?? widget.call;
          
          // Auto close if call ended
          if (call.isEnded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pop();
            });
          }
          
          return SafeArea(
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header with status
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getStateColor(call.state).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _getStateColor(call.state).withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _getStateColor(call.state),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _getCallStateText(call.state),
                                style: TextStyle(
                                  color: _getStateColor(call.state),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Call participant info
                  _buildParticipantInfo(call, currentUser?.uid),
                  
                  const Spacer(),
                  
                  // Call controls
                  _buildCallControls(call, currentUser?.uid),
                  
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        },
      ),
    );
  }
                      const Spacer(),
                      if (call.state == CallState.connected)
                        Text(
                          _formatDuration(call),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                
                const Spacer(),
                
                // Call info
                Column(
                  children: [
                    // Profile picture / avatar
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: call.state == CallState.ringing ? _pulseAnimation.value : 1.0,
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: _getGradientColors(call.displayName),
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                call.displayName.isNotEmpty 
                                    ? call.displayName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 64,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 32),
                    
                    // Name
                    AnimatedBuilder(
                      animation: _fadeAnimation,
                      builder: (context, child) {
                        return Opacity(
                          opacity: call.state == CallState.ringing ? _fadeAnimation.value : 1.0,
                          child: Text(
                            call.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        );
                      },
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // Call type
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          call.isVideoCall ? Icons.videocam : Icons.call,
                          color: Colors.white70,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          call.isGroupCall 
                              ? '${call.isVideoCall ? 'Video' : 'Voice'} call with ${call.participantIds.length} people'
                              : '${call.isVideoCall ? 'Video' : 'Voice'} call',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                
                const Spacer(),
                
                // Action buttons
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: _buildActionButtons(call, currentUser?.uid),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons(Call call, String? currentUserId) {
    final isIncoming = call.callerId != currentUserId && call.state == CallState.ringing;
    final isConnected = call.state == CallState.connected;
    
    if (isIncoming) {
      // Incoming call buttons
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Decline button
          _buildActionButton(
            icon: Icons.call_end,
            color: const Color(0xFFFF3B30),
            onPressed: () => _declineCall(call.id),
          ),
          
          // Accept button
          _buildActionButton(
            icon: Icons.call,
            color: const Color(0xFF34C759),
            onPressed: () => _acceptCall(call.id),
          ),
        ],
      );
    } else if (isConnected) {
      // Connected call buttons
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Mute button
          _buildActionButton(
            icon: _isMuted ? Icons.mic_off : Icons.mic,
            color: _isMuted ? const Color(0xFFFF9500) : Colors.white24,
            onPressed: _toggleMute,
          ),
          
          // Speaker button
          _buildActionButton(
            icon: _isSpeakerOn ? Icons.volume_up : Icons.volume_down,
            color: _isSpeakerOn ? const Color(0xFF007AFF) : Colors.white24,
            onPressed: _toggleSpeaker,
          ),
          
          // End call button
          _buildActionButton(
            icon: Icons.call_end,
            color: const Color(0xFFFF3B30),
            onPressed: () => _endCall(call.id),
          ),
        ],
      );
    } else {
      // Outgoing call (ringing)
      return _buildActionButton(
        icon: Icons.call_end,
        color: const Color(0xFFFF3B30),
        onPressed: () => _endCall(call.id),
      );
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  String _getCallStateText(CallState state) {
    switch (state) {
      case CallState.initiating:
        return 'Initiating...';
      case CallState.ringing:
        return 'Ringing...';
      case CallState.connecting:
        return 'Connecting...';
      case CallState.connected:
        return 'Connected';
      case CallState.ended:
        return 'Call ended';
      case CallState.declined:
        return 'Declined';
      case CallState.missed:
        return 'Missed';
      case CallState.failed:
        return 'Failed';
    }
  }

  String _formatDuration(Call call) {
    if (call.startedAt == null) return '';
    
    final duration = DateTime.now().difference(call.startedAt!);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  List<Color> _getGradientColors(String text) {
    final hash = text.hashCode.abs();
    final colorPairs = [
      [const Color(0xFF667eea), const Color(0xFF764ba2)],
      [const Color(0xFFf093fb), const Color(0xFFf5576c)],
      [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
      [const Color(0xFF43e97b), const Color(0xFF38f9d7)],
      [const Color(0xFFfa709a), const Color(0xFFfee140)],
      [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
      [const Color(0xFFffecd2), const Color(0xFFfcb69f)],
      [const Color(0xFFa8caba), const Color(0xFF5d4e75)],
    ];
    return colorPairs[hash % colorPairs.length];
  }

  void _acceptCall(String callId) {
    _pulseController.stop();
    _fadeController.stop();
    context.read<CallService>().acceptCall(callId);
  }

  void _declineCall(String callId) {
    context.read<CallService>().declineCall(callId);
    Navigator.of(context).pop();
  }

  void _endCall(String callId) {
    context.read<CallService>().endCall(callId);
    Navigator.of(context).pop();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });
    // TODO: Implement actual mute functionality with WebRTC
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });
    // TODO: Implement actual speaker toggle with WebRTC
  }
}
