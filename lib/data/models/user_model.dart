import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { conductor, passenger }

/// Represents a user stored in the `users` Firestore collection.
class UserModel {
  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.createdAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      role: data['role'] == 'conductor' ? UserRole.conductor : UserRole.passenger,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role == UserRole.conductor ? 'conductor' : 'passenger',
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
