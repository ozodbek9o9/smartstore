import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/tenant_firestore.dart';

class AuthResult {
  const AuthResult({required this.user, required this.created});

  final User user;
  final bool created;
}

/// Firebase Authentication adapter for the existing username/password UI.
///
/// The UI intentionally remains username based. A validated username is
/// converted into an internal, non-displayed Firebase email address so that
/// Firebase Email/Password Auth can provide a secure UID for every tenant.
class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;

  static String emailForUsername(String username) {
    final normalized = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{3,}$').hasMatch(normalized)) {
      throw ArgumentError.value(username, 'username', 'Invalid username');
    }
    return '$normalized@smartstore.local';
  }

  /// Creates a Firebase account or signs in to an existing one. This keeps the
  /// current two-step username/password screen unchanged.
  Future<AuthResult> registerOrSignIn({
    required String username,
    required String fullName,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    final email = emailForUsername(normalizedUsername);

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw StateError('Firebase Authentication did not return a user.');
      }

      try {
        await TenantFirestore.userDocument.set({
          'uid': user.uid,
          'username': normalizedUsername,
          'usernameLower': normalizedUsername.toLowerCase(),
          'fullName': fullName.trim(),
          'password': password,
          'createdAt': FieldValue.serverTimestamp(),
          'lastLogin': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Do not leave a partially provisioned account if its tenant profile
        // cannot be created.
        await user.delete();
        await _auth.signOut();
        rethrow;
      }

      return AuthResult(user: user, created: true);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') rethrow;

      try {
        final credential = await _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        final user = credential.user;
        if (user == null) {
          throw StateError('Firebase Authentication did not return a user.');
        }

        await TenantFirestore.userDocument.set({
          'uid': user.uid,
          'username': normalizedUsername,
          'usernameLower': normalizedUsername.toLowerCase(),
          'fullName': fullName.trim(),
          'password': password,
          'lastLogin': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        return AuthResult(user: user, created: false);
      } on FirebaseAuthException catch (signInError) {
        if (signInError.code == 'wrong-password' ||
            signInError.code == 'invalid-credential' ||
            signInError.code == 'user-not-found') {
          rethrow;
        }

        throw FirebaseAuthException(
          code: 'account-exists',
          message:
              'This account already exists in Firebase Auth. Please use the correct password or reset it.',
        );
      }
    }
  }

  Future<void> updateProfile({
    required String currentUsername,
    required String username,
    required String fullName,
    String? currentPassword,
    String? newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw const UnauthenticatedUserException();

    final normalizedCurrent = currentUsername.trim();
    final normalizedUsername = username.trim();
    final usernameChanged =
        normalizedCurrent.toLowerCase() != normalizedUsername.toLowerCase();
    final passwordChanged = newPassword != null && newPassword.isNotEmpty;

    if ((usernameChanged || passwordChanged) &&
        (currentPassword == null || currentPassword.isEmpty)) {
      throw const RecentAuthenticationRequiredException();
    }

    if (usernameChanged || passwordChanged) {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email ?? emailForUsername(normalizedCurrent),
          password: currentPassword!,
        ),
      );
    }

    if (usernameChanged) {
      await user.verifyBeforeUpdateEmail(emailForUsername(normalizedUsername));
    }
    if (passwordChanged) {
      await user.updatePassword(newPassword);
    }

    await TenantFirestore.userDocument.set({
      'uid': user.uid,
      'username': normalizedUsername,
      'usernameLower': normalizedUsername.toLowerCase(),
      'fullName': fullName.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> signOut() => _auth.signOut();
}

class RecentAuthenticationRequiredException implements Exception {
  const RecentAuthenticationRequiredException();
}
