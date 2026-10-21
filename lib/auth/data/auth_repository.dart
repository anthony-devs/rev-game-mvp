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
    if (kIsWeb) {
      // Browsers use Firebase's own pop-up. The google_sign_in plugin is for phones.
      try {
        await _auth.signInWithPopup(GoogleAuthProvider());
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request' || e.code == 'web-context-canceled') throw const AuthFailure.cancelled();
        if (e.code == 'popup-blocked') throw const AuthFailure('Your browser blocked the sign-in window. Allow pop-ups for this site and try again.');
        throw AuthFailure.fromCode(e.code);
      }
      return;
    }
    // Without the iOS client id from Firebase, the Google sign-in library closes the whole app.
    if (defaultTargetPlatform == TargetPlatform.iOS && DefaultFirebaseOptions.ios.iosClientId == null) {
      throw const AuthFailure('Google sign-in is not available right now. Use email, phone or Apple instead.');
    }
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

  // ---- Apple --------------------------------------------------------------

  /// Sign in with Apple (iPhone and iPad). Needs the Apple provider switched on in Firebase and the
  /// Sign in with Apple capability on the app.
  Future<void> signInWithApple() async {
    try {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      await _auth.signInWithProvider(provider);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled' || e.code == 'web-context-cancelled') throw const AuthFailure.cancelled();
      throw AuthFailure.fromCode(e.code);
    }
  }

  /// Apple requires the Sign in with Apple link to be cut when an account is deleted.
  /// Asks Apple once more, then revokes the token. Does nothing for other sign-in types.
  /// Throws [AuthFailure.cancelled] when the player closes the Apple sheet.
  Future<void> revokeAppleAccess() async {
    final user = _auth.currentUser;
    if (user == null || !user.providerData.any((p) => p.providerId == 'apple.com')) return;
    try {
      final result = await user.reauthenticateWithProvider(AppleAuthProvider());
      final code = result.additionalUserInfo?.authorizationCode;
      if (code != null && code.isNotEmpty) await _auth.revokeTokenWithAuthorizationCode(code);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'canceled' || e.code == 'web-context-canceled' || e.code == 'web-context-cancelled') throw const AuthFailure.cancelled();
      rethrow;
    }
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
  Future<String?> idToken({bool force = false}) async => _auth.currentUser?.getIdToken(force);

  // ---- Session ------------------------------------------------------------

  Future<void> signOut() async {
    // Firebase first: this is what actually signs the player out. The Google plugin can hang on the web,
    // so it comes after, with a time limit, and can never hold sign out up.
    await _auth.signOut();
    try {
      await _google.signOut().timeout(const Duration(seconds: 2));
    } catch (_) {}
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
