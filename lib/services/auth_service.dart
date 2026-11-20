import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

/// Account status stored by the web app in `companies/{uid}.status`.
/// A new account is "pending" until an administrator sets it to "active" (the web app stores it in lower case).
/// A missing status counts as active (accounts that existed before approvals). An account with no company
/// record at all (sign-up was not finished) must complete its profile first, like on the website.
enum AccountStatus { active, pending, needsProfile, bidCheck }

AccountStatus accountStatusOf(Map<String, dynamic>? company) {
  if (company == null) return AccountStatus.needsProfile;
  if ('${company['status']}'.toLowerCase() == 'pending') {
    return AccountStatus.pending;
  }
  // An account made with a mobile OTP gets the free Bid Check pages only (email accounts get the whole app).
  return company['signup_method'] == 'mobile_otp'
      ? AccountStatus.bidCheck
      : AccountStatus.active;
}

/// Bumped when something outside the gate (the sign-up wizard) changes the account's status, so the gate
/// reloads it.
final authRefresh = ValueNotifier<int>(0);

class AuthService {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  Stream<User?> get userChanges => _auth.authStateChanges();

  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  /// Creates the Firebase account (and signs it in). The company details are saved separately, by the server.
  Future<User> createAccount(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  /// Signs in with the custom token the server returns after a correct OTP.
  Future<void> signInWithToken(String token) async {
    try {
      await _auth.signInWithCustomToken(token);
    } on FirebaseAuthException catch (e) {
      throw AuthException(
        e.code == 'network-request-failed'
            ? 'Could not reach the server. Check your internet connection.'
            : 'Could not sign you in (${e.code}). Please try again.',
      );
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthException(_message(e));
    }
  }

  Future<void> signOut() => _auth.signOut();

  /// The company profile saved by the web app, or null if none exists yet.
  Future<Map<String, dynamic>?> company(String uid) async {
    final snap = await _db.collection('companies').doc(uid).get();
    return snap.data();
  }

  AccountStatus statusOf(Map<String, dynamic>? company) =>
      accountStatusOf(company);

  String _message(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'That email address is not valid.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Could not reach the server. Check your internet connection.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is switched off in Firebase.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Log in instead.';
      case 'weak-password':
        return 'The password is too weak. Use at least 8 characters.';
      default:
        return 'Sign-in failed (${e.code}).';
    }
  }
}

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}
