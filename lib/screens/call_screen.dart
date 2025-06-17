import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class CallScreen extends StatefulWidget {
  final Call call;

  const CallScreen({super.key, required this.call});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  
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
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
    
    // Start animations for ringing state
    if (widget.call.state == CallState.ringing) {
      _pulseController.repeat(reverse: true);
      _fadeController.repeat(reverse: true);
    }
  }
  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    super.dispose();
  }  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.user;
    
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: StreamBuilder<Call?>(
        stream: context.read<CallService>().callStateStream,
        initialData: widget.call,
        builder: (context, snapshot) {
          final call = snapshot.data ?? widget.call;
          
          // Auto close if call ended
          if (call.isEnded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const ChatScreen()),
                (route) => false,
              );
            });
          }
            return SafeArea(
            child: _buildNotionStyleCallUI(call, currentUser),
          );
        },
      ),
    );
  }

  Widget _buildNotionStyleCallUI(Call call, dynamic currentUser) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF1A1A1A),
            const Color(0xFF000000).withOpacity(0.9),
          ],
        ),
      ),
      child: Column(
        children: [
          // Top bar with minimal controls
          _buildTopBar(call),
          
          // Main content area
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Participant info with beautiful styling
                _buildMinimalParticipantInfo(call, currentUser?.uid),
                
                const SizedBox(height: 60),
                
                // Call status
                _buildCallStatus(call),
                
                const SizedBox(height: 40),
              ],
            ),
          ),
          
          // Bottom controls
          _buildMinimalCallControls(call, currentUser?.uid),
          
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildTopBar(Call call) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // Call type indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  call.isVideoCall ? Icons.videocam_rounded : Icons.call_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  call.isVideoCall ? 'Video' : 'Voice',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // Connection indicator
          if (call.state == CallState.connected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF10B981),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatDuration(call),
                    style: const TextStyle(
                      color: Color(0xFF10B981),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
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

  Color _getStateColor(CallState state) {
    switch (state) {
      case CallState.initiating:
      case CallState.connecting:
        return const Color(0xFFFF9500);
      case CallState.ringing:
        return const Color(0xFF007AFF);
      case CallState.connected:
        return const Color(0xFF34C759);
      case CallState.ended:
      case CallState.declined:
      case CallState.missed:
        return const Color(0xFF8E8E93);
      case CallState.failed:
        return const Color(0xFFFF3B30);
    }
  }
  Widget _buildParticipantInfo(Call call, String? currentUserId) {
    final isCurrentUserCaller = call.callerId == currentUserId;
    String otherParticipantName;
    
    if (call.isGroupCall) {
      otherParticipantName = call.groupName ?? 'Group Call';
    } else {
      // For one-on-one calls, show the other participant's name
      if (isCurrentUserCaller) {
        // Current user is the caller, show the first participant who isn't the caller
        final otherParticipantId = call.participantIds.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        otherParticipantName = call.participantNames[otherParticipantId] ?? 'Unknown User';
      } else {
        // Current user is being called, show the caller's name
        otherParticipantName = call.callerName.isNotEmpty 
            ? call.callerName 
            : call.callerEmail.split('@')[0];
      }
    }
    
    return Column(
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
                    colors: _getGradientColors(otherParticipantName),
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
                    otherParticipantName.isNotEmpty 
                        ? otherParticipantName[0].toUpperCase()
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
                otherParticipantName,
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
    );
  }

  Widget _buildCallControls(Call call, String? currentUserId) {
    return _buildActionButtons(call, currentUserId);
  }

  Widget _buildMinimalParticipantInfo(Call call, String? currentUserId) {
    // Fix the name display logic
    String displayName;
    String subtitle;
    
    if (call.isGroupCall) {
      displayName = call.groupName ?? 'Group Call';
      subtitle = '${call.participantIds.length} participants';
    } else {
      // For 1-on-1 calls, always show the OTHER person's name
      final isCurrentUserCaller = call.callerId == currentUserId;
      
      if (isCurrentUserCaller) {
        // Current user initiated the call - show the recipient's name
        final otherParticipantId = call.participantIds.firstWhere(
          (id) => id != currentUserId,
          orElse: () => '',
        );
        displayName = call.participantNames[otherParticipantId] ?? 
                      call.callerEmail.split('@')[0]; // fallback to email prefix
        subtitle = call.isVideoCall ? 'Video call' : 'Voice call';
      } else {
        // Current user is receiving the call - show the caller's name
        displayName = call.callerName.isNotEmpty 
            ? call.callerName 
            : call.callerEmail.split('@')[0];
        subtitle = call.isVideoCall ? 'Incoming video call' : 'Incoming voice call';
      }
    }

    return Column(
      children: [
        // Beautiful avatar with subtle animation
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: call.state == CallState.ringing ? _pulseAnimation.value : 1.0,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _getGradientColors(displayName),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _getGradientColors(displayName)[0].withOpacity(0.3),
                      blurRadius: 30,
                      spreadRadius: 5,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    displayName.isNotEmpty 
                        ? displayName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        
        const SizedBox(height: 24),
        
        // Name with fade animation
        AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            return Opacity(
              opacity: call.state == CallState.ringing ? _fadeAnimation.value : 1.0,
              child: Text(
                displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
            );
          },
        ),
        
        const SizedBox(height: 8),
        
        // Subtitle
        Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildCallStatus(Call call) {
    String statusText;
    Color statusColor;
    
    switch (call.state) {
      case CallState.initiating:
        statusText = 'Calling...';
        statusColor = const Color(0xFF007AFF);
        break;
      case CallState.ringing:
        statusText = 'Ringing...';
        statusColor = const Color(0xFF007AFF);
        break;
      case CallState.connecting:
        statusText = 'Connecting...';
        statusColor = const Color(0xFFFF9500);
        break;
      case CallState.connected:
        return const SizedBox.shrink(); // Duration is shown in top bar
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinimalCallControls(Call call, String? currentUserId) {
    final isIncoming = call.callerId != currentUserId && call.state == CallState.ringing;
    final isConnected = call.state == CallState.connected;
    
    if (isIncoming) {
      // Incoming call - Accept/Decline
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildMinimalActionButton(
            icon: Icons.call_end_rounded,
            color: const Color(0xFFFF3B30),
            onPressed: () => _declineCall(call.id),
            label: 'Decline',
          ),
          
          const SizedBox(width: 60),
          
          _buildMinimalActionButton(
            icon: Icons.call_rounded,
            color: const Color(0xFF10B981),
            onPressed: () => _acceptCall(call.id),
            label: 'Accept',
          ),
        ],
      );
    } else if (isConnected) {
      // Connected call controls
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildMinimalSecondaryButton(
            icon: _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
            isActive: _isMuted,
            onPressed: _toggleMute,
          ),
          
          _buildMinimalActionButton(
            icon: Icons.call_end_rounded,
            color: const Color(0xFFFF3B30),
            onPressed: () => _endCall(call.id),
            label: 'End',
          ),
          
          _buildMinimalSecondaryButton(
            icon: _isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
            isActive: _isSpeakerOn,
            onPressed: _toggleSpeaker,
          ),
        ],
      );
    } else {
      // Outgoing call
      return _buildMinimalActionButton(
        icon: Icons.call_end_rounded,
        color: const Color(0xFFFF3B30),
        onPressed: () => _endCall(call.id),
        label: 'End Call',
      );
    }
  }

  Widget _buildMinimalActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required String label,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(36),
              child: Icon(
                icon,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildMinimalSecondaryButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.2) : Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Icon(
            icon,
            color: isActive ? Colors.white : Colors.white.withOpacity(0.7),
            size: 24,
          ),
        ),
      ),
    );
  }
}
