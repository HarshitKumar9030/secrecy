import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'profile_screen.dart';
import '../widgets/create_group_dialog.dart';
import '../widgets/linkify_text.dart';
import '../widgets/badged_user_name.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _chatSearchController = TextEditingController();
  ChatUser? _selectedUser;
  String? _selectedGroupId;
  Map<String, dynamic>? _selectedGroup;
  bool _showUsersList = false;
  String _searchQuery = '';
  bool _showChatSearch = false;
  String _chatSearchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updateLastSeen();
    _chatService.startPresenceUpdates();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {    WidgetsBinding.instance.removeObserver(this);
    _chatService.stopPresenceUpdates();
    _searchController.dispose();
    _chatSearchController.dispose();
    super.dispose();
  }

  void _updateLastSeen() {
    _chatService.updateLastSeen();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _chatService.updateUserOnlineStatus(true);
        _chatService.startPresenceUpdates();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _chatService.stopPresenceUpdates();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.user;
    final isLargeScreen = MediaQuery.of(context).size.width > 768;    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F3),
      body: SafeArea(
        child: Stack(
          children: [
            // Main chat area
            Column(
              children: [
                // Chat header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE1E1E0), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // Menu button for mobile
                    if (!isLargeScreen)
                      Container(
                        margin: const EdgeInsets.only(right: 12),
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _showUsersList = !_showUsersList;
                            });
                          },
                          icon: Icon(
                            _showUsersList ? Icons.close : Icons.menu,
                            color: const Color(0xFF9B9A97),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    
                    // Chat title based on selection
                    if (_selectedUser == null && _selectedGroupId == null) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F3437).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.tag,
                          color: Color(0xFF2F3437),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'general',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2F3437),
                        ),
                      ),
                    ] else if (_selectedGroupId != null) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6B6B6B),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.group,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedGroup?['name'] ?? 'Group',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2F3437),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '${(_selectedGroup?['memberIds'] as List?)?.length ?? 0} members',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9B9A97),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _getGradientColors(_selectedUser!.displayName.isNotEmpty 
                                ? _selectedUser!.displayName 
                                : _selectedUser!.email),
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Center(
                          child: Text(
                            _selectedUser!.displayName.isNotEmpty 
                                ? _selectedUser!.displayName[0].toUpperCase()
                                : _selectedUser!.email[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [                            BadgedUserName(
                              senderName: _selectedUser!.displayName,
                              senderEmail: _selectedUser!.email,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2F3437),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _chatService.formatLastSeen(_selectedUser!.lastSeen, _selectedUser!.isOnline),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9B9A97),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                      // Profile and Search buttons
                    const Spacer(),
                    Row(
                      children: [
                        // Search button
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _showChatSearch = !_showChatSearch;
                              if (!_showChatSearch) {
                                _chatSearchController.clear();
                                _chatSearchQuery = '';
                              }
                            });
                          },
                          icon: Icon(
                            _showChatSearch ? Icons.close : Icons.search,
                            color: const Color(0xFF9B9A97),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        if (_selectedUser != null)
                          IconButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => NewProfileScreen(
                                    user: _selectedUser,
                                    isEditable: false,
                                    onMessageTap: () {
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.person,
                              color: Color(0xFF9B9A97),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ],                ),
              ),
              
              // Search bar (when active)
              if (_showChatSearch)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE1E1E0), width: 1),
                    ),
                  ),
                  child: TextField(
                    controller: _chatSearchController,
                    onChanged: (value) {
                      setState(() {
                        _chatSearchQuery = value;
                      });
                    },
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF9B9A97)),
                      suffixIcon: _chatSearchController.text.isNotEmpty
                          ? IconButton(
                              onPressed: () {
                                _chatSearchController.clear();
                                setState(() {
                                  _chatSearchQuery = '';
                                });
                              },
                              icon: const Icon(Icons.clear, color: Color(0xFF9B9A97)),
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE1E1E0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE1E1E0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF2F3437), width: 2),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7F6F3),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              
              // Messages
              Expanded(
                child: ChatMessagesView(
                  chatService: _chatService,
                  selectedUser: _selectedUser,
                  selectedGroupId: _selectedGroupId,
                  selectedGroup: _selectedGroup,
                  searchQuery: _chatSearchQuery,
                ),
              ),
            ],
          ),

          // Sidebar overlay for large screens
          if (isLargeScreen)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 280,
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFF7F6F3),
                  border: Border(
                    right: BorderSide(color: Color(0xFFE1E1E0), width: 1),
                  ),
                ),
                child: _buildSidebar(currentUser, isLargeScreen),
              ),
            ),

          // Sidebar overlay for mobile
          if (_showUsersList && !isLargeScreen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showUsersList = false;
                  });
                },
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 280,
                      height: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF7F6F3),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: _buildSidebar(currentUser, isLargeScreen),
                    ),                  ),
                ),
              ),
            ),
        ],
        ),
      ),
    );
  }

  Widget _buildSidebar(User? currentUser, bool isLargeScreen) {
    return Column(
      children: [
        // Header with user info
        Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFFE1E1E0), width: 1),
            ),
          ),          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2F3437), Color(0xFF4A4F52)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    (currentUser?.displayName?.isNotEmpty == true
                        ? currentUser!.displayName![0]
                        : currentUser?.email?[0] ?? 'U').toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: !isLargeScreen ? () {
                    _showProfileMenuForMobile(context);
                  } : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [                          Expanded(
                            child: currentUser?.displayName?.isNotEmpty == true
                                ? BadgedUserName(
                                    senderName: currentUser!.displayName!,
                                    senderEmail: currentUser.email!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: Color(0xFF2F3437),
                                    ),
                                  )
                                : const Text(
                                    'You',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      color: Color(0xFF2F3437),
                                    ),
                                  ),
                          ),
                          if (!isLargeScreen)
                            const Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF9B9A97),
                              size: 20,
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentUser?.email ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF9B9A97),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLargeScreen)
                IconButton(
                  onPressed: () {
                    setState(() {
                      _showUsersList = false;
                    });
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Color(0xFF9B9A97),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                )
              else
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'logout') {
                      await Provider.of<AuthService>(context, listen: false).signOut();
                    } else if (value == 'profile') {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const NewProfileScreen(isEditable: true),
                        ),
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'profile',
                      child: Row(
                        children: [
                          Icon(Icons.person_outline, size: 18),
                          SizedBox(width: 8),
                          Text('Profile'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 8),
                          Text('Logout'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: Colors.transparent,
                    ),
                    child: const Icon(
                      Icons.more_horiz,
                      color: Color(0xFF9B9A97),
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
        ),
        
        // Chat options
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildChatOption(
                icon: Icons.tag,
                title: 'General Chat',
                isSelected: _selectedUser == null && _selectedGroupId == null,
                onTap: () {
                  setState(() {
                    _selectedUser = null;
                    _selectedGroupId = null;
                    _selectedGroup = null;
                    if (!isLargeScreen) {
                      _showUsersList = false;
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              Container(
                height: 1,
                color: const Color(0xFFE1E1E0),
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              
              // Groups Section
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'GROUPS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9B9A97),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
                // Groups List
              StreamBuilder<List<Map<String, dynamic>>>(
                stream: _chatService.getGroups(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Error loading groups: ${snapshot.error}',
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                    );
                  }
                  
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF9B9A97),
                          ),
                        ),
                      ),
                    );
                  }
                  
                  if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                    return Column(
                      children: snapshot.data!.map((group) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _buildGroupItem(group, isLargeScreen),
                        );
                      }).toList(),
                    );
                  }
                  
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No groups yet',
                      style: TextStyle(
                        color: Color(0xFF9B9A97),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 8),
              Container(
                height: 1,
                color: const Color(0xFFE1E1E0),
                margin: const EdgeInsets.symmetric(vertical: 8),
              ),
              
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DIRECT MESSAGES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF9B9A97),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Create Group Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final users = await _chatService.searchUsers('').first;
                      final result = await showDialog<String>(
                        context: context,
                        builder: (context) => CreateGroupDialog(
                          allUsers: users,
                        ),
                      );
                      if (result != null) {
                        setState(() {});
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error loading users: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.group_add),
                  label: const Text('Create Group'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Search Field
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFE1E1E0)),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search users...',
                    hintStyle: TextStyle(
                      color: Color(0xFF9B9A97),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      color: Color(0xFF9B9A97),
                      size: 18,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 12),
              
              // Help text
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Text(
                  'Tap to chat • Tap avatar to view profile • Long press for options',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9B9A97),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
        
        // Users list
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: StreamBuilder<List<ChatUser>>(
              stream: _searchQuery.isEmpty 
                  ? _chatService.getUsers()
                  : _chatService.searchUsers(_searchQuery),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading users: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }
                
                if (!snapshot.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                
                final users = snapshot.data!
                    .where((user) => user.id != currentUser?.uid)
                    .toList();
                    
                if (users.isEmpty) {
                  return Center(
                    child: Text(
                      _searchQuery.isEmpty 
                          ? 'No other users yet'
                          : 'No users found for "$_searchQuery"',
                      style: const TextStyle(
                        color: Color(0xFF9B9A97),
                        fontSize: 14,
                      ),
                    ),
                  );
                }
                
                return ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _buildUserItem(user, isLargeScreen);
                  },
                );
              },
            ),
          ),
        ),
        
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChatOption({
    required IconData icon,
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF37352F).withOpacity(0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? const Color(0xFF2F3437) : const Color(0xFF9B9A97),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                  color: isSelected ? const Color(0xFF2F3437) : const Color(0xFF6B6B6B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserItem(ChatUser user, bool isLargeScreen) {
    final isSelected = _selectedUser?.id == user.id;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedUser = user;
            _selectedGroupId = null;
            _selectedGroup = null;
            if (!isLargeScreen) {
              _showUsersList = false;
            }
          });
        },
        onLongPress: () {
          _showUserProfileMenu(user);
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF37352F).withOpacity(0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => NewProfileScreen(
                            user: user,
                            isEditable: false,
                            onMessageTap: () {
                              Navigator.of(context).pop();
                              setState(() {
                                _selectedUser = user;
                                _showUsersList = false;
                              });
                            },
                          ),
                        ),
                      );
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _getGradientColors(user.displayName.isNotEmpty ? user.displayName : user.email),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          user.displayName.isNotEmpty 
                              ? user.displayName[0].toUpperCase()
                              : user.email[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (user.isOnline)
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(
                            BorderSide(color: Color(0xFFF7F6F3), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [                    BadgedUserName(
                      senderName: user.displayName,
                      senderEmail: user.email,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected ? const Color(0xFF2F3437) : const Color(0xFF6B6B6B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _chatService.formatLastSeen(user.lastSeen, user.isOnline),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9B9A97),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupItem(Map<String, dynamic> group, bool isLargeScreen) {
    final isSelected = _selectedGroupId == group['id'];
    final groupName = group['name'] ?? 'Unnamed Group';
    final memberCount = (group['memberIds'] as List?)?.length ?? 0;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedUser = null;
            _selectedGroupId = group['id'];
            _selectedGroup = group;
            if (!isLargeScreen) {
              _showUsersList = false;
            }
          });
        },
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF37352F).withOpacity(0.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B6B6B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.group,
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      groupName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                        color: isSelected ? const Color(0xFF2F3437) : const Color(0xFF6B6B6B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '$memberCount members',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9B9A97),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserProfileMenu(ChatUser user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E1E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _getGradientColors(user.displayName.isNotEmpty ? user.displayName : user.email),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        user.displayName.isNotEmpty 
                            ? user.displayName[0].toUpperCase()
                            : user.email[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [                        BadgedUserName(
                          senderName: user.displayName,
                          senderEmail: user.email,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2F3437),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _chatService.formatLastSeen(user.lastSeen, user.isOnline),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF9B9A97),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => NewProfileScreen(
                              user: user,
                              isEditable: false,
                              onMessageTap: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  _selectedUser = user;
                                  _showUsersList = false;
                                });
                              },
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.person),
                      label: const Text('View Profile'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF7F6F3),
                        foregroundColor: const Color(0xFF2F3437),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFFE1E1E0)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        setState(() {
                          _selectedUser = user;
                          _selectedGroupId = null;
                          _selectedGroup = null;
                          _showUsersList = false;
                        });
                      },
                      icon: const Icon(Icons.message),
                      label: const Text('Message'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.black,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showProfileMenuForMobile(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E1E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.person_outline, color: Color(0xFF2F3437)),
                title: const Text('Profile'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NewProfileScreen(isEditable: true),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Color(0xFF2F3437)),
                title: const Text('Logout'),
                onTap: () async {
                  Navigator.pop(context);
                  await Provider.of<AuthService>(context, listen: false).signOut();
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
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
      [const Color(0xFFa8caba), const Color(0xFF5d4e75)],    ];
    return colorPairs[hash % colorPairs.length];
  }
}

// ChatMessagesView widget
class ChatMessagesView extends StatefulWidget {
  final ChatService chatService;
  final ChatUser? selectedUser;
  final String? selectedGroupId;
  final Map<String, dynamic>? selectedGroup;
  final String? searchQuery;

  const ChatMessagesView({
    super.key,
    required this.chatService,
    this.selectedUser,
    this.selectedGroupId,
    this.selectedGroup,
    this.searchQuery,
  });

  @override
  State<ChatMessagesView> createState() => _ChatMessagesViewState();
}

class _ChatMessagesViewState extends State<ChatMessagesView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      final hasText = _messageController.text.trim().isNotEmpty;
      if (hasText != _hasText) {
        setState(() {
          _hasText = hasText;
        });
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    _messageController.clear();

    try {
      await widget.chatService.sendMessageOptimistic(
        content,
        recipientId: widget.selectedUser?.id,
        groupId: widget.selectedGroupId,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 80,
      );

      if (image != null) {
        setState(() {
          _isLoading = true;
        });

        await widget.chatService.sendImage(
          File(image.path),
          recipientId: widget.selectedUser?.id,
          groupId: widget.selectedGroupId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );

      if (video != null) {
        setState(() {
          _isLoading = true;
        });

        await widget.chatService.sendVideo(
          File(video.path),
          recipientId: widget.selectedUser?.id,
          groupId: widget.selectedGroupId,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send video: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadMoreMessages() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      await widget.chatService.loadMoreMessages(
        recipientId: widget.selectedUser?.id,
        groupId: widget.selectedGroupId,
      );
    } catch (e) {
      print('Error loading more messages: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Messages list
        Expanded(
          child: Container(
            color: Colors.white,            child: StreamBuilder<List<Message>>(
              stream: widget.searchQuery != null && widget.searchQuery!.trim().isNotEmpty
                  ? widget.chatService.searchMessagesInChat(
                      widget.searchQuery!,
                      recipientId: widget.selectedUser?.id,
                      groupId: widget.selectedGroupId,
                    )
                  : widget.chatService.getMessagesStream(
                      recipientId: widget.selectedUser?.id,
                      groupId: widget.selectedGroupId,
                    ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error loading messages',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${snapshot.error}',
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                final messages = snapshot.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.selectedUser == null && widget.selectedGroupId == null
                              ? Icons.tag_outlined 
                              : widget.selectedGroupId != null
                                  ? Icons.group_outlined
                                  : Icons.message_outlined,
                          size: 64,
                          color: const Color(0xFF9B9A97),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.selectedUser == null && widget.selectedGroupId == null
                              ? 'Welcome to #general'
                              : widget.selectedGroupId != null
                                  ? 'Welcome to ${widget.selectedGroup?['name'] ?? 'this group'}'
                                  : 'Start your conversation with ${widget.selectedUser!.displayName.isNotEmpty ? widget.selectedUser!.displayName : widget.selectedUser!.email.split('@')[0]}',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFF9B9A97),
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Send a message to get started!',
                          style: TextStyle(color: Color(0xFF9B9A97)),
                        ),
                      ],
                    ),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    // Load more messages when scrolling near the top
                    if (scrollInfo.metrics.pixels <= scrollInfo.metrics.maxScrollExtent * 0.1) {
                      _loadMoreMessages();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(20),
                    itemCount: messages.length + (widget.chatService.hasMoreMessages(
                      recipientId: widget.selectedUser?.id,
                      groupId: widget.selectedGroupId,
                    ) ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show loading indicator at the top for pagination
                      if (index == 0 && widget.chatService.hasMoreMessages(
                        recipientId: widget.selectedUser?.id,
                        groupId: widget.selectedGroupId,
                      )) {
                        return Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF9B9A97),
                              ),
                            ),
                          ),
                        );
                      }
                      
                      // Adjust index for messages
                      final messageIndex = widget.chatService.hasMoreMessages(
                        recipientId: widget.selectedUser?.id,
                        groupId: widget.selectedGroupId,
                      ) ? index - 1 : index;
                      
                      if (messageIndex < 0 || messageIndex >= messages.length) {
                        return const SizedBox.shrink();
                      }
                      
                      final message = messages[messageIndex];
                      return NotionMessageBubble(
                        message: message,
                        chatService: widget.chatService,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),

        // Message input
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Color(0xFFE1E1E0), width: 1),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _showMediaPicker,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F6F3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE1E1E0)),
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Color(0xFF9B9A97),
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F6F3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE1E1E0)),
                  ),
                  child: TextField(
                    controller: _messageController,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(color: Color(0xFF9B9A97)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _hasText ? _sendMessage : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _hasText ? Colors.black : const Color(0xFFF7F6F3),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _hasText ? Colors.black : const Color(0xFFE1E1E0),
                      ),
                    ),
                    child: Icon(
                      Icons.send,
                      color: _hasText ? Colors.white : const Color(0xFF9B9A97),
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE1E1E0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Share',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2F3437),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildMediaOption(
                    icon: Icons.photo,
                    label: 'Photo',
                    onTap: () {
                      Navigator.of(context).pop();
                      _sendImage();
                    },
                  ),
                  _buildMediaOption(
                    icon: Icons.videocam,
                    label: 'Video',
                    onTap: () {
                      Navigator.of(context).pop();
                      _sendVideo();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMediaOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F6F3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E1E0)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
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
                fontSize: 12,
                color: Color(0xFF2F3437),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// NotionMessageBubble widget - simplified version
class NotionMessageBubble extends StatelessWidget {
  final Message message;
  final ChatService chatService;

  const NotionMessageBubble({
    super.key,
    required this.message,
    required this.chatService,
  });

  @override
  Widget build(BuildContext context) {
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
              children: [                Row(
                  children: [                    BadgedUserName(
                      senderName: message.senderName,
                      senderEmail: message.senderEmail,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Color(0xFF2F3437),
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
                    if (message.isOptimistic) ...[
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.schedule,
                        size: 12,
                        color: Color(0xFF9B9A97),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                if (message.type == MessageType.text) ...[
                  LinkifyText(
                    text: message.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2F3437),
                      height: 1.4,
                    ),
                  ),
                ] else if (message.type == MessageType.image) ...[
                  if (message.imageUrl != null)
                    Container(
                      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          imageUrl: message.imageUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            width: 200,
                            height: 200,
                            color: const Color(0xFFF7F6F3),
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            width: 200,
                            height: 200,
                            color: const Color(0xFFF7F6F3),
                            child: const Icon(Icons.error),
                          ),
                        ),
                      ),
                    ),
                  if (message.content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      message.content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2F3437),
                      ),
                    ),
                  ],
                ] else if (message.type == MessageType.video) ...[
                  if (message.videoUrl != null)
                    Container(
                      constraints: const BoxConstraints(maxWidth: 300, maxHeight: 300),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F6F3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE1E1E0)),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.play_circle_filled,
                              size: 48,
                              color: Color(0xFF9B9A97),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (message.content.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      message.content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2F3437),
                      ),
                    ),
                  ],
                ],
              ],
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
}
