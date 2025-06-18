import 'package:flutter/material.dart';
import '../models/chat_item.dart';
import '../models/message.dart';
import '../models/call_log.dart';
import '../services/chat_service.dart';
import '../widgets/badged_user_name.dart';
import '../widgets/linkify_text.dart';
import 'package:intl/intl.dart';

class ChatItemWidget extends StatelessWidget {
  final ChatItem chatItem;
  final ChatService chatService;

  const ChatItemWidget({
    super.key,
    required this.chatItem,
    required this.chatService,
  });

  @override
  Widget build(BuildContext context) {
    if (chatItem.isMessage) {
      return _buildMessageItem(chatItem.asMessage);
    } else if (chatItem.isCallLog) {
      return _buildCallLogItem(chatItem.asCallLog);
    } else {
      return const SizedBox.shrink();
    }
  }

  Widget _buildMessageItem(Message message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _getGradientColors(message.senderName),
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                message.senderName.isNotEmpty 
                    ? message.senderName[0].toUpperCase()
                    : message.senderEmail[0].toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Message content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    BadgedUserName(
                      senderName: message.senderName,
                      senderEmail: message.senderEmail,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF37352F),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('HH:mm').format(message.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9B9A97),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildMessageContent(message),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCallLogItem(CallLog callLog) {
    final isIncoming = callLog.type == CallLogType.incoming;
    final isMissed = callLog.status == CallLogStatus.missed;
    final isVideo = callLog.isVideo;
    
    Color iconColor;
    IconData iconData;
    
    if (isMissed) {
      iconColor = Colors.red;
      iconData = isIncoming ? Icons.call_received : Icons.call_made;
    } else {
      iconColor = Colors.green;
      iconData = isIncoming ? Icons.call_received : Icons.call_made;
    }
    
    if (isVideo) {
      iconData = isIncoming ? Icons.videocam : Icons.videocam;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F6F3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE1E1E0)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              iconData,
              color: iconColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isVideo ? Icons.videocam : Icons.call,
                      size: 14,
                      color: const Color(0xFF9B9A97),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getCallLogDescription(callLog),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF37352F),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('HH:mm').format(callLog.timestamp),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9B9A97),
                      ),
                    ),
                  ],
                ),
                if (callLog.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatDuration(callLog.duration!),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9B9A97),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildMessageContent(Message message) {
    switch (message.type) {
      case MessageType.text:
        return LinkifyText(
          text: message.content,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF37352F),
            height: 1.4,
          ),
          linkStyle: const TextStyle(
            fontSize: 14,
            color: Color(0xFF0B6BCB),
            decoration: TextDecoration.underline,
            height: 1.4,
          ),
          enableEmbeds: true,
        );      case MessageType.image:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isNotEmpty) ...[
              LinkifyText(
                text: message.content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF37352F),
                  height: 1.4,
                ),
                linkStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF0B6BCB),
                  decoration: TextDecoration.underline,
                  height: 1.4,
                ),
                enableEmbeds: false, // Disable embeds for image captions
              ),
              const SizedBox(height: 8),
            ],
            Container(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 200),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  message.imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F6F3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F6F3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.error),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );      case MessageType.video:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.content.isNotEmpty) ...[
              LinkifyText(
                text: message.content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF37352F),
                  height: 1.4,
                ),
                linkStyle: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF0B6BCB),
                  decoration: TextDecoration.underline,
                  height: 1.4,
                ),
                enableEmbeds: false, // Disable embeds for video captions
              ),
              const SizedBox(height: 8),
            ],
            Container(
              constraints: const BoxConstraints(maxWidth: 300, maxHeight: 200),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F6F3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (message.thumbnailUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        message.thumbnailUrl!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                  if (message.videoDuration != null)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatDuration(message.videoDuration!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),          ],
        );
      case MessageType.callLog:
        if (message.callLog != null) {
          final callLogData = message.callLog!;
          final isVideo = callLogData['isVideo'] as bool? ?? false;
          final type = callLogData['type'] as String? ?? '';
          final status = callLogData['status'] as String? ?? '';
          final duration = callLogData['duration'] as int? ?? 0;
          
          final isIncoming = type == 'incoming';
          final isMissed = status == 'missed';
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isVideo ? Icons.videocam : Icons.phone,
                  size: 16,
                  color: isMissed ? Colors.red : Colors.green,
                ),
                const SizedBox(width: 8),
                Text(
                  _getCallLogText(isIncoming, isMissed, isVideo, duration),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF666666),
                  ),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
    }
  }

  String _getCallLogText(bool isIncoming, bool isMissed, bool isVideo, int duration) {
    if (isMissed) {
      return isIncoming ? 'Missed call' : 'Call not answered';
    }
    
    final callType = isVideo ? 'Video call' : 'Call';
    final direction = isIncoming ? 'Incoming' : 'Outgoing';
    
    if (duration > 0) {
      final durationText = _formatCallDuration(duration);
      return '$direction $callType ($durationText)';
    } else {
      return '$direction $callType';
    }
  }

  String _formatCallDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else if (seconds < 3600) {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return remainingSeconds > 0 ? '${minutes}m ${remainingSeconds}s' : '${minutes}m';
    } else {
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      return minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
    }
  }

  String _getCallLogDescription(CallLog callLog) {
    final isIncoming = callLog.type == CallLogType.incoming;
    final isMissed = callLog.status == CallLogStatus.missed;
    final isVideo = callLog.isVideo;
    
    String prefix = isVideo ? 'Video call' : 'Voice call';
    
    if (isMissed) {
      return '$prefix missed';
    } else if (isIncoming) {
      return '$prefix received';
    } else {
      return '$prefix made';
    }
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    final minutes = duration.inMinutes;
    final remainingSeconds = duration.inSeconds % 60;
    
    if (minutes > 0) {
      return '${minutes}:${remainingSeconds.toString().padLeft(2, '0')}';
    } else {
      return '0:${remainingSeconds.toString().padLeft(2, '0')}';
    }
  }

  List<Color> _getGradientColors(String name) {
    final hash = name.hashCode;
    final gradients = [
      [const Color(0xFF6366F1), const Color(0xFF8B5CF6)], // Purple-Indigo
      [const Color(0xFF06B6D4), const Color(0xFF3B82F6)], // Cyan-Blue
      [const Color(0xFF10B981), const Color(0xFF059669)], // Emerald
      [const Color(0xFFF59E0B), const Color(0xFFEF4444)], // Amber-Red
      [const Color(0xFFEC4899), const Color(0xFFF97316)], // Pink-Orange
      [const Color(0xFF8B5CF6), const Color(0xFFEC4899)], // Violet-Pink
      [const Color(0xFF059669), const Color(0xFF0891B2)], // Emerald-Cyan
      [const Color(0xFFEF4444), const Color(0xFFF59E0B)], // Red-Amber
    ];
    
    return gradients[hash.abs() % gradients.length];
  }
}
