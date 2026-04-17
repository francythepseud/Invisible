import 'package:equatable/equatable.dart';

class UserCredentials extends Equatable {
  final String username;
  final String password;

  const UserCredentials({
    required this.username,
    required this.password,
  });

  @override
  List<Object?> get props => [username, password];

  @override
  String toString() {
    return 'UserCredentials(username: $username, password: [HIDDEN])';
  }
}
