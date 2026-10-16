/// A sign-in problem with a message that is safe to show to the player.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.cancelled = false});

  /// The player closed the Google sheet. Not an error, show nothing.
  const AuthFailure.cancelled()
      : message = '',
        cancelled = true;

  final String message;
  final bool cancelled;

  /// Maps a FirebaseAuthException code to a friendly message.
  factory AuthFailure.fromCode(String code) {
    switch (code) {
      case 'invalid-email':
        return const AuthFailure('That email address does not look right.');
      case 'user-disabled':
        return const AuthFailure('This account has been disabled.');
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return const AuthFailure('Wrong email or password.');
      case 'email-already-in-use':
        return const AuthFailure('An account with this email already exists. Try signing in.');
      case 'weak-password':
        return const AuthFailure('Choose a stronger password (at least 6 characters).');
      case 'account-exists-with-different-credential':
        return const AuthFailure('This email is already used with another sign-in method.');
      case 'credential-already-in-use':
        return const AuthFailure('That account is already linked to another player.');
      case 'too-many-requests':
        return const AuthFailure('Too many attempts. Please wait a moment and try again.');
      case 'network-request-failed':
        return const AuthFailure('No connection. Check your internet and try again.');
      case 'operation-not-allowed':
        return const AuthFailure('This sign-in method is not enabled yet.');
      case 'invalid-phone-number':
      case 'missing-phone-number':
        return const AuthFailure('Enter a valid phone number with its country code.');
      case 'invalid-verification-code':
        return const AuthFailure('That code is not correct.');
      case 'invalid-verification-id':
      case 'session-expired':
      case 'code-expired':
        return const AuthFailure('That code has expired. Request a new one.');
      case 'quota-exceeded':
        return const AuthFailure('Too many codes were sent. Try again later.');
      case 'captcha-check-failed':
      case 'missing-client-identifier':
      case 'app-not-authorized':
        return const AuthFailure('Phone verification could not start on this device.');
      default:
        return const AuthFailure('Something went wrong. Please try again.');
    }
  }

  @override
  String toString() => 'AuthFailure($message)';
}
