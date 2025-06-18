import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/call_log.dart';
import '../models/call_model.dart';
import '../services/call_service_improved.dart';
import 'package:provider/provider.dart';

class CallLogsScreen extends StatefulWidget {
  const CallLogsScreen({super.key});

  @override
  State<CallLogsScreen> createState() => _CallLogsScreenState();
}

class _CallLogsScreenState extends State<CallLogsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();

  Stream<List<CallLog>> _getCallLogsStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('call_logs')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return CallLog.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Minimal header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(
                    color: Color(0xFFF1F1F0),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F6F3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        size: 16,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Call History',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2F3437),
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: StreamBuilder<List<CallLog>>(
                stream: _getCallLogsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF2F3437),
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F6F3),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              size: 32,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Unable to load call logs',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF2F3437),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Error: ${snapshot.error}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B6B6B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }

                  final callLogs = snapshot.data ?? [];

                  if (callLogs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF7F6F3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.call_outlined,
                              size: 48,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No calls yet',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2F3437),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your call history will appear here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return Scrollbar(
                    controller: _scrollController,
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: callLogs.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFF1F1F0),
                        indent: 72,
                      ),
                      itemBuilder: (context, index) {
                        final callLog = callLogs[index];
                        return CallLogTile(callLog: callLog);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CallLogTile extends StatelessWidget {
  final CallLog callLog;

  const CallLogTile({super.key, required this.callLog});

  IconData _getCallIcon() {
    switch (callLog.type) {
      case CallLogType.incoming:
        switch (callLog.status) {
          case CallLogStatus.missed:
            return Icons.call_received;
          case CallLogStatus.declined:
            return Icons.call_received;
          default:
            return Icons.call_received;
        }
      case CallLogType.outgoing:
        return Icons.call_made;
      case CallLogType.missed:
        return Icons.call_received;
    }
  }

  Color _getCallIconColor() {
    switch (callLog.status) {
      case CallLogStatus.missed:
        return const Color(0xFFE03E3E);
      case CallLogStatus.declined:
        return const Color(0xFFFF8800);
      case CallLogStatus.failed:
        return const Color(0xFFE03E3E);
      default:
        return const Color(0xFF0F8B0F);
    }
  }

  String _getCallStatusText() {
    switch (callLog.status) {
      case CallLogStatus.completed:
        return callLog.duration != null ? _formatDuration(Duration(seconds: callLog.duration!)) : 'Completed';
      case CallLogStatus.missed:
        return 'Missed';
      case CallLogStatus.declined:
        return 'Declined';
      case CallLogStatus.failed:
        return 'Failed';
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    
    if (duration.inHours > 0) {
      return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
    } else {
      return "$twoDigitMinutes:$twoDigitSeconds";
    }
  }

  String _formatTimestamp() {
    final now = DateTime.now();
    final difference = now.difference(callLog.timestamp);

    if (difference.inDays == 0) {
      // Today - show time
      final hour = callLog.timestamp.hour;
      final minute = callLog.timestamp.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      return '$displayHour:$minute $period';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[callLog.timestamp.weekday - 1];
    } else {
      return '${callLog.timestamp.day}/${callLog.timestamp.month}/${callLog.timestamp.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final callService = context.read<CallServiceImproved>();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            // Show call options in a bottom sheet
            _showCallOptions(context, callService);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Call icon with status color
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _getCallIconColor().withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    _getCallIcon(),
                    color: _getCallIconColor(),
                    size: 20,
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Call details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name/Email
                      Text(
                        callLog.groupName ?? (callLog.participantName.isNotEmpty 
                            ? callLog.participantName 
                            : callLog.participantEmail),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF2F3437),
                        ),
                      ),
                      
                      const SizedBox(height: 4),
                      
                      // Call type and status
                      Row(
                        children: [
                          Icon(
                            callLog.isVideo ? Icons.videocam : Icons.call,
                            size: 14,
                            color: const Color(0xFF6B6B6B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _getCallStatusText(),
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B6B6B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                // Timestamp and callback button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatTimestamp(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B6B6B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _makeCall(callService),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F6F3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          callLog.isVideo ? Icons.videocam : Icons.call,
                          color: const Color(0xFF2F3437),
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCallOptions(BuildContext context, CallServiceImproved callService) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE1E1E0),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Contact info
            Text(
              callLog.groupName ?? (callLog.participantName.isNotEmpty 
                  ? callLog.participantName 
                  : callLog.participantEmail),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2F3437),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Call options
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildCallOption(
                  icon: Icons.call,
                  label: 'Voice Call',
                  onTap: () {
                    Navigator.pop(context);
                    _makeCall(callService, isVideo: false);
                  },
                ),
                _buildCallOption(
                  icon: Icons.videocam,
                  label: 'Video Call',
                  onTap: () {
                    Navigator.pop(context);
                    _makeCall(callService, isVideo: true);
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildCallOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24,
              color: const Color(0xFF2F3437),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Color(0xFF2F3437),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _makeCall(CallServiceImproved callService, {bool? isVideo}) {
    if (callLog.groupId != null) {
      // Group call - TODO: Implement group call
    } else {
      // Individual call
      callService.initiateCall(
        recipientId: callLog.participantId,
        recipientName: callLog.participantName,
        recipientEmail: callLog.participantEmail,
        type: (isVideo ?? callLog.isVideo) ? CallType.video : CallType.voice,
      );
    }
  }
}
