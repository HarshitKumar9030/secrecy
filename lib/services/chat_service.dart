import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../models/call_log.dart';
import '../models/chat_item.dart';
import 'event_bus.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();
  
  // Cache for messages and streams
  final Map<String, List<Message>> _messageCache = {};
  final Map<String, StreamController<List<Message>>> _messageControllers = {};
  final Map<String, StreamController<List<ChatItem>>> _chatItemControllers = {};
  final Map<String, StreamSubscription?> _activeStreams = {};
  final Map<String, DocumentSnapshot?> _lastDocuments = {};
  final Map<String, bool> _hasMoreMessages = {};
  final Map<String, bool> _isLoadingMore = {};
  
  // Upload progress tracking
  final Map<String, StreamController<double>> _uploadProgressControllers = {};
  final Map<String, UploadTask> _activeUploads = {};
  
  // Settings
  static const int _messagesPerPage = 20;
  static const int _initialLoadCount = 50;
  
  Timer? _presenceTimer;
  bool _migrationRun = false;
  // Constructor
  ChatService() {
    // Run migration once when service is created
    _runMigrationOnce();
    
    // Listen for call log events
    _listenForCallLogEvents();
  }

  Future<void> _runMigrationOnce() async {
    if (!_migrationRun) {
      _migrationRun = true;
      await migrateGeneralMessages();
    }
  }

  // Send message with optimistic updates
  Future<String> sendMessageOptimistic(String content, {String? recipientId, String? groupId}) async {
    final user = _auth.currentUser;
    if (user == null) return '';

    // Generate temporary ID for optimistic update
    final tempId = 'temp_${_uuid.v4()}';
    final timestamp = DateTime.now();
    
    final message = Message(
      id: tempId,
      content: content,
      type: MessageType.text,
      senderId: user.uid,
      senderEmail: user.email ?? '',
      senderName: user.displayName ?? user.email?.split('@')[0] ?? 'Anonymous',
      senderPhotoUrl: user.photoURL,
      recipientId: recipientId,
      groupId: groupId,
      timestamp: timestamp,
      isOptimistic: true,
    );

    // Add to cache immediately for instant UI update
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    _addMessageToCache(cacheKey, message);    try {
      // Send to server
      final messageData = message.toMap();
      messageData.remove('isOptimistic');
      
      // Add chatType and chatRoomId for consistent querying
      if (groupId != null) {
        messageData['chatType'] = 'group';
        messageData['chatRoomId'] = null;
      } else if (recipientId == null) {
        messageData['chatType'] = 'general';
        messageData['chatRoomId'] = null;
        messageData['recipientId'] = null;
        messageData['groupId'] = null;
      } else {
        messageData['chatType'] = 'private';
        messageData['chatRoomId'] = _getChatRoomId(user.uid, recipientId);
        messageData['groupId'] = null;
      }
      
      // Always use the main messages collection
      final docRef = await _firestore.collection('messages').add(messageData);

      // Update cache with real ID
      _updateOptimisticMessage(cacheKey, tempId, docRef.id);
      return docRef.id;
    } catch (e) {
      // Remove from cache if failed
      _removeMessageFromCache(cacheKey, tempId);
      rethrow;
    }
  }

  // Send image message
  Future<void> sendImage(File imageFile, {String? recipientId, String? groupId, String? caption}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      // Upload image to Firebase Storage
      final imageId = _uuid.v4();
      final ref = _storage.ref().child('chat_images').child('$imageId.jpg');
      
      final uploadTask = ref.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          cacheControl: 'max-age=3600',
        ),
      );
      
      final snapshot = await uploadTask.whenComplete(() {});
      final imageUrl = await snapshot.ref.getDownloadURL();

      final message = Message(
        id: '',
        content: caption ?? '',
        type: MessageType.image,
        imageUrl: imageUrl,
        senderId: user.uid,
        senderEmail: user.email ?? '',
        senderName: user.displayName ?? user.email?.split('@')[0] ?? 'Anonymous',
        senderPhotoUrl: user.photoURL,
        recipientId: recipientId,
        groupId: groupId,        timestamp: DateTime.now(),
      );

      final messageData = message.toMap();
      
      // Add chatType and chatRoomId for consistent querying
      if (groupId != null) {
        messageData['chatType'] = 'group';
        messageData['chatRoomId'] = null;
      } else if (recipientId == null) {
        messageData['chatType'] = 'general';
        messageData['chatRoomId'] = null;
        messageData['recipientId'] = null;
        messageData['groupId'] = null;
      } else {
        messageData['chatType'] = 'private';
        messageData['chatRoomId'] = _getChatRoomId(user.uid, recipientId);
        messageData['groupId'] = null;
      }

      // Always use the main messages collection
      await _firestore.collection('messages').add(messageData);
    } catch (e) {
      print('Error in sendImage: $e');
      throw Exception('Failed to upload image: $e');
    }
  }

  // Send video message
  Future<void> sendVideo(File videoFile, {String? recipientId, String? groupId, String? caption}) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final videoId = _uuid.v4();
      final ref = _storage.ref().child('chat_videos').child('$videoId.mp4');
      
      final uploadTask = ref.putFile(videoFile);
      final snapshot = await uploadTask;
      final videoUrl = await snapshot.ref.getDownloadURL();

      final message = Message(
        id: '',
        content: caption ?? '',
        type: MessageType.video,
        videoUrl: videoUrl,
        senderId: user.uid,
        senderEmail: user.email ?? '',
        senderName: user.displayName ?? user.email?.split('@')[0] ?? 'Anonymous',
        senderPhotoUrl: user.photoURL,
        recipientId: recipientId,
        groupId: groupId,        timestamp: DateTime.now(),
      );

      final messageData = message.toMap();
      
      // Add chatType and chatRoomId for consistent querying
      if (groupId != null) {
        messageData['chatType'] = 'group';
        messageData['chatRoomId'] = null;
      } else if (recipientId == null) {
        messageData['chatType'] = 'general';
        messageData['chatRoomId'] = null;
        messageData['recipientId'] = null;
        messageData['groupId'] = null;
      } else {
        messageData['chatType'] = 'private';
        messageData['chatRoomId'] = _getChatRoomId(user.uid, recipientId);
        messageData['groupId'] = null;
      }

      // Always use the main messages collection
      await _firestore.collection('messages').add(messageData);
    } catch (e) {
      print('Error in sendVideo: $e');
      throw Exception('Failed to upload video: $e');
    }
  }
  // Get messages stream (main method)
  Stream<List<Message>> getMessagesStream({String? recipientId, String? groupId}) {
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    
    // Always clear existing cache to ensure fresh data when switching chats
    if (_messageControllers.containsKey(cacheKey)) {
      clearChatCache(recipientId: recipientId, groupId: groupId);
    }
    
    // Create fresh controller
    _messageControllers[cacheKey] = StreamController<List<Message>>.broadcast();
    _messageCache[cacheKey] = [];
    _hasMoreMessages[cacheKey] = true;
    _isLoadingMore[cacheKey] = false;
    
    // Immediately emit empty list to prevent hanging
    _messageControllers[cacheKey]!.add([]);
    
    // Load initial messages asynchronously
    _loadInitialMessages(cacheKey, recipientId: recipientId, groupId: groupId);
    
    return _messageControllers[cacheKey]!.stream;
  }

  // Get messages (compatibility method)
  Stream<List<Message>> getMessages({String? recipientId, String? groupId}) {
    return getMessagesStream(recipientId: recipientId, groupId: groupId);
  }

  // Send message (compatibility method)
  Future<void> sendMessage(String content, {String? recipientId, String? groupId}) async {
    await sendMessageOptimistic(content, recipientId: recipientId, groupId: groupId);  }
  // Load initial messages
  Future<void> _loadInitialMessages(String cacheKey, {String? recipientId, String? groupId}) async {
    print('🔄 Loading initial messages for cacheKey: $cacheKey');
    print('   recipientId: $recipientId, groupId: $groupId');
    
    try {
      List<Message> messages;
        if (recipientId != null && groupId == null) {
        // Private chat - use special method to get both directions
        print('   📱 Loading private chat messages');
        messages = await _getPrivateChatMessages(recipientId, limit: _initialLoadCount);
        
        // Set pagination state for private chats
        _lastDocuments[cacheKey] = null; // TODO: Implement proper pagination for private chats
        _hasMoreMessages[cacheKey] = messages.length == _initialLoadCount;
      } else {
        // General or group chat - use normal query
        final chatType = recipientId == null && groupId == null ? 'general' : 'group';
        print('   🌐 Loading $chatType chat messages');
        
        Query query = _buildMessageQuery(recipientId: recipientId, groupId: groupId);
        query = query.orderBy('timestamp', descending: true).limit(_initialLoadCount);
        
        final snapshot = await query.get();
        print('   📥 Got ${snapshot.docs.length} messages from Firestore');
        
        messages = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Message.fromMap(data, doc.id);
        }).toList();
        
        _lastDocuments[cacheKey] = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMoreMessages[cacheKey] = snapshot.docs.length == _initialLoadCount;
      }
        // Sort to show oldest first
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      _messageCache[cacheKey] = messages;
      print('   ✅ Cached ${messages.length} messages');
      
      // Notify listeners with the loaded messages
      if (_messageControllers.containsKey(cacheKey)) {
        _messageControllers[cacheKey]!.add(List.from(messages));
        print('   📤 Sent messages to UI');
      }
      
      // Set up real-time listener for new messages
      _setupRealtimeListener(cacheKey, recipientId: recipientId, groupId: groupId);
    } catch (e) {
      print('❌ Error loading initial messages: $e');
      // Still set up listener even if initial load fails
      _setupRealtimeListener(cacheKey, recipientId: recipientId, groupId: groupId);
    }
  }

  // Setup real-time listener
  void _setupRealtimeListener(String cacheKey, {String? recipientId, String? groupId}) {
    // Cancel existing listener if any
    _activeStreams[cacheKey]?.cancel();
    
    Query query = _buildMessageQuery(recipientId: recipientId, groupId: groupId);
    
    // Only listen for new messages after the last loaded message
    if (_messageCache[cacheKey]!.isNotEmpty) {
      final lastMessage = _messageCache[cacheKey]!.last;
      query = query.where('timestamp', isGreaterThan: Timestamp.fromDate(lastMessage.timestamp));
    }
    
    // Set up the listener
    _activeStreams[cacheKey] = query
        .orderBy('timestamp', descending: false)
        .snapshots()
        .listen(
      (snapshot) {
        bool hasNewMessages = false;
        for (final change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            final data = change.doc.data() as Map<String, dynamic>;
            final message = Message.fromMap(data, change.doc.id);
            
            // Prevent duplicates
            final isDuplicate = _messageCache[cacheKey]!.any((m) => 
              m.id == message.id || 
              (m.isOptimistic && m.content == message.content && m.senderId == message.senderId)
            );
            
            if (!isDuplicate) {
              _addMessageToCache(cacheKey, message, notify: false);
              hasNewMessages = true;
            }
          }
        }
        
        // Notify only if we have new messages
        if (hasNewMessages && _messageControllers.containsKey(cacheKey)) {
          _messageControllers[cacheKey]!.add(List.from(_messageCache[cacheKey]!));
        }
      },
      onError: (error) {
        print('Error in real-time listener: $error');
      },
    );
  }  // Build query for messages
  Query _buildMessageQuery({String? recipientId, String? groupId}) {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    if (recipientId == null && groupId == null) {
      // General chat - use chatType field
      print('    🔍 Building general chat query using chatType');
      return _firestore
          .collection('messages')
          .where('chatType', isEqualTo: 'general');
    } else if (groupId != null) {
      // Group chat - use chatType + groupId
      print('    🔍 Building group chat query (chatType: group, groupId: $groupId)');
      return _firestore
          .collection('messages')
          .where('chatType', isEqualTo: 'group')
          .where('groupId', isEqualTo: groupId);
    } else {
      // Private chat - use chatType + chatRoomId
      final chatRoomId = _getChatRoomId(user.uid, recipientId!);
      print('    🔍 Building private chat query (chatType: private, chatRoomId: $chatRoomId)');
      return _firestore
          .collection('messages')
          .where('chatType', isEqualTo: 'private')
          .where('chatRoomId', isEqualTo: chatRoomId);
    }
  }

  // Load more messages (pagination)
  Future<void> loadMoreMessages({String? recipientId, String? groupId}) async {
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    
    if (_isLoadingMore[cacheKey] == true) return;
    if (!(_hasMoreMessages[cacheKey] ?? true) || _lastDocuments[cacheKey] == null) return;
    
    _isLoadingMore[cacheKey] = true;
    
    try {
      Query query = _buildMessageQuery(recipientId: recipientId, groupId: groupId);
      query = query
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastDocuments[cacheKey]!)
          .limit(_messagesPerPage);
      
      final snapshot = await query.get();
      
      if (snapshot.docs.isEmpty) {
        _hasMoreMessages[cacheKey] = false;
        return;
      }
      
      final newMessages = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Message.fromMap(data, doc.id);
      }).toList();
      
      // Add to beginning of cache (oldest messages)
      newMessages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      _messageCache[cacheKey]!.insertAll(0, newMessages);
      
      _lastDocuments[cacheKey] = snapshot.docs.last;
      _hasMoreMessages[cacheKey] = snapshot.docs.length == _messagesPerPage;
      
      // Notify listeners
      if (_messageControllers.containsKey(cacheKey)) {
        _messageControllers[cacheKey]!.add(List.from(_messageCache[cacheKey]!));
      }
    } catch (e) {
      print('Error loading more messages: $e');
    } finally {
      _isLoadingMore[cacheKey] = false;
    }
  }

  // Check if has more messages
  bool hasMoreMessages({String? recipientId, String? groupId}) {
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    return _hasMoreMessages[cacheKey] ?? true;
  }

  // User management
  Stream<List<ChatUser>> getUsers() {
    return _firestore.collection('users').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return ChatUser.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  Stream<List<ChatUser>> searchUsers(String query) {
    if (query.isEmpty) {
      return getUsers();
    }
    
    return _firestore
        .collection('users')
        .where('displayName', isGreaterThanOrEqualTo: query)
        .where('displayName', isLessThanOrEqualTo: query + '\uf8ff')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return ChatUser.fromMap(doc.data(), doc.id);
      }).toList();
    }).handleError((e) {
      print('Error searching users: $e');
      return <ChatUser>[];
    });
  }

  // Get multiple users by their IDs
  Future<List<ChatUser>> getUsersByIds(List<String> userIds) async {
    if (userIds.isEmpty) return [];
    
    try {
      final userDocs = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: userIds)
          .get();
      
      return userDocs.docs.map((doc) {
        final data = doc.data();
        return ChatUser(
          id: doc.id,
          email: data['email'] ?? '',
          displayName: data['displayName'] ?? '',
          photoUrl: data['photoUrl'],
          bio: data['bio'] ?? '',
          status: data['status'] ?? '',
          lastSeen: data['lastSeen'] != null 
              ? DateTime.parse(data['lastSeen']) 
              : DateTime.now(),
          isOnline: data['isOnline'] ?? false,
        );
      }).toList();
    } catch (e) {
      print('Error getting users by IDs: $e');
      return [];
    }
  }

  // Group management
  Future<String> createGroup(String name, String description, List<String> memberIds) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final groupData = {
      'name': name,
      'description': description,
      'createdBy': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'memberIds': [user.uid, ...memberIds],
      'memberCount': memberIds.length + 1,
    };

    final docRef = await _firestore.collection('groups').add(groupData);
    return docRef.id;
  }

  Future<String> createGroupChat({
    required String name,
    required String description,
    required List<String> memberIds,
  }) async {
    return await createGroup(name, description, memberIds);
  }

  Stream<List<Map<String, dynamic>>> getGroups() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('groups')
        .where('memberIds', arrayContains: user.uid)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Profile and presence management
  Future<void> updateUserProfile({
    String? displayName,
    String? bio,
    String? status,
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final updateData = <String, dynamic>{
      'email': user.email,
      'lastSeen': DateTime.now().toIso8601String(),
      'isOnline': true,
    };

    if (displayName != null) updateData['displayName'] = displayName;
    if (bio != null) updateData['bio'] = bio;
    if (status != null) updateData['status'] = status;
    if (photoUrl != null) updateData['photoUrl'] = photoUrl;

    await _firestore.collection('users').doc(user.uid).set(updateData, SetOptions(merge: true));
  }

  Future<void> updateLastSeen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'lastSeen': DateTime.now().toIso8601String(),
        'isOnline': true,
        'email': user.email,
        'displayName': user.displayName ?? '',
        'photoUrl': user.photoURL,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error updating last seen: $e');
    }
  }

  Future<void> setUserOffline() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore.collection('users').doc(user.uid).update({
      'lastSeen': DateTime.now().toIso8601String(),
      'isOnline': false,
    });
  }

  Future<void> updateUserOnlineStatus(bool isOnline) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _firestore.collection('users').doc(user.uid).update({
        'isOnline': isOnline,
        'lastSeen': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Error updating online status: $e');
    }
  }

  Future<String> uploadProfileImage(File imageFile) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('No authenticated user');

    final imageId = _uuid.v4();
    final ref = _storage.ref().child('profile_images').child('${user.uid}_$imageId.jpg');
    
    final uploadTask = ref.putFile(imageFile);
    final snapshot = await uploadTask;
    final downloadUrl = await snapshot.ref.getDownloadURL();
    
    await updateUserProfile(photoUrl: downloadUrl);
    return downloadUrl;
  }

  void startPresenceUpdates() {
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      updateLastSeen();
    });
  }

  void stopPresenceUpdates() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
  }

  String formatLastSeen(dynamic lastSeenInput, [bool? isOnline]) {
    // Handle online status first
    if (isOnline == true) {
      return 'Online';
    }
    
    String lastSeenString;
    if (lastSeenInput is DateTime) {
      lastSeenString = lastSeenInput.toIso8601String();
    } else if (lastSeenInput is String) {
      lastSeenString = lastSeenInput;
    } else {
      return 'Unknown';
    }
    
    if (lastSeenString.isEmpty) return 'Unknown';
    
    try {
      final lastSeen = DateTime.parse(lastSeenString);
      final now = DateTime.now();
      final difference = now.difference(lastSeen);

      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }

  // Search messages within a chat
  Stream<List<Message>> searchMessagesInChat(String query, {String? recipientId, String? groupId}) {
    if (query.trim().isEmpty) {
      return getMessagesStream(recipientId: recipientId, groupId: groupId);
    }

    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    
    // Create a search-specific controller
    final searchCacheKey = '${cacheKey}_search_${query.toLowerCase()}';
    
    if (!_messageControllers.containsKey(searchCacheKey)) {
      _messageControllers[searchCacheKey] = StreamController<List<Message>>.broadcast();
      
      // Search through cached messages first
      if (_messageCache.containsKey(cacheKey)) {
        final filteredMessages = _messageCache[cacheKey]!
            .where((message) => 
                message.content.toLowerCase().contains(query.toLowerCase()))
            .toList();
        _messageControllers[searchCacheKey]!.add(filteredMessages);
      }
      
      // Then search from Firestore
      _searchInFirestore(query, searchCacheKey, recipientId: recipientId, groupId: groupId);
    }
    
    return _messageControllers[searchCacheKey]!.stream;
  }

  Future<void> _searchInFirestore(String query, String searchCacheKey, {String? recipientId, String? groupId}) async {
    try {
      Query baseQuery = _buildMessageQuery(recipientId: recipientId, groupId: groupId);
      
      // Firestore doesn't support case-insensitive text search natively
      // So we'll fetch all messages and filter client-side for now
      final snapshot = await baseQuery
          .orderBy('timestamp', descending: true)
          .limit(500) // Limit to recent messages for performance
          .get();
      
      final filteredMessages = snapshot.docs
          .map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return Message.fromMap(data, doc.id);
          })
          .where((message) => 
              message.content.toLowerCase().contains(query.toLowerCase()))
          .toList();
      
      // Sort by timestamp (newest first for search results)
      filteredMessages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      
      if (_messageControllers.containsKey(searchCacheKey)) {
        _messageControllers[searchCacheKey]!.add(filteredMessages);
      }
    } catch (e) {
      print('Error searching messages: $e');
    }
  }
  // Special method for private chat to get messages using unified structure
  Future<List<Message>> _getPrivateChatMessages(String recipientId, {DocumentSnapshot? startAfter, int limit = 50}) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      print('    🔍 Getting private chat messages using unified structure');
      final chatRoomId = _getChatRoomId(user.uid, recipientId);
      print('    📱 ChatRoomId: $chatRoomId');
      
      // Use the unified query structure
      Query query = _firestore
          .collection('messages')
          .where('chatType', isEqualTo: 'private')
          .where('chatRoomId', isEqualTo: chatRoomId);

      if (startAfter != null) {
        query = query.orderBy('timestamp', descending: true).startAfterDocument(startAfter).limit(limit);
      } else {
        query = query.orderBy('timestamp', descending: true).limit(limit);
      }

      final snapshot = await query.get();
      print('    📥 Got ${snapshot.docs.length} private messages from Firestore');

      final messages = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Message.fromMap(data, doc.id);
      }).toList();

      return messages;
    } catch (e) {
      print('❌ Error getting private chat messages: $e');
      return [];
    }
  }

  // Migration method to add chatType to existing general messages
  Future<void> migrateGeneralMessages() async {
    try {
      print('🔄 Starting migration of general messages...');
      
      // Find messages where both groupId and recipientId are empty strings
      final snapshot = await _firestore
          .collection('messages')
          .where('groupId', isEqualTo: '')
          .where('recipientId', isEqualTo: '')
          .get();
      
      print('📋 Found ${snapshot.docs.length} messages to migrate');
      
      // Update each message to add chatType field
      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'chatType': 'general'});
      }
      
      await batch.commit();
      print('✅ Migration completed successfully!');
    } catch (e) {
      print('❌ Migration failed: $e');
    }
  }

  // Upload progress tracking
  Stream<double> getUploadProgressStream(String uploadId) {
    if (!_uploadProgressControllers.containsKey(uploadId)) {
      _uploadProgressControllers[uploadId] = StreamController<double>.broadcast();
    }
    return _uploadProgressControllers[uploadId]!.stream;
  }

  void _updateUploadProgress(String uploadId, double progress) {
    if (_uploadProgressControllers.containsKey(uploadId)) {
      _uploadProgressControllers[uploadId]!.add(progress);
    }
  }

  void _completeUpload(String uploadId) {
    _activeUploads.remove(uploadId);
    _uploadProgressControllers[uploadId]?.close();
    _uploadProgressControllers.remove(uploadId);
  }

  Future<void> cancelUpload(String uploadId) async {
    final uploadTask = _activeUploads[uploadId];
    if (uploadTask != null) {
      await uploadTask.cancel();
      _completeUpload(uploadId);
    }
  }

  // Upload file with progress tracking
  Future<String> uploadFileWithProgress(
    File file, 
    String fileName, {
    String? recipientId,
    String? groupId,
    required Function(String uploadId) onUploadStarted,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    final uploadId = _uuid.v4();
    final storageRef = _storage.ref().child('chat_files/${user.uid}/$uploadId/$fileName');
    
    try {
      // Start upload task
      final uploadTask = storageRef.putFile(file);
      _activeUploads[uploadId] = uploadTask;
      
      // Create progress controller
      _uploadProgressControllers[uploadId] = StreamController<double>.broadcast();
      
      // Notify about upload start
      onUploadStarted(uploadId);
      
      // Listen to upload progress
      uploadTask.snapshotEvents.listen(
        (snapshot) {
          final progress = snapshot.bytesTransferred / snapshot.totalBytes;
          _updateUploadProgress(uploadId, progress);
        },
        onError: (error) {
          _uploadProgressControllers[uploadId]?.addError(error);
          _completeUpload(uploadId);
        },
      );
      
      // Wait for upload to complete
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      _completeUpload(uploadId);
      return downloadUrl;
      
    } catch (e) {
      _completeUpload(uploadId);
      rethrow;
    }
  }

  // Call log methods
  Future<void> addCallLog(CallLog callLog) async {
    try {
      await _firestore
          .collection('call_logs')
          .doc(callLog.id)
          .set(callLog.toMap());
    } catch (e) {
      print('Error adding call log: $e');
      rethrow;
    }
  }

  Stream<List<CallLog>> getCallLogsStream({String? recipientId, String? groupId}) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    Query query = _firestore
        .collection('call_logs')
        .where('userId', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(50);

    if (recipientId != null) {
      query = query.where('participantId', isEqualTo: recipientId);
    } else if (groupId != null) {
      query = query.where('groupId', isEqualTo: groupId);
    }

    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => CallLog.fromMap(doc.data() as Map<String, dynamic>, doc.id)).toList());
  }

  Future<List<CallLog>> getRecentCallLogs({int limit = 10}) async {
    final user = _auth.currentUser;
    if (user == null) return [];

    try {
      final querySnapshot = await _firestore
          .collection('call_logs')
          .where('userId', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();

      return querySnapshot.docs
          .map((doc) => CallLog.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error getting recent call logs: $e');
      return [];
    }
  }

  // Add call log to chat as a chat item
  Future<void> addCallLogToChat(String chatId, CallLog callLog) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      // Create a call log message
      final callLogData = {
        'id': callLog.id,
        'callId': callLog.callId,
        'type': callLog.type.toString().split('.').last,
        'status': callLog.status.toString().split('.').last,
        'isVideo': callLog.isVideo,
        'participantId': callLog.participantId,
        'participantName': callLog.participantName,
        'participantEmail': callLog.participantEmail,
        'groupId': callLog.groupId,
        'groupName': callLog.groupName,
        'timestamp': Timestamp.fromDate(callLog.timestamp),
        'duration': callLog.duration,
        'userId': callLog.userId,
        'messageType': 'call_log', // Special type to identify call logs
      };

      // Add to the chat's messages collection
      await _firestore
          .collection('chats')
          .doc(chatId)
          .collection('messages')
          .doc(callLog.id)
          .set(callLogData);

      print('Call log added to chat: $chatId');
    } catch (e) {
      print('Error adding call log to chat: $e');
    }
  }
  // Listen to call logs for a chat and integrate them with messages
  Stream<List<ChatItem>> getChatItemsWithCallLogsStream(String chatId) {
    if (_chatItemControllers.containsKey(chatId)) {
      return _chatItemControllers[chatId]!.stream;
    }

    final controller = StreamController<List<ChatItem>>.broadcast();
    _chatItemControllers[chatId] = controller;

    // Listen to both messages and call logs
    _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(_initialLoadCount)
        .snapshots()
        .listen((snapshot) {
      try {
        final chatItems = <ChatItem>[];

        for (var doc in snapshot.docs) {
          final data = doc.data();
          final messageType = data['messageType'] as String?;

          if (messageType == 'call_log') {
            // It's a call log
            final callLog = CallLog(
              id: doc.id,
              callId: data['callId'] ?? '',
              type: CallLogType.values.firstWhere(
                (e) => e.toString() == 'CallLogType.${data['type']}',
                orElse: () => CallLogType.incoming,
              ),
              status: CallLogStatus.values.firstWhere(
                (e) => e.toString() == 'CallLogStatus.${data['status']}',
                orElse: () => CallLogStatus.completed,
              ),
              isVideo: data['isVideo'] ?? false,
              participantId: data['participantId'] ?? '',
              participantName: data['participantName'] ?? '',
              participantEmail: data['participantEmail'] ?? '',
              groupId: data['groupId'],
              groupName: data['groupName'],
              timestamp: (data['timestamp'] as Timestamp).toDate(),
              duration: data['duration'],
              userId: data['userId'] ?? '',
            );            chatItems.add(CallLogChatItem(callLog));
          } else {
            // It's a regular message
            final message = Message.fromMap(data, doc.id);
            chatItems.add(MessageChatItem(message));
          }
        }

        // Sort by timestamp (most recent first)
        chatItems.sort((a, b) {
          final aTime = a.isMessage ? a.asMessage.timestamp : a.asCallLog.timestamp;
          final bTime = b.isMessage ? b.asMessage.timestamp : b.asCallLog.timestamp;
          return bTime.compareTo(aTime);
        });

        controller.add(chatItems);
      } catch (e) {
        print('Error processing chat items: $e');
        controller.addError(e);
      }
    });

    return controller.stream;
  }

  // Cleanup
  void dispose() {
    _presenceTimer?.cancel();
    for (final subscription in _activeStreams.values) {
      subscription?.cancel();
    }
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    for (final controller in _uploadProgressControllers.values) {
      controller.close();
    }
    _activeStreams.clear();
    _messageControllers.clear();
    _uploadProgressControllers.clear();
    _activeUploads.clear();
    _messageCache.clear();
    _lastDocuments.clear();
    _hasMoreMessages.clear();
    _isLoadingMore.clear();
  }
  // Cache helper methods
  String _getCacheKey({String? recipientId, String? groupId}) {
    if (groupId != null) {
      return 'group_$groupId';
    } else if (recipientId != null) {
      final currentUserId = _auth.currentUser?.uid ?? '';
      return 'private_${_getChatRoomId(currentUserId, recipientId)}';
    } else {
      return 'general';
    }
  }

  void _addMessageToCache(String cacheKey, Message message, {bool notify = true}) {
    if (!_messageCache.containsKey(cacheKey)) {
      _messageCache[cacheKey] = [];
    }
    
    // Insert message in chronological order (newest at end)
    final messages = _messageCache[cacheKey]!;
    int insertIndex = messages.length;
    
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].timestamp.isBefore(message.timestamp)) {
        insertIndex = i + 1;
        break;
      } else if (messages[i].timestamp.isAtSameMomentAs(message.timestamp)) {
        // Replace if same timestamp (for optimistic updates)
        if (messages[i].id == message.id || messages[i].id.startsWith('temp_')) {
          messages[i] = message;
          if (notify) _notifyMessageListeners(cacheKey);
          return;
        }
      }
    }
    
    messages.insert(insertIndex, message);
    if (notify) _notifyMessageListeners(cacheKey);
  }

  void _updateOptimisticMessage(String cacheKey, String tempId, String realId) {
    final messages = _messageCache[cacheKey];
    if (messages != null) {
      for (int i = 0; i < messages.length; i++) {        if (messages[i].id == tempId) {
          messages[i] = Message(
            id: realId,
            senderId: messages[i].senderId,
            senderName: messages[i].senderName,
            senderEmail: messages[i].senderEmail,
            content: messages[i].content,
            timestamp: messages[i].timestamp,
            type: messages[i].type,
            imageUrl: messages[i].imageUrl,
            videoUrl: messages[i].videoUrl,
            thumbnailUrl: messages[i].thumbnailUrl,
            videoDuration: messages[i].videoDuration,
            senderPhotoUrl: messages[i].senderPhotoUrl,
            recipientId: messages[i].recipientId,
            groupId: messages[i].groupId,
            isEdited: messages[i].isEdited,
            editedAt: messages[i].editedAt,
            isSystemMessage: messages[i].isSystemMessage,
            isOptimistic: false, // Update to false since it's now confirmed
            status: messages[i].status,
          );
          _notifyMessageListeners(cacheKey);
          break;
        }
      }
    }
  }

  void _removeMessageFromCache(String cacheKey, String messageId) {
    final messages = _messageCache[cacheKey];
    if (messages != null) {
      messages.removeWhere((msg) => msg.id == messageId);
      _notifyMessageListeners(cacheKey);
    }
  }

  void _notifyMessageListeners(String cacheKey) {
    final controller = _messageControllers[cacheKey];
    final messages = _messageCache[cacheKey];
    if (controller != null && messages != null) {
      controller.add(List.from(messages.reversed));
    }
  }

  void clearChatCache({String? recipientId, String? groupId}) {
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    
    // Cancel existing stream subscription
    _activeStreams[cacheKey]?.cancel();
    _activeStreams.remove(cacheKey);
    
    // Close and remove controller
    _messageControllers[cacheKey]?.close();
    _messageControllers.remove(cacheKey);
    
    // Clear cache data
    _messageCache.remove(cacheKey);
    _lastDocuments.remove(cacheKey);
    _hasMoreMessages.remove(cacheKey);
    _isLoadingMore.remove(cacheKey);
  }

  // Force refresh of a chat (clears cache and reloads)
  void refreshChat({String? recipientId, String? groupId}) {
    clearChatCache(recipientId: recipientId, groupId: groupId);
    // The next call to getMessagesStream will recreate everything
  }

  String _getChatRoomId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort();
    return ids.join('_');
  }
  // Get combined chat items stream (messages + call logs)
  Stream<List<ChatItem>> getChatItemsStream({String? recipientId, String? groupId}) {
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    
    // Clear existing cache if it exists
    if (_chatItemControllers.containsKey(cacheKey)) {
      _chatItemControllers[cacheKey]?.close();
      _chatItemControllers.remove(cacheKey);
    }
    
    // Create fresh controller
    _chatItemControllers[cacheKey] = StreamController<List<ChatItem>>.broadcast();
      // Combine messages and call logs streams
    final messagesStream = getMessagesStream(recipientId: recipientId, groupId: groupId);
    // TODO: Re-implement call logs integration without circular dependency
    // final callLogsStream = _callService.getCallLogsStream(recipientId: recipientId, groupId: groupId);
    
    // Keep track of latest data from both streams
    List<Message> latestMessages = [];
    List<CallLog> latestCallLogs = [];
    
    void emitCombinedItems() {
      final combinedItems = <ChatItem>[];
      
      // Add messages as chat items
      for (final message in latestMessages) {
        combinedItems.add(MessageChatItem(message));
      }
      
      // Add call logs as chat items
      for (final callLog in latestCallLogs) {
        combinedItems.add(CallLogChatItem(callLog));
      }
      
      // Sort by timestamp (oldest first)
      combinedItems.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      // Emit combined items
      if (_chatItemControllers.containsKey(cacheKey)) {
        _chatItemControllers[cacheKey]!.add(combinedItems);
      }
    }
      // Listen to messages stream
    messagesStream.listen((messages) {
      latestMessages = messages;
      emitCombinedItems();
    });
    
    // TODO: Re-implement call logs stream listener without circular dependency
    // callLogsStream.listen((callLogs) {
    //   latestCallLogs = callLogs;
    //   emitCombinedItems();
    // });
    
    return _chatItemControllers[cacheKey]!.stream;
  }

  // Listen for call log events from CallService
  void _listenForCallLogEvents() {
    EventBus().on<CallLogCreatedEvent>().listen((event) {
      _addCallLogToChat(event);
    });
  }

  // Add call log to chat as a message
  Future<void> _addCallLogToChat(CallLogCreatedEvent event) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      String? chatId;
      
      if (event.isGroupCall && event.groupId != null) {
        // Group call - use group ID as chat ID
        chatId = event.groupId;
      } else if (event.recipientId.isNotEmpty) {
        // 1-on-1 call - generate chat ID from user IDs
        final List<String> userIds = [user.uid, event.recipientId];
        userIds.sort(); // Ensure consistent chat ID regardless of who calls
        chatId = userIds.join('_');
      }      if (chatId != null) {
        // Create a call log message
        final callLogMessage = Message(
          id: _uuid.v4(),
          senderId: user.uid,
          senderEmail: user.email ?? '',
          senderName: user.displayName ?? user.email?.split('@')[0] ?? 'Unknown',
          content: '',
          timestamp: DateTime.now(),
          type: MessageType.callLog,
          callLog: event.callLog,
        );
        
        // Add message to chat by directly saving to Firestore
        final chatCollection = event.isGroupCall 
            ? _firestore.collection('group_chats').doc(chatId).collection('messages')
            : _firestore.collection('chats').doc(chatId).collection('messages');
            
        await chatCollection.doc(callLogMessage.id).set(callLogMessage.toMap());
        
        print('📞 Call log added to chat: $chatId');
      }
    } catch (e) {
      print('❌ Error adding call log to chat: $e');
    }
  }
}
