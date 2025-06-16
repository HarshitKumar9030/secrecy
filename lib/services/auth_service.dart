import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '881814858440-45jnis6351av32n7sqqh4bmbi4ifcin4.apps.googleusercontent.com',
  );
  User? _user;

  User? get user => _user;
  bool get isAuthenticated => _user != null;

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  // Sign in with email and password
  Future<String?> signInWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'user-not-found':
          return 'No user found with this email address.';
        case 'wrong-password':
          return 'Wrong password provided.';
        case 'invalid-email':
          return 'The email address is not valid.';
        case 'user-disabled':
          return 'This user account has been disabled.';
        default:
          return 'An error occurred. Please try again.';
      }
    } catch (e) {
      return 'An unexpected error occurred.';
    }
  }

  // Register with email and password
  Future<String?> registerWithEmailAndPassword(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'weak-password':
          return 'The password provided is too weak.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'invalid-email':
          return 'The email address is not valid.';
        default:
          return 'An error occurred. Please try again.';
      }
    } catch (e) {
      return 'An unexpected error occurred.';
    }
  }
  // Sign out
  Future<void> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      _user = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('Error signing out: $e');
      }
    }
  }
  // Update display name
  Future<void> updateDisplayName(String displayName) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await currentUser.updateDisplayName(displayName);
        await currentUser.reload();
        _user = _auth.currentUser;
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating display name: $e');
      }
      rethrow; // Re-throw so calling code can handle the error
    }
  }

  // Sign in with Google
  Future<String?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return 'Sign in was cancelled.';
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);
      _user = result.user;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      switch (e.code) {
        case 'account-exists-with-different-credential':
          return 'An account already exists with the same email address but different sign-in credentials.';
        case 'invalid-credential':
          return 'The credential received is malformed or has expired.';
        case 'operation-not-allowed':
          return 'Google sign-in is not enabled for this project.';
        case 'user-disabled':
          return 'The user account has been disabled by an administrator.';
        default:
          return 'An error occurred during Google sign-in. Please try again.';
      }
    } catch (e) {
      return 'An unexpected error occurred during Google sign-in.';
    }
  }
}
