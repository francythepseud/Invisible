import 'package:equatable/equatable.dart';

class Contact extends Equatable {
  final String id;
  final String name;
  /// Chiave pubblica X25519 master del contatto (DH identity key in X3DH)
  final String publicKey;
  /// Chiave pubblica Ed25519 del contatto (firma + auth)
  final String? identityKey;
  /// Chiave pubblica X25519 Signed Pre-Key del contatto (separata da publicKey)
  final String? signedPreKey;
  /// Firma Ed25519 della signedPreKey — verifica che appartenga a questo contatto
  final String? signedPreKeySig;
  final String? avatarPath;
  final bool blocked;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Contact({
    required this.id,
    required this.name,
    required this.publicKey,
    this.identityKey,
    this.signedPreKey,
    this.signedPreKeySig,
    this.avatarPath,
    this.blocked = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Contact copyWith({
    String? id,
    String? name,
    String? publicKey,
    String? identityKey,
    String? signedPreKey,
    String? signedPreKeySig,
    String? avatarPath,
    bool? blocked,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Contact(
      id: id ?? this.id,
      name: name ?? this.name,
      publicKey: publicKey ?? this.publicKey,
      identityKey: identityKey ?? this.identityKey,
      signedPreKey: signedPreKey ?? this.signedPreKey,
      signedPreKeySig: signedPreKeySig ?? this.signedPreKeySig,
      avatarPath: avatarPath ?? this.avatarPath,
      blocked: blocked ?? this.blocked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'public_key': publicKey,
      'identity_key': identityKey,
      'signed_pre_key': signedPreKey,
      'signed_pre_key_sig': signedPreKeySig,
      'avatar_path': avatarPath,
      'blocked': blocked ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      id: json['id'] as String,
      name: json['name'] as String,
      publicKey: json['public_key'] as String,
      identityKey: json['identity_key'] as String?,
      signedPreKey: json['signed_pre_key'] as String?,
      signedPreKeySig: json['signed_pre_key_sig'] as String?,
      avatarPath: json['avatar_path'] as String?,
      blocked: (json['blocked'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        publicKey,
        identityKey,
        signedPreKey,
        signedPreKeySig,
        blocked,
        createdAt,
        updatedAt,
      ];

  @override
  String toString() => 'Contact(id: $id, name: $name, blocked: $blocked)';
}
