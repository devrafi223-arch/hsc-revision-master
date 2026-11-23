import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/app_user.dart';
import 'admin_service.dart';
import 'firebase_init.dart';
import 'user_repository.dart';

/// Email + password + Google sign-in, backed by Firebase Auth.
///
/// Every method throws
/// `Exception('Online features need Firebase setup — replace
/// lib/firebase_options.dart with your real project config.')`
/// while [FirebaseInit.isOnlineMode] is false. There is no OTP system:
/// registration is email + password only (plus Google Sign-In).
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
