import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/call_service.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  CallService? _callService;
  bool _hasStartedListening = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // Get the call service instance
        _callService ??= Provider.of<CallService>(context, listen: false);
        
        if (authService.isAuthenticated) {
          // Start listening for incoming calls when user is authenticated
          if (!_hasStartedListening) {
            _hasStartedListening = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _callService?.startListeningForIncomingCalls();
            });
          }
          
          return const ChatScreen();
        } else {
          _hasStartedListening = false;
          return const AuthScreen();
        }
      },
    );
  }
}
