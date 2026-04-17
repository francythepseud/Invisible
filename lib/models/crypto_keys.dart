import 'package:equatable/equatable.dart';

class CryptoKeys extends Equatable {
  // masterKey (X25519) — usata come long-term DH identity key in X3DH
  final String masterKeyPrivate;
  final String masterKeyPublic;
  // identityKey (Ed25519) — usata per firme e autenticazione
  final String identityKeyPrivate;
  final String identityKeyPublic;
  // signedPreKey (X25519) — chiave separata per il protocollo X3DH
  final String signedPreKeyPrivate;
  final String signedPreKeyPublic;
  /// Firma Ed25519 della signedPreKey pubblica: prova che appartiene a questo profilo
  final String signedPreKeySignature;
  final DateTime signedPreKeyCreatedAt;

  const CryptoKeys({
    required this.masterKeyPrivate,
    required this.masterKeyPublic,
    required this.identityKeyPrivate,
    required this.identityKeyPublic,
    required this.signedPreKeyPrivate,
    required this.signedPreKeyPublic,
    required this.signedPreKeySignature,
    required this.signedPreKeyCreatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'master_key_private': masterKeyPrivate,
      'master_key_public': masterKeyPublic,
      'identity_key_private': identityKeyPrivate,
      'identity_key_public': identityKeyPublic,
      'signed_pre_key_private': signedPreKeyPrivate,
      'signed_pre_key_public': signedPreKeyPublic,
      'signed_pre_key_signature': signedPreKeySignature,
      'signed_pre_key_created_at': signedPreKeyCreatedAt.millisecondsSinceEpoch,
    };
  }

  factory CryptoKeys.fromJson(Map<String, dynamic> json) {
    return CryptoKeys(
      masterKeyPrivate: json['master_key_private'] as String,
      masterKeyPublic: json['master_key_public'] as String,
      identityKeyPrivate: json['identity_key_private'] as String,
      identityKeyPublic: json['identity_key_public'] as String,
      signedPreKeyPrivate: json['signed_pre_key_private'] as String,
      signedPreKeyPublic: json['signed_pre_key_public'] as String,
      signedPreKeySignature: (json['signed_pre_key_signature'] as String?) ?? '',
      signedPreKeyCreatedAt: DateTime.fromMillisecondsSinceEpoch(
        json['signed_pre_key_created_at'] as int,
      ),
    );
  }

  @override
  List<Object?> get props => [
        masterKeyPublic,
        identityKeyPublic,
        signedPreKeyPublic,
        signedPreKeySignature,
        signedPreKeyCreatedAt,
      ];

  @override
  String toString() =>
      'CryptoKeys(ik: ${identityKeyPublic.substring(0, 8)}..., spk: ${signedPreKeyPublic.substring(0, 8)}...)';
}
