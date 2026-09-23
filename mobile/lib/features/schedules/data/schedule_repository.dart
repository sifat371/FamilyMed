import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class ScheduleRepository {
  Future<MedicationSchedule> createSchedule(
    String medicationId,
    ScheduleDraft draft,
  );

  Future<MedicationSchedule?> getCurrentSchedule(String medicationId);

  Future<MedicationSchedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  );
}

class ApiScheduleRepository implements ScheduleRepository {
  ApiScheduleRepository(this._client);

  final ApiClient _client;

  @override
  Future<MedicationSchedule> createSchedule(
    String medicationId,
    ScheduleDraft draft,
  ) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/member-medications/$medicationId/schedules',
      data: draft.toJson(),
    );
    return MedicationSchedule.fromJson(response.data!);
  }

  @override
  Future<MedicationSchedule?> getCurrentSchedule(String medicationId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/member-medications/$medicationId/schedule',
      );
      return MedicationSchedule.fromJson(response.data!);
    } on ApiError catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<MedicationSchedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  ) async {
    final response = await _client.patch<Map<String, dynamic>>(
      '/schedules/$scheduleId',
      data: draft.toJson(),
    );
    return MedicationSchedule.fromJson(response.data!);
  }
}

final scheduleRepositoryProvider = Provider<ScheduleRepository>((ref) {
  return ApiScheduleRepository(ref.watch(apiClientProvider));
});
