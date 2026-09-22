import 'package:familymed/features/auth/domain/current_user.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  const AuthState.loading() : this(status: AuthStatus.loading);
  const AuthState.unauthenticated([String? message])
      : this(status: AuthStatus.unauthenticated, errorMessage: message);
  const AuthState.authenticated(CurrentUser currentUser)
      : this(status: AuthStatus.authenticated, user: currentUser);

  final AuthStatus status;
  final CurrentUser? user;
  final String? errorMessage;
}
