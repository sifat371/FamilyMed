import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

abstract interface class HistoryRepository {
  Future<MemberHistory> load(
    String memberId, {
    DateTime? from,
    DateTime? to,
  });
}

class ApiHistoryRepository implements HistoryRepository {
  ApiHistoryRepository(this._client);

  final ApiClient _client;

  @override
  Future<MemberHistory> load(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final format = DateFormat('yyyy-MM-dd');
    final query = <String, dynamic>{
      if (from != null) 'from': format.format(from),
      if (to != null) 'to': format.format(to),
    };
    final response = await _client.get<Map<String, dynamic>>(
      '/family-members/$memberId/history',
      queryParameters: query.isEmpty ? null : query,
    );
    return MemberHistory.fromJson(response.data!);
  }
}

final historyRepositoryProvider = Provider<HistoryRepository>((ref) {
  return ApiHistoryRepository(ref.watch(apiClientProvider));
});
