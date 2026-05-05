import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:ksrtc_smarttrack/core/constants/app_constants.dart';
import 'package:ksrtc_smarttrack/data/models/user_model.dart';

/// Handles all authentication and user-profile operations.
class AuthRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Auth state ─────────────────────────────────────────────────────────

  /// Stream of auth-state changes (login / logout).
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Currently signed-in Firebase user, or `null`.
  User? get currentUser => _auth.currentUser;

  // ── Sign up ────────────────────────────────────────────────────────────

  /// Creates a new account and writes the user profile to Firestore.
  Future<UserModel> signUp({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user!;
    final userModel = UserModel(
      uid: user.uid,
      email: email.trim(),
      displayName: displayName.trim(),
      role: role,
      createdAt: DateTime.now(),
    );

    await _firestore
        .collection(AppConstants.usersCollection)
        .doc(user.uid)
        .set(userModel.toMap());

    return userModel;
  }

  // ── Sign in ────────────────────────────────────────────────────────────

  /// Signs in with email + password and returns the user profile.
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    return getUserProfile(credential.user!.uid);
  }

  // ── Sign out ───────────────────────────────────────────────────────────

  Future<void> signOut() => _auth.signOut();

  // ── Profile helpers ────────────────────────────────────────────────────

  /// Fetches the Firestore user profile for the given [uid].
  Future<UserModel> getUserProfile(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();

    if (!doc.exists) {
      throw 'User profile not found. Please sign up first.';
    }
    return UserModel.fromFirestore(doc);
  }
}
