import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Permanent account deletion requires a live authenticated session and
/// password confirmation. It must never queue an offline deletion request.
class AccountDeletionRepository {
  const AccountDeletionRepository(this._api);
  final ApiClient _api;

  Future<void> deleteAccount(String password) async {
    await _api.post<void>('/auth/me/delete', data: {'password': password});
  }
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => AccountDeletionRepository(ref.watch(apiClientProvider)),
);
