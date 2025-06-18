import 'dart:async';

// Event bus for decoupling services
class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final Map<Type, StreamController> _controllers = {};

  // Get stream for a specific event type
  Stream<T> on<T>() {
    if (!_controllers.containsKey(T)) {
      _controllers[T] = StreamController<T>.broadcast();
    }
    return _controllers[T]!.stream.cast<T>();
  }

  // Emit an event
  void emit<T>(T event) {
    if (_controllers.containsKey(T)) {
      _controllers[T]!.add(event);
    }
  }

  // Dispose all controllers
  void dispose() {
    for (var controller in _controllers.values) {
      controller.close();
    }
    _controllers.clear();
  }
}

// Event classes
class CallLogCreatedEvent {
  final Map<String, dynamic> callLog;
  final String recipientId;
  final bool isGroupCall;
  final String? groupId;

  CallLogCreatedEvent({
    required this.callLog,
    required this.recipientId,
    required this.isGroupCall,
    this.groupId,
  });
}
