import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/auth/domain/current_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountRepository {
  AccountRepository(this._client);
  final ApiClient _client;

  Future<CurrentUser> update({
    required String name,
    required String language,
  }) async {
    final response = await _client.patch<Map<String, dynamic>>(
      '/auth/me',
      data: {'name': name.trim(), 'preferred_language': language},
    );
    return CurrentUser.fromJson(response.data!);
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider)),
);
