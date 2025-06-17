import 'package:flutter/material.dart';
import '../services/chat_service.dart';
import '../models/user.dart';

class GroupInfoScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupInfoScreen({
    super.key,
    required this.group,
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final ChatService _chatService = ChatService();
  List<ChatUser> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroupMembers();
  }

  Future<void> _loadGroupMembers() async {
    try {
      final memberIds = List<String>.from(widget.group['memberIds'] ?? []);
      final members = await _chatService.getUsersByIds(memberIds);
      
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load members: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFA),
      body: CustomScrollView(
        slivers: [
          // Modern app bar
          SliverAppBar(
            backgroundColor: const Color(0xFFFBFBFA),
            elevation: 0,
            pinned: true,
            leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, color: Color(0xFF37352F)),
            ),
            actions: [
              IconButton(
                onPressed: _editGroup,
                icon: const Icon(Icons.edit, color: Color(0xFF6B6B6B)),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'leave') _leaveGroup();
                },
                icon: const Icon(Icons.more_horiz, color: Color(0xFF6B6B6B)),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'leave',
                    child: Row(
                      children: [
                        Icon(Icons.exit_to_app, size: 16, color: Color(0xFFE03E3E)),
                        SizedBox(width: 8),
                        Text('Leave Group', style: TextStyle(color: Color(0xFFE03E3E))),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(64),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF37352F),
                      ),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group header - clean and minimal
                        Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _getGradientColors(widget.group['name'] ?? ''),
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  (widget.group['name'] ?? '').isNotEmpty
                                      ? (widget.group['name'] ?? '')[0].toUpperCase()
                                      : 'G',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.group['name'] ?? 'Unknown Group',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF37352F),
                                      height: 1.2,
                                    ),
                                  ),
                                  if (widget.group['description']?.isNotEmpty == true) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.group['description'],
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF787774),
                                        height: 1.4,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_members.length} members',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF9B9A97),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Action buttons - clean design
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE6E6E3)),
                          ),
                          child: Column(
                            children: [
                              _buildActionButton(
                                icon: Icons.call,
                                title: 'Voice Call',
                                subtitle: 'Start a voice call with all members',
                                onTap: () => _initiateGroupCall(false),
                                color: const Color(0xFF0F8B0F),
                              ),
                              const Divider(height: 1, color: Color(0xFFE6E6E3)),
                              _buildActionButton(
                                icon: Icons.videocam,
                                title: 'Video Call',
                                subtitle: 'Start a video call with all members',
                                onTap: () => _initiateGroupCall(true),
                                color: const Color(0xFF0B6BCB),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                        
                        // Members section header
                        Row(
                          children: [
                            const Text(
                              'Members',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF37352F),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F1EF),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${_members.length}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF787774),
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Members list - clean cards
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE6E6E3)),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _members.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              color: Color(0xFFE6E6E3),
                              indent: 60,
                            ),
                            itemBuilder: (context, index) {
                              final member = _members[index];
                              final isCreator = member.id == widget.group['createdBy'];
                              
                              return _buildMemberTile(member, isCreator);
                            },
                          ),
                        ),
                        
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
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

  void _editGroup() {
    // TODO: Implement group editing
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Group editing feature coming soon!'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _leaveGroup() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: const Text('Are you sure you want to leave this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement leave group functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Leave group feature coming soon!'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Leave', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _initiateGroupCall(bool isVideo) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${isVideo ? 'Video' : 'Voice'} call in ${widget.group['name']}'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _messageUser(ChatUser user) {
    Navigator.of(context).pop();
    // TODO: Navigate to private chat with this user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Opening chat with ${user.displayName}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _removeMember(ChatUser user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove ${user.displayName} from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              // TODO: Implement remove member functionality
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${user.displayName} removed from group'),
                  backgroundColor: Colors.red,
                ),
              );
            },
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Helper method to build action buttons
  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF37352F),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF787774),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF9B9A97),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build member tiles
  Widget _buildMemberTile(ChatUser member, bool isCreator) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _messageUser(member),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _getGradientColors(member.displayName.isNotEmpty 
                        ? member.displayName 
                        : member.email),
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    member.displayName.isNotEmpty
                        ? member.displayName[0].toUpperCase()
                        : member.email[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // Name and status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          member.displayName.isNotEmpty 
                              ? member.displayName 
                              : member.email.split('@')[0],
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF37352F),
                          ),
                        ),
                        if (isCreator) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F2EE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Admin',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF787774),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _chatService.formatLastSeen(member.lastSeen, member.isOnline),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9B9A97),
                      ),
                    ),
                  ],
                ),
              ),
              
              // More options
              if (!isCreator)
                IconButton(
                  onPressed: () => _removeMember(member),
                  icon: const Icon(
                    Icons.more_horiz,
                    color: Color(0xFF9B9A97),
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
