import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import 'admin_service.dart';
import 'firebase_init.dart';
import 'user_repository.dart';

/// Email + OTP + Google sign-in, backed by Firebase Auth.
///
/// Every method throws
/// `Exception('Online features need Firebase setup — replace
/// lib/firebase_options.dart with your real project config.')`
/// while [FirebaseInit.isOnlineMode] is false — EXCEPT the OTP local-demo
/// path (see [sendOtp] / [verifyOtp]).
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const String _onlineError =
      'Online features need Firebase setup — replace '
      'lib/firebase_options.dart with your real project config.';

  /// Emits the signed-in uid, or null when signed out. In local-only mode
  /// emits a single null (there is no account without Firebase).
  Stream<String?> get authStateChanges {
    if (!FirebaseInit.isOnlineMode) return Stream<String?>.value(null);
    return FirebaseAuth.instance
        .authStateChanges()
        .map((user) => user?.uid);
  }

  String? get currentUid => FirebaseInit.isOnlineMode
      ? FirebaseAuth.instance.currentUser?.uid
      : null;

  bool get signedIn => currentUid != null;

  /// False while Firebase is not configured (local-only mode).
  bool get isAvailable => FirebaseInit.isOnlineMode;

  void _requireOnline() {
    if (!FirebaseInit.isOnlineMode) throw Exception(_onlineError);
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String name,
  }) async {
    _requireOnline();
    final credential =
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final user = credential.user;
    if (user == null) throw Exception('Registration failed: no user.');
    await user.updateDisplayName(name);
    // Local admin fallback: the first user ever registered on this device
    // becomes the admin until a real isAdmin flag is set in Firestore.
    try {
      await AdminService.recordFirstUser(user.uid);
    } catch (_) {
      // Best effort only.
    }
    // Best effort: create the profile doc so the community can show it.
    try {
      await UserRepository.instance.saveUser(
        AppUser(id: user.uid, name: name, email: email),
      );
    } catch (_) {
      // Profile doc failure must not fail registration itself.
    }
  }

  Future<void> loginWithEmail({
    required String email,
    required String password,
  }) async {
    _requireOnline();
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Generates a 6-digit OTP, stores its SHA-256 hash + a 10-minute expiry
  /// in Firestore collection `email_otps` (doc id = the email).
  ///
  /// TODO: EMAIL SENDING IS NOT POSSIBLE WITHOUT A BACKEND. Firebase Auth
  /// has no "send a custom OTP email" API, so no email is actually sent by
  /// this method. To send the code for real, Rafi needs a backend (e.g. a
  /// Cloud Function / small server) that reads the pending code and emails
  /// it via SMTP. Until that exists, the LOCAL-ONLY demo path below stores
  /// the plain code in SharedPreferences key `demo-otp-<email>` so the UI
  /// can show it labelled "demo code (no email configured)". In online
  /// mode the code is NOT shown anywhere — only its hash is stored.
  Future<void> sendOtp(String email) async {
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    final hash = sha256.convert(utf8.encode(code)).toString();
    final expiresAt =
        DateTime.now().add(const Duration(minutes: 10)).millisecondsSinceEpoch;

    if (!FirebaseInit.isOnlineMode) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('demo-otp-$email', code);
      await prefs.setString('demo-otp-hash-$email', hash);
      await prefs.setInt('demo-otp-exp-$email', expiresAt);
      return;
    }

    await FirebaseFirestore.instance.collection('email_otps').doc(email).set({
      'hash': hash,
      'expiresAt': expiresAt,
      'createdAt': FieldValue.serverTimestamp(),
    });
    // TODO: a backend must email the code to the user (see doc comment).
  }

  /// Validates an OTP by comparing its SHA-256 hash and checking the
  /// 10-minute expiry. Returns true on success, false otherwise.
  ///
  /// NOTE: this only validates the code — it does NOT create or sign in a
  /// user. On success the UI completes registration by calling
  /// [registerWithEmail] (email + password + name). On success the stored
  /// OTP is deleted (one-time use).
  Future<bool> verifyOtp(String email, String code) async {
    final hash = sha256.convert(utf8.encode(code)).toString();
    final now = DateTime.now().millisecondsSinceEpoch;

    if (!FirebaseInit.isOnlineMode) {
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString('demo-otp-hash-$email');
      final storedExp = prefs.getInt('demo-otp-exp-$email');
      if (storedHash == null || storedExp == null) return false;
      if (now > storedExp) return false;
      if (storedHash != hash) return false;
      await prefs.remove('demo-otp-$email');
      await prefs.remove('demo-otp-hash-$email');
      await prefs.remove('demo-otp-exp-$email');
      return true;
    }

    final doc = await FirebaseFirestore.instance
        .collection('email_otps')
        .doc(email)
        .get();
    final data = doc.data();
    if (data == null) return false;
    final storedHash = data['hash'] as String?;
    final storedExp = (data['expiresAt'] as num?)?.toInt();
    if (storedHash == null || storedExp == null) return false;
    if (now > storedExp) return false;
    if (storedHash != hash) return false;
    // One-time use: delete the OTP after a successful check.
    await doc.reference.delete();
    return true;
  }

  Future<void> signInWithGoogle() async {
    _requireOnline();
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) {
      throw Exception('Google sign-in cancelled.');
    }
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final result =
        await FirebaseAuth.instance.signInWithCredential(credential);
    final user = result.user;
    if (user != null) {
      try {
        final existing =
            await UserRepository.instance.getUser(user.uid);
        if (existing == null) {
          await UserRepository.instance.saveUser(
            AppUser(
              id: user.uid,
              name: user.displayName ?? googleUser.displayName ?? 'Student',
              email: user.email ?? googleUser.email,
              photoUrl: user.photoURL,
            ),
          );
        }
      } catch (_) {
        // Profile doc failure must not fail sign-in itself.
      }
    }
  }

  Future<void> signOut() async {
    if (!FirebaseInit.isOnlineMode) return;
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google sign-out is best effort.
    }
    await FirebaseAuth.instance.signOut();
  }

  Future<void> sendEmailVerification() async {
    _requireOnline();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('No user is signed in.');
    await user.sendEmailVerification();
  }
}
