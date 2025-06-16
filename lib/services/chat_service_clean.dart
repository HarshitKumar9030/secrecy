import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import '../models/message.dart';
import '../models/user.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();
  
  // Cache for messages and streams
  final Map<String, List<Message>> _messageCache = {};
  final Map<String, StreamController<List<Message>>> _messageControllers = {};
  final Map<String, StreamSubscription?> _activeStreams = {};
  final Map<String, DocumentSnapshot?> _lastDocuments = {};
  final Map<String, bool> _hasMoreMessages = {};
  final Map<String, bool> _isLoadingMore = {};
  
  // Settings
  static const int _messagesPerPage = 20;
  static const int _initialLoadCount = 50;
  
  Timer? _presenceTimer;

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
    _addMessageToCache(cacheKey, message);

    try {
      // Send to server
      final messageData = message.toMap();
      messageData.remove('isOptimistic');
      
      DocumentReference docRef;
      if (groupId != null) {
        docRef = await _firestore.collection('messages').add(messageData);
      } else if (recipientId == null) {
        docRef = await _firestore.collection('messages').add(messageData);
      } else {
        final chatRoomId = _getChatRoomId(user.uid, recipientId);
        docRef = await _firestore
            .collection('private_chats')
            .doc(chatRoomId)
            .collection('messages')
            .add(messageData);
      }

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
        groupId: groupId,
        timestamp: DateTime.now(),
      );

      if (groupId != null) {
        await _firestore.collection('messages').add(message.toMap());
      } else if (recipientId == null) {
        await _firestore.collection('messages').add(message.toMap());
      } else {
        final chatRoomId = _getChatRoomId(user.uid, recipientId);
        await _firestore
            .collection('private_chats')
            .doc(chatRoomId)
            .collection('messages')
            .add(message.toMap());
      }
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
        groupId: groupId,
        timestamp: DateTime.now(),
      );

      if (groupId != null) {
        await _firestore.collection('messages').add(message.toMap());
      } else if (recipientId == null) {
        await _firestore.collection('messages').add(message.toMap());
      } else {
        final chatRoomId = _getChatRoomId(user.uid, recipientId);
        await _firestore
            .collection('private_chats')
            .doc(chatRoomId)
            .collection('messages')
            .add(message.toMap());
      }
    } catch (e) {
      print('Error in sendVideo: $e');
      throw Exception('Failed to upload video: $e');
    }
  }

  // Get messages stream (main method)
  Stream<List<Message>> getMessagesStream({String? recipientId, String? groupId}) {
    final cacheKey = _getCacheKey(recipientId: recipientId, groupId: groupId);
    
    // Create controller if doesn't exist
    if (!_messageControllers.containsKey(cacheKey)) {
      _messageControllers[cacheKey] = StreamController<List<Message>>.broadcast();
      _messageCache[cacheKey] = [];
      _hasMoreMessages[cacheKey] = true;
      _isLoadingMore[cacheKey] = false;
      
      // Immediately emit empty list to prevent hanging
      _messageControllers[cacheKey]!.add([]);
      
      // Load initial messages asynchronously
      _loadInitialMessages(cacheKey, recipientId: recipientId, groupId: groupId);
    }
    
    return _messageControllers[cacheKey]!.stream;
  }

  // Get messages (compatibility method)
  Stream<List<Message>> getMessages({String? recipientId, String? groupId}) {
    return getMessagesStream(recipientId: recipientId, groupId: groupId);
  }

  // Send message (compatibility method)
  Future<void> sendMessage(String content, {String? recipientId, String? groupId}) async {
    await sendMessageOptimistic(content, recipientId: recipientId, groupId: groupId);
  }

  // Load initial messages
  Future<void> _loadInitialMessages(String cacheKey, {String? recipientId, String? groupId}) async {
    try {
      Query query = _buildMessageQuery(recipientId: recipientId, groupId: groupId);
      query = query.orderBy('timestamp', descending: true).limit(_initialLoadCount);
      
      final snapshot = await query.get();
      final messages = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Message.fromMap(data, doc.id);
      }).toList();
      
      // Reverse to show oldest first
      messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      
      _messageCache[cacheKey] = messages;
      _lastDocuments[cacheKey] = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      _hasMoreMessages[cacheKey] = snapshot.docs.length == _initialLoadCount;
      
      // Notify listeners with the loaded messages
      if (_messageControllers.containsKey(cacheKey)) {
        _messageControllers[cacheKey]!.add(List.from(messages));
      }
      
      // Set up real-time listener for new messages
      _setupRealtimeListener(cacheKey, recipientId: recipientId, groupId: groupId);
    } catch (e) {
      print('Error loading initial messages: $e');
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
  }

  // Build query for messages
  Query _buildMessageQuery({String? recipientId, String? groupId}) {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User not authenticated');

    if (recipientId == null && groupId == null) {
      // General chat
      return _firestore
          .collection('messages')
          .where('recipientId', isNull: true)
          .where('groupId', isNull: true);
    } else if (groupId != null) {
      // Group chat
      return _firestore
          .collection('messages')
          .where('groupId', isEqualTo: groupId);
    } else {
      // Private chat
      final chatRoomId = _getChatRoomId(user.uid, recipientId!);
      return _firestore
          .collection('private_chats')
          .doc(chatRoomId)
          .collection('messages');
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

  // Helper methods
  String _getCacheKey({String? recipientId, String? groupId}) {
    if (groupId != null) return 'group_$groupId';
    if (recipientId != null) return 'private_$recipientId';
    return 'general';
  }

  String _getChatRoomId(String userId1, String userId2) {
    List<String> ids = [userId1, userId2];
    ids.sort();
    return ids.join('_');
  }

  void _addMessageToCache(String cacheKey, Message message, {bool notify = true}) {
    if (!_messageCache.containsKey(cacheKey)) {
      _messageCache[cacheKey] = [];
    }
    
    _messageCache[cacheKey]!.add(message);
    
    if (notify && _messageControllers.containsKey(cacheKey)) {
      _messageControllers[cacheKey]!.add(List.from(_messageCache[cacheKey]!));
    }
  }

  void _updateOptimisticMessage(String cacheKey, String tempId, String realId) {
    if (!_messageCache.containsKey(cacheKey)) return;
    
    final messages = _messageCache[cacheKey]!;
    final index = messages.indexWhere((m) => m.id == tempId);
    if (index != -1) {
      final oldMessage = messages[index];
      final updatedMessage = Message(
        id: realId,
        content: oldMessage.content,
        type: oldMessage.type,
        imageUrl: oldMessage.imageUrl,
        videoUrl: oldMessage.videoUrl,
        thumbnailUrl: oldMessage.thumbnailUrl,
        videoDuration: oldMessage.videoDuration,
        senderId: oldMessage.senderId,
        senderEmail: oldMessage.senderEmail,
        senderName: oldMessage.senderName,
        senderPhotoUrl: oldMessage.senderPhotoUrl,
        recipientId: oldMessage.recipientId,
        groupId: oldMessage.groupId,
        timestamp: oldMessage.timestamp,
        isOptimistic: false,
      );
      
      messages[index] = updatedMessage;
      
      if (_messageControllers.containsKey(cacheKey)) {
        _messageControllers[cacheKey]!.add(List.from(messages));
      }
    }
  }

  void _removeMessageFromCache(String cacheKey, String messageId) {
    if (!_messageCache.containsKey(cacheKey)) return;
    
    _messageCache[cacheKey]!.removeWhere((m) => m.id == messageId);
    
    if (_messageControllers.containsKey(cacheKey)) {
      _messageControllers[cacheKey]!.add(List.from(_messageCache[cacheKey]!));
    }
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
    _activeStreams.clear();
    _messageControllers.clear();
    _messageCache.clear();
    _lastDocuments.clear();
    _hasMoreMessages.clear();
    _isLoadingMore.clear();
  }
}
