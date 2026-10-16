import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../firebase_options.dart';
import '../../model/model.dart';
import 'auth_failure.dart';

/// What happened after asking Firebase to text a code.
class PhoneCodeResult {
  const PhoneCodeResult.sent(this.verificationId, this.resendToken) : signedIn = false;
  const PhoneCodeResult.signedIn()
      : verificationId = null,
        resendToken = null,
        signedIn = true;

  final String? verificationId;
  final int? resendToken;

  /// Android read the SMS itself and signed the player in.
  final bool signedIn;
}

/// The only class that talks to Firebase Auth and Google sign in.
/// BLoCs depend on this, never on Firebase directly.
class AuthRepository {
  AuthRepository({FirebaseAuth? auth, GoogleSignIn? google})
      : _auth = auth ?? FirebaseAuth.instance,
        _google = google ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  Future<void>? _googleReady;

  /// Emits [AppUser.empty] when signed out.
  Stream<AppUser> get user => _auth.authStateChanges().map(_toUser);

  /// Synchronous, available as soon as Firebase is initialised.
  AppUser get currentUser => _toUser(_auth.currentUser);

  // ---- Email / password ---------------------------------------------------

  Future<void> signInWithEmail({required String email, required String password}) {
    return _guard(() => _auth.signInWithEmailAndPassword(email: email.trim(), password: password));
  }

  Future<void> signUpWithEmail({required String name, required String email, required String password}) {
    return _guard(() async {
      final cred = await _auth.createUserWithEmailAndPassword(email: email.trim(), password: password);
      await cred.user?.updateDisplayName(name.trim());
    });
  }

  Future<void> sendPasswordReset(String email) {
    return _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));
  }

  // ---- Google -------------------------------------------------------------

  Future<void> signInWithGoogle() async {
    try {
      await (_googleReady ??= _initGoogle());
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) throw const AuthFailure('Google did not return a sign-in token.');
      await _guard(() => _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) throw const AuthFailure.cancelled();
      throw const AuthFailure('Google sign-in is not available right now. Try again or use email.');
    }
  }

  Future<void> _initGoogle() {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    return _google.initialize(clientId: isIos ? DefaultFirebaseOptions.ios.iosClientId : null);
  }

  // ---- Guest --------------------------------------------------------------

  Future<void> signInAsGuest() => _guard(() => _auth.signInAnonymously());

  // ---- Phone --------------------------------------------------------------

  /// Asks Firebase to text a code. Completes when the code was sent (or the
  /// phone was verified automatically). Throws [AuthFailure] on problems.
  Future<PhoneCodeResult> requestPhoneCode(String phoneNumber, {int? resendToken}) {
    final done = Completer<PhoneCodeResult>();

    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: resendToken,
      verificationCompleted: (credential) async {
        try {
          await _auth.signInWithCredential(credential);
          if (!done.isCompleted) done.complete(const PhoneCodeResult.signedIn());
        } on FirebaseAuthException catch (e) {
          if (!done.isCompleted) done.completeError(AuthFailure.fromCode(e.code));
        }
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(AuthFailure.fromCode(e.code));
      },
      codeSent: (id, token) {
        if (!done.isCompleted) done.complete(PhoneCodeResult.sent(id, token));
      },
      codeAutoRetrievalTimeout: (_) {},
    );

    return done.future;
  }

  Future<void> verifySmsCode({required String verificationId, required String code}) {
    final credential = PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim());
    return _guard(() => _auth.signInWithCredential(credential));
  }

  /// Firebase ID token for the game server. Refreshed automatically when it expires.
  Future<String?> idToken() async => _auth.currentUser?.getIdToken();

  // ---- Session ------------------------------------------------------------

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
    await _auth.signOut();
  }

  // ---- helpers ------------------------------------------------------------

  Future<void> _guard(Future<void> Function() run) async {
    try {
      await run();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromCode(e.code);
    }
  }

  AppUser _toUser(User? u) {
    if (u == null) return AppUser.empty;
    final name = u.displayName?.trim();
    final email = u.email;
    final fallback = u.isAnonymous
        ? 'Guest'
        : (email != null && email.contains('@') ? email.split('@').first : 'Player');
    return AppUser(
      id: u.uid,
      displayName: (name != null && name.isNotEmpty) ? name : fallback,
      email: email,
      photoUrl: u.photoURL,
      isAnonymous: u.isAnonymous,
      createdAt: u.metadata.creationTime,
      lastLoginAt: u.metadata.lastSignInTime,
    );
  }
}
