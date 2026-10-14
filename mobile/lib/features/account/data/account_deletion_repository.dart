import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Permanent account deletion requires a live authenticated session and
/// password or fresh Google identity confirmation. Never queue deletion offline.
class AccountDeletionRepository {
  const AccountDeletionRepository(this._api);
  final ApiClient _api;

  Future<void> deleteAccount({String? password, String? googleIdToken}) async {
    if ((password == null) == (googleIdToken == null)) {
      throw ArgumentError('Exactly one reauthentication credential is required.');
    }
    await _api.post<void>(
      '/auth/me/delete',
      data: password == null
          ? {'google_id_token': googleIdToken}
          : {'password': password},
    );
  }
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>(
  (ref) => AccountDeletionRepository(ref.watch(apiClientProvider)),
);
