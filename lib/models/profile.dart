import 'package:equatable/equatable.dart';

class Profile extends Equatable {
  final String id;
  final String username;
  final String publicKey;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const Profile({
    required this.id,
    required this.username,
    required this.publicKey,
    required this.createdAt,
    this.lastLoginAt,
  });

  Profile copyWith({
    String? id,
    String? username,
    String? publicKey,
    DateTime? createdAt,
    DateTime? lastLoginAt,
  }) {
    return Profile(
      id: id ?? this.id,
      username: username ?? this.username,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'public_key': publicKey,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_login_at': lastLoginAt?.millisecondsSinceEpoch,
    };
  }

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      username: json['username'] as String,
      publicKey: json['public_key'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['last_login_at'] as int)
          : null,
    );
  }

  @override
  List<Object?> get props => [id, username, publicKey, createdAt, lastLoginAt];

  @override
  String toString() {
    return 'Profile(id: $id, username: $username, createdAt: $createdAt)';
  }
}
