import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;

import 'firebase_options.dart';

class FirebaseStatus {
  FirebaseStatus._();

  static const _signInTimeout = Duration(seconds: 8);
  static bool _initialized = false;
  static final authRevision = ValueNotifier(0);
  static Future<bool>? _initializationInProgress;
  static Future<bool>? _signInInProgress;

  static bool get isInitialized => _initialized;

  static Future<bool> initialize() {
    if (_initialized) return Future.value(true);
    return _initializationInProgress ??= _initialize().whenComplete(() {
      _initializationInProgress = null;
    });
  }

  static Future<bool> _initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      return true;
    } catch (error) {
      debugPrint('Firebase initialization failed: $error');
      return false;
    }
  }

  static Future<bool> ensureSignedIn() {
    if (!_initialized) return _initializeAndSignIn();
    return _signInInProgress ??= _signIn().whenComplete(() {
      _signInInProgress = null;
    });
  }

  static Future<bool> _initializeAndSignIn() async {
    if (!await initialize()) return false;
    return ensureSignedIn();
  }

  static Future<bool> _signIn() async {
    try {
      final auth = FirebaseAuth.instance;
      if (auth.currentUser != null) return true;
      final credential = await auth.signInAnonymously().timeout(_signInTimeout);
      debugPrint('Anonymous user authenticated: ${credential.user?.uid}');
      if (credential.user == null) return false;
      authRevision.value++;
      return true;
    } catch (error) {
      debugPrint('Anonymous sign-in failed: $error');
      return false;
    }
  }
}
