import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/features/auth/domain/current_user.dart';

class AuthSession {
  const AuthSession({required this.user, required this.tokens});

  final CurrentUser user;
  final AuthTokens tokens;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      user: CurrentUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
      tokens: AuthTokens(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String,
      ),
    );
  }
}
