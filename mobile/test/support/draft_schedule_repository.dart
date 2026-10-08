import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';

class DraftScheduleRepository implements ScheduleRepository {
  @override
  Future<MedicationSchedule?> getCurrentSchedule(String medicationId) async =>
      null;

  @override
  Future<MedicationSchedule> createSchedule(
    String medicationId,
    ScheduleDraft draft,
  ) => throw UnimplementedError();

  @override
  Future<MedicationSchedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  ) => throw UnimplementedError();
}
