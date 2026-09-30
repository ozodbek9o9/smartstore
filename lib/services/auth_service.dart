import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../utils/tenant_firestore.dart';

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
    if (!RegExp(r'^[a-zA-Z0-9_]{3,}$').hasMatch(normalizedUsername)) {
      throw const InvalidUsernameException();
    }
    final usernameChanged =
        normalizedCurrent.toLowerCase() != normalizedUsername.toLowerCase();
    final passwordChanged = newPassword != null && newPassword.isNotEmpty;
    final currentUsernameRef = TenantFirestore.usernameDocument(
      normalizedCurrent,
    );
    final newUsernameRef = TenantFirestore.usernameDocument(normalizedUsername);

    if ((usernameChanged || passwordChanged) &&
        (currentPassword == null || currentPassword.isEmpty)) {
      throw const RecentAuthenticationRequiredException();
    }

    var reservedNewUsername = false;
    if (usernameChanged || passwordChanged) {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(
          email: user.email ?? emailForUsername(normalizedCurrent),
          password: currentPassword!,
        ),
      );
    }

    try {
      if (usernameChanged) {
        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final existing = await transaction.get(newUsernameRef);
          final existingUid = existing.data()?['uid'];
          if (existing.exists && existingUid != user.uid) {
            throw const UsernameAlreadyTakenException();
          }
          if (!existing.exists) reservedNewUsername = true;
          transaction.set(newUsernameRef, {
            'uid': user.uid,
            'authEmail': user.email ?? emailForUsername(normalizedCurrent),
            'username': normalizedUsername,
            'usernameLower': normalizedUsername.toLowerCase(),
          }, SetOptions(merge: true));
        });
      }
      if (passwordChanged) await user.updatePassword(newPassword);

      await TenantFirestore.userDocument.set({
        'uid': user.uid,
        'username': normalizedUsername,
        'usernameLower': normalizedUsername.toLowerCase(),
        'fullName': fullName.trim(),
        'password': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (usernameChanged) await currentUsernameRef.delete();
    } catch (_) {
      if (reservedNewUsername) {
        try {
          await newUsernameRef.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> signOut() => _auth.signOut();
}

class RecentAuthenticationRequiredException implements Exception {
  const RecentAuthenticationRequiredException();
}

class UsernameAlreadyTakenException implements Exception {
  const UsernameAlreadyTakenException();
}

class InvalidUsernameException implements Exception {
  const InvalidUsernameException();
}
