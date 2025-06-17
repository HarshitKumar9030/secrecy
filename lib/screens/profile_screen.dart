import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../models/user.dart';

class NewProfileScreen extends StatefulWidget {
  final ChatUser? user; // If null, shows current user's profile for editing
  final bool isEditable;
  final VoidCallback? onMessageTap; // Callback for starting a chat

  const NewProfileScreen({
    super.key,
    this.user,
    this.isEditable = false,
    this.onMessageTap,
  });

  @override
  State<NewProfileScreen> createState() => _NewProfileScreenState();
}

class _NewProfileScreenState extends State<NewProfileScreen> 
    with TickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  final ImagePicker _imagePicker = ImagePicker();
  
  late TextEditingController _displayNameController;
  late TextEditingController _bioController;
  late TextEditingController _statusController;
  
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _scaleController;
  
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  
  bool _isLoading = false;
  bool _isEditing = false;
  String? _selectedPhotoPath;
  ChatUser? _currentUserProfile;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeProfile();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.elasticOut,
    ));

    // Start animations
    _fadeController.forward();
    _slideController.forward();
    _scaleController.forward();
  }

  Future<void> _initializeProfile() async {
    if (widget.user != null) {
      // Viewing another user's profile
      final user = widget.user!;
      _displayNameController = TextEditingController(text: user.displayName);
      _bioController = TextEditingController(text: user.bio ?? '');
      _statusController = TextEditingController(text: user.status ?? '');
    } else {
      // Current user's profile - fetch from Firestore
      setState(() {
        _isLoading = true;
      });
      
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        final firebaseUser = authService.user;
        if (firebaseUser != null) {
          // Get complete profile from Firestore
          final usersStream = _chatService.searchUsers('');
          final users = await usersStream.first;
          final currentUserList = users.where((user) => user.id == firebaseUser.uid).toList();
          
          final currentUser = currentUserList.isNotEmpty 
              ? currentUserList.first
              : ChatUser(
                  id: firebaseUser.uid,
                  email: firebaseUser.email ?? '',
                  displayName: firebaseUser.displayName ?? '',
                  photoUrl: firebaseUser.photoURL,
                  lastSeen: DateTime.now(),
                  isOnline: true,
                );
          
          setState(() {
            _currentUserProfile = currentUser;
            _displayNameController = TextEditingController(text: currentUser.displayName);
            _bioController = TextEditingController(text: currentUser.bio ?? '');
            _statusController = TextEditingController(text: currentUser.status ?? '');
          });
        }
      } catch (e) {
        print('Error fetching user profile: $e');
        // Fallback to basic profile
        final authService = Provider.of<AuthService>(context, listen: false);
        final firebaseUser = authService.user;
        if (firebaseUser != null) {
          final user = ChatUser(
            id: firebaseUser.uid,
            email: firebaseUser.email ?? '',
            displayName: firebaseUser.displayName ?? '',
            photoUrl: firebaseUser.photoURL,
            lastSeen: DateTime.now(),
            isOnline: true,
          );
          setState(() {
            _currentUserProfile = user;
            _displayNameController = TextEditingController(text: user.displayName);
            _bioController = TextEditingController(text: user.bio ?? '');
            _statusController = TextEditingController(text: user.status ?? '');
          });
        }
      }
      
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _scaleController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 70,
      );
      
      if (image != null) {
        setState(() {
          _selectedPhotoPath = image.path;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      String? photoUrl;
      
      // Upload new photo if selected
      if (_selectedPhotoPath != null) {
        photoUrl = await _chatService.uploadProfileImage(File(_selectedPhotoPath!));
      }

      // Update profile
      await _chatService.updateUserProfile(
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        status: _statusController.text.trim(),
        photoUrl: photoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        
        setState(() {
          _isEditing = false;
          _selectedPhotoPath = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() {
      _isLoading = false;
    });
  }
  Widget _buildProfileHeader() {
    final user = widget.user ?? _currentUserProfile;
    if (user == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 40),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            children: [
              // Profile Avatar
              ScaleTransition(
                scale: _scaleAnimation,
                child: GestureDetector(
                  onTap: widget.isEditable && _isEditing ? _pickImage : null,
                  child: Stack(
                    children: [
                      Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade50,
                          border: Border.all(
                            color: Colors.grey.shade100,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 32,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: _selectedPhotoPath != null
                              ? Image.file(
                                  File(_selectedPhotoPath!),
                                  fit: BoxFit.cover,
                                )
                              : user.photoUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: user.photoUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey.shade100,
                                        child: Icon(
                                          Icons.person,
                                          size: 70,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: Colors.grey.shade100,
                                        child: Icon(
                                          Icons.person,
                                          size: 70,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey.shade100,
                                      child: Icon(
                                        Icons.person,
                                        size: 70,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                        ),
                      ),
                      if (widget.isEditable && _isEditing)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.black,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // Name and Email
              Column(
                children: [
                  Text(
                    user.displayName.isNotEmpty ? user.displayName : 'No Name',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                      letterSpacing: -0.8,
                      height: 1.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    user.email,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                      letterSpacing: -0.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  
                  // Status Badge
                  if (user.status != null && user.status!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.shade100,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        user.status!,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade800,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                  
                  // Online Status
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: user.isOnline ? Colors.green : Colors.grey.shade400,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        user.isOnline
                            ? 'Online'
                            : 'Last seen ${_formatLastSeen(user.lastSeen)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
    String? hint,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.black,
                letterSpacing: -0.1,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: _isEditing ? Colors.white : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isEditing ? Colors.grey.shade200 : Colors.grey.shade100,
                width: 1,
              ),
            ),
            child: TextField(
              controller: controller,
              maxLines: maxLines,
              enabled: _isEditing,
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(16),
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 15,
                ),
              ),
              style: TextStyle(
                fontSize: 15,
                color: _isEditing ? Colors.black : Colors.grey.shade700,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final user = widget.user ?? _currentUserProfile;
    if (user == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade100,
          width: 1,
        ),
      ),      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Profile Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: -0.2,
                  ),
                ),
                if (widget.isEditable)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isEditing = !_isEditing;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _isEditing ? Colors.black : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _isEditing ? Icons.close : Icons.edit,
                        color: _isEditing ? Colors.white : Colors.black,
                        size: 16,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            
            // Fields
            _buildEditableField(
              label: 'Display Name',
              controller: _displayNameController,
              icon: Icons.person_outline,
              hint: 'Enter your display name',
            ),
            _buildEditableField(
              label: 'Bio',
              controller: _bioController,
              icon: Icons.info_outline,
              maxLines: 3,
              hint: 'Tell us about yourself...',
            ),
            _buildEditableField(
              label: 'Status',
              controller: _statusController,
              icon: Icons.mood_outlined,
              hint: 'What\'s your current mood?',
            ),
            
            // Save Button
            if (_isEditing) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    disabledBackgroundColor: Colors.grey.shade300,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Save Changes',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  Widget _buildActionButtons() {
    if (widget.user == null || widget.isEditable) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: widget.onMessageTap,
              icon: const Icon(Icons.message_outlined, size: 18),
              label: const Text('Send Message'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                // TODO: Add to favorites or call functionality
              },
              icon: Icon(Icons.favorite_border, size: 18, color: Colors.grey.shade600),
              label: Text(
                'Favorite',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                side: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final difference = now.difference(lastSeen);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'just now';
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.black,
                strokeWidth: 2,
              ),
            )
          : CustomScrollView(
              slivers: [
                // Custom App Bar
                SliverAppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  pinned: true,
                  expandedHeight: 0,
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.arrow_back_ios_new,
                        color: Colors.black,
                        size: 16,
                      ),
                    ),
                  ),
                  title: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      widget.isEditable ? 'Edit Profile' : 'Profile',
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  actions: [
                    if (widget.isEditable && !_isEditing)
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isEditing = true;
                          });
                        },
                        icon: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.black,
                            size: 16,
                          ),
                        ),
                      ),
                    const SizedBox(width: 16),
                  ],
                ),
                
                // Profile Content
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      _buildProfileHeader(),
                      _buildInfoCard(),
                      _buildActionButtons(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
