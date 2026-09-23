import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class NotificationPreference {
  const NotificationPreference({
    required this.memberId,
    required this.enabled,
    required this.defaultSnoozeMinutes,
  });

  final String memberId;
  final bool enabled;
  final int defaultSnoozeMinutes;

  factory NotificationPreference.fromJson(Map<String, dynamic> json) {
    return NotificationPreference(
      memberId: json['member_id'].toString(),
      enabled: json['enabled'] as bool,
      defaultSnoozeMinutes: json['default_snooze_minutes'] as int,
    );
  }
}

abstract interface class NotificationPreferenceRepository {
  Future<NotificationPreference> getPreference(String memberId);
  Future<NotificationPreference> updatePreference(
    String memberId, {
    bool? enabled,
    int? defaultSnoozeMinutes,
  });
}

class ApiNotificationPreferenceRepository
    implements NotificationPreferenceRepository {
  ApiNotificationPreferenceRepository(this._client);

  final ApiClient _client;

  @override
  Future<NotificationPreference> getPreference(String memberId) async {
    final response = await _client.get<Map<String, dynamic>>(
      '/family-members/$memberId/notification-preference',
    );
    return NotificationPreference.fromJson(response.data!);
  }

  @override
  Future<NotificationPreference> updatePreference(
    String memberId, {
    bool? enabled,
    int? defaultSnoozeMinutes,
  }) async {
    final data = <String, dynamic>{};
    if (enabled != null) data['enabled'] = enabled;
    if (defaultSnoozeMinutes != null) {
      data['default_snooze_minutes'] = defaultSnoozeMinutes;
    }
    final response = await _client.patch<Map<String, dynamic>>(
      '/family-members/$memberId/notification-preference',
      data: data,
    );
    return NotificationPreference.fromJson(response.data!);
  }
}

final notificationPreferenceRepositoryProvider =
    Provider<NotificationPreferenceRepository>((ref) {
  return ApiNotificationPreferenceRepository(ref.watch(apiClientProvider));
});
