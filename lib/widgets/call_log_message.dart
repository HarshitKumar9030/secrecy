import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/call_log.dart';
import '../models/call_model.dart';
import '../services/call_service.dart';

class CallLogMessage extends StatelessWidget {
  final CallLog callLog;
  final VoidCallback? onCallBack;

  const CallLogMessage({
    super.key,
    required this.callLog,
    this.onCallBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getBorderColor(),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // Call type icon with status
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: callLog.statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Icon(
                        callLog.isVideo ? Icons.videocam : Icons.call,
                        size: 18,
                        color: callLog.statusColor,
                      ),
                    ),
                    if (callLog.status == CallLogStatus.missed)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE03E3E),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Call info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Call direction indicator
                        Icon(
                          callLog.type == CallLogType.incoming 
                              ? Icons.call_received 
                              : Icons.call_made,
                          size: 14,
                          color: _getDirectionColor(),
                        ),
                        const SizedBox(width: 6),
                        
                        // Call type text
                        Text(
                          _getCallTypeText(),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF37352F),
                          ),
                        ),
                        
                        if (callLog.groupName != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B6BCB).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Group',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF0B6BCB),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    
                    Row(
                      children: [
                        // Status and duration
                        Text(
                          _getStatusText(),
                          style: TextStyle(
                            fontSize: 12,
                            color: callLog.status == CallLogStatus.missed
                                ? const Color(0xFFE03E3E)
                                : const Color(0xFF787774),
                            fontWeight: callLog.status == CallLogStatus.missed
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                        ),
                        
                        if (callLog.duration != null && callLog.duration! > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 3,
                            height: 3,
                            decoration: const BoxDecoration(
                              color: Color(0xFF9B9A97),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            callLog.formattedDuration,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF787774),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        
                        const Spacer(),
                        
                        // Timestamp
                        Text(
                          _formatTimestamp(callLog.timestamp),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9B9A97),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Call back button
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B6BCB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: IconButton(
                  onPressed: onCallBack ?? () => _initiateCallBack(context),
                  icon: Icon(
                    callLog.isVideo ? Icons.videocam : Icons.call,
                    size: 16,
                    color: const Color(0xFF0B6BCB),
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getBackgroundColor() {
    switch (callLog.status) {
      case CallLogStatus.missed:
        return const Color(0xFFFFF5F5);
      case CallLogStatus.completed:
        return const Color(0xFFF0FDF4);
      case CallLogStatus.declined:
        return const Color(0xFFFEF3C7);
      case CallLogStatus.failed:
        return const Color(0xFFFFF5F5);
    }
  }

  Color _getBorderColor() {
    switch (callLog.status) {
      case CallLogStatus.missed:
        return const Color(0xFFE03E3E).withOpacity(0.2);
      case CallLogStatus.completed:
        return const Color(0xFF0F8B0F).withOpacity(0.2);
      case CallLogStatus.declined:
        return const Color(0xFFFF8800).withOpacity(0.2);
      case CallLogStatus.failed:
        return const Color(0xFFE03E3E).withOpacity(0.2);
    }
  }

  Color _getDirectionColor() {
    return callLog.type == CallLogType.incoming 
        ? const Color(0xFF0F8B0F) 
        : const Color(0xFF0B6BCB);
  }

  String _getCallTypeText() {
    final typeText = callLog.isVideo ? 'Video call' : 'Voice call';
    final directionText = callLog.type == CallLogType.incoming ? 'Incoming' : 'Outgoing';
    return '$directionText $typeText';
  }

  String _getStatusText() {
    switch (callLog.status) {
      case CallLogStatus.completed:
        return 'Completed';
      case CallLogStatus.missed:
        return 'Missed';
      case CallLogStatus.declined:
        return 'Declined';
      case CallLogStatus.failed:
        return 'Failed';
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return DateFormat('HH:mm').format(timestamp);
    } else if (difference.inDays == 1) {
      return 'Yesterday ${DateFormat('HH:mm').format(timestamp)}';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE HH:mm').format(timestamp);
    } else {
      return DateFormat('MMM d, HH:mm').format(timestamp);
    }
  }

  void _initiateCallBack(BuildContext context) {
    // Show call back options
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('Call ${callLog.displayTitle}'),
        content: const Text('Would you like to start a call?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (!callLog.isVideo)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startCall(context, CallType.voice);
              },
              child: const Text('Voice Call'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _startCall(context, CallType.video);
            },
            child: const Text('Video Call'),
          ),
        ],
      ),
    );
  }

  void _startCall(BuildContext context, CallType type) {
    try {
      final callService = context.read<CallService>();
      
      if (callLog.groupId != null) {
        // Group call
        _initiateGroupCall(context, callService, type);
      } else {
        // Private call
        _initiatePrivateCall(context, callService, type);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to start call: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  Future<void> _initiatePrivateCall(BuildContext context, CallService callService, CallType type) async {
    try {
      await callService.initiateCall(
        recipientId: callLog.participantId,
        recipientName: callLog.participantName,
        recipientEmail: callLog.participantEmail,
        type: type,
      );
      
      // Navigation will be handled automatically by main.dart based on call state
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  Future<void> _initiateGroupCall(BuildContext context, CallService callService, CallType type) async {
    try {
      // For group calls, we need more information about participants
      // This is a simplified implementation
      await callService.initiateCall(
        recipientId: '', // Group calls don't have a single recipient
        recipientName: callLog.groupName ?? 'Group',
        recipientEmail: '',
        type: type,
        groupId: callLog.groupId,
        groupName: callLog.groupName,
      );
      
      // Navigation will be handled automatically by main.dart based on call state
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to initiate group call: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
