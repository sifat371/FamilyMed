import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/features/auth/domain/auth_session.dart';
import 'package:familymed/features/auth/domain/current_user.dart';

abstract interface class AuthRepository {
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  });

  Future<AuthSession> login({
    required String email,
    required String password,
  });

  Future<CurrentUser> me();
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._client);

  final ApiClient _client;

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/register',
      data: {'name': name, 'email': email, 'password': password},
      skipAuth: true,
    );
    return AuthSession.fromJson(response.data!);
  }

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
      skipAuth: true,
    );
    return AuthSession.fromJson(response.data!);
  }

  @override
  Future<CurrentUser> me() async {
    final response = await _client.get<Map<String, dynamic>>('/auth/me');
    return CurrentUser.fromJson(response.data!);
  }
}
