import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/call_service.dart';
import 'screens/auth_wrapper.dart';
import 'screens/call_screen.dart';
import 'models/call_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    await FirebaseAppCheck.instance.activate(
      webProvider: kDebugMode 
          ? ReCaptchaV3Provider('debug') 
          : ReCaptchaV3Provider('your-recaptcha-site-key'),
      androidProvider: kDebugMode 
          ? AndroidProvider.debug 
          : AndroidProvider.playIntegrity,
    );
  } catch (e) {
    // Firebase may already be initialized, which is fine
    if (!e.toString().contains('duplicate-app')) {
      print('Firebase initialization error: $e');
    }
  }
  
  runApp(const SecrecyApp());
}

class SecrecyApp extends StatelessWidget {
  const SecrecyApp({super.key});  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
        Provider(create: (context) => CallService()),
      ],      child: Consumer<CallService>(
        builder: (context, callService, child) {
          return StreamBuilder<Call?>(
            stream: callService.callStateStream,
            builder: (context, callSnapshot) {
              final call = callSnapshot.data;
              
              return MaterialApp(
                title: 'Secrecy',
                theme: ThemeData(
          fontFamily: 'SF Pro Display',
          primaryColor: const Color(0xFF2F3437),
          scaffoldBackgroundColor: const Color(0xFFF7F6F3),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF2F3437),
            brightness: Brightness.light,
            surface: Colors.white,
            onSurface: const Color(0xFF2F3437),
          ),
          appBarTheme: const AppBarTheme(
            elevation: 0,
            centerTitle: false,
            backgroundColor: Color(0xFF2F3437),
            foregroundColor: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2F3437),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
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
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),          cardTheme: const CardThemeData(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
              side: BorderSide(color: Color(0xFFE1E1E0), width: 1),
            ),
            color: Colors.white,
          ),
          dividerColor: const Color(0xFFE1E1E0),
          textTheme: const TextTheme(
            headlineMedium: TextStyle(
              color: Color(0xFF2F3437),
              fontWeight: FontWeight.w700,            ),
            bodyLarge: TextStyle(
              color: Color(0xFF2F3437),
            ),
            bodyMedium: TextStyle(
              color: Color(0xFF2F3437),            ),
          ),
        ),        home: call != null && (call.state == CallState.ringing || 
                                 call.state == CallState.connecting || 
                                 call.state == CallState.connected)
            ? CallScreen(call: call)
            : const AuthWrapper(),
        debugShowCheckedModeBanner: false,
              );
            },
          );
        },
      ),
    );
  }
}
