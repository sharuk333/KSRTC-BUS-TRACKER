import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ksrtc_smarttrack/data/models/user_model.dart';
import 'package:ksrtc_smarttrack/data/repositories/auth_repository.dart';

// ── Repository singleton ─────────────────────────────────────────────────
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository();
});

// ── Firebase auth-state stream ───────────────────────────────────────────
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges;
});

// ── Current user profile (fetched from Firestore) ────────────────────────
final userProfileProvider = FutureProvider<UserModel?>((ref) async {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (user) async {
      if (user == null) return null;
      return ref.read(authRepositoryProvider).getUserProfile(user.uid);
    },
    loading: () => null,
    error: (_, _) => null,
  );
});
