import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/call_log.dart';

class CallLogTile extends StatelessWidget {
  final CallLog callLog;
  final VoidCallback? onTap;

  const CallLogTile({
    super.key,
    required this.callLog,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E6E3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Call type icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: callLog.statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    callLog.statusIcon,
                    size: 18,
                    color: callLog.statusColor,
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
                          Expanded(
                            child: Text(
                              callLog.displayTitle,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF37352F),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (callLog.isVideo)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0B6BCB).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Video',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF0B6BCB),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          // Call direction indicator
                          Icon(
                            callLog.type == CallLogType.incoming 
                                ? Icons.call_received 
                                : Icons.call_made,
                            size: 12,
                            color: callLog.type == CallLogType.incoming 
                                ? const Color(0xFF0F8B0F) 
                                : const Color(0xFF0B6BCB),
                          ),
                          const SizedBox(width: 4),
                          
                          // Call status/duration
                          Text(
                            callLog.statusText,
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
                          
                          const SizedBox(width: 8),
                          
                          // Timestamp
                          Text(
                            _formatTimestamp(callLog.timestamp),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9B9A97),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Call back button
                IconButton(
                  onPressed: () => _initiateCallBack(context),
                  icon: Icon(
                    callLog.isVideo ? Icons.videocam : Icons.call,
                    size: 18,
                    color: const Color(0xFF0B6BCB),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inDays == 0) {
      // Today - show time
      return DateFormat('HH:mm').format(timestamp);
    } else if (difference.inDays == 1) {
      // Yesterday
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      // This week - show day
      return DateFormat('EEEE').format(timestamp);
    } else {
      // Older - show date
      return DateFormat('MMM d').format(timestamp);
    }
  }

  void _initiateCallBack(BuildContext context) {
    // Show call back dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Call ${callLog.displayTitle}'),
        content: Text('Would you like to start a ${callLog.isVideo ? 'video' : 'voice'} call?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement call initiation
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Starting ${callLog.isVideo ? 'video' : 'voice'} call...'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            child: const Text('Call'),
          ),
        ],
      ),
    );
  }
}
