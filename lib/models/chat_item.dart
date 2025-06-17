import 'message.dart';
import 'call_log.dart';

/// Base interface for items that can be displayed in a chat
abstract class ChatItem {
  String get id;
  DateTime get timestamp;
  String get senderId;
  String get senderName;
  String get senderEmail;
  String? get senderPhotoUrl;
  
  /// Returns true if this is a message item
  bool get isMessage;
  
  /// Returns true if this is a call log item
  bool get isCallLog;
  
  /// Cast to Message (only call if isMessage is true)
  Message get asMessage;
  
  /// Cast to CallLog (only call if isCallLog is true)
  CallLog get asCallLog;
}

/// Wrapper for CallLog to implement ChatItem
class CallLogChatItem implements ChatItem {
  final CallLog callLog;
  
  CallLogChatItem(this.callLog);
  
  @override
  String get id => callLog.id;
  
  @override
  DateTime get timestamp => callLog.timestamp;
  
  @override
  String get senderId => callLog.userId;
  
  @override
  String get senderName => callLog.participantName;
  
  @override
  String get senderEmail => callLog.participantEmail;
  
  @override
  String? get senderPhotoUrl => null; // Call logs don't have sender photos
  
  @override
  bool get isMessage => false;
  
  @override
  bool get isCallLog => true;
  
  @override
  CallLog get asCallLog => callLog;
  
  @override
  Message get asMessage => throw StateError('This is not a message');
}

/// Wrapper for Message to implement ChatItem
class MessageChatItem implements ChatItem {
  final Message message;
  
  MessageChatItem(this.message);
  
  @override
  String get id => message.id;
  
  @override
  DateTime get timestamp => message.timestamp;
  
  @override
  String get senderId => message.senderId;
  
  @override
  String get senderName => message.senderName;
  
  @override
  String get senderEmail => message.senderEmail;
  
  @override
  String? get senderPhotoUrl => message.senderPhotoUrl;
  
  @override
  bool get isMessage => true;
  
  @override
  bool get isCallLog => false;
  
  @override
  Message get asMessage => message;
  
  @override
  CallLog get asCallLog => throw StateError('This is not a call log');
}
