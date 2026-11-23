// ===========================================================================
//  REAL FIREBASE CONFIG — project massenger-b9169
// ===========================================================================
//  Values below come from android/app/google-services.json (Rafi's existing
//  Firebase project "massenger-b9169", Android app com.rafi.hscrevise).
//  Android is fully wired. WEB is NOT: the project has no Web app yet, so
//  the web appId is the literal string 'TODO-WEB-APP-ID' and
//  FirebaseInit.initialize() keeps web in LOCAL-ONLY mode (never crashes)
//  until Rafi adds a Web app in the Firebase console and pastes its appId
//  here. Do NOT reuse the Android appId for web.
// ===========================================================================

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// Firebase options for project massenger-b9169.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        // No native Firebase app registered for desktop; fall back to the
        // Android options — init will fail gracefully into local-only mode.
        return android;
    }
  }

  /// Android app com.rafi.hscrevise (from google-services.json).
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAq0t3Rh0cFLdzC5IYY3Lb52YSGu9DbDvs',
    appId: '1:863796919453:android:ebbe3fda969eb4fd2e6874',
    messagingSenderId: '863796919453',
    projectId: 'massenger-b9169',
    storageBucket: 'massenger-b9169.appspot.com',
  );

  /// Web options. appId is a TODO until a Web app is added in the console.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAq0t3Rh0cFLdzC5IYY3Lb52YSGu9DbDvs',
    appId: 'TODO-WEB-APP-ID',
    messagingSenderId: '863796919453',
    projectId: 'massenger-b9169',
    authDomain: 'massenger-b9169.firebaseapp.com',
    storageBucket: 'massenger-b9169.appspot.com',
  );
}
