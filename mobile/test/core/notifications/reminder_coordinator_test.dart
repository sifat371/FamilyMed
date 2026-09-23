import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:flutter_test/flutter_test.dart';

class _TodayRepository implements TodayRepository {
  _TodayRepository(this.doses);

  final List<DoseProjection> doses;
  int loads = 0;

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async => doses;

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async {
    loads++;
    return doses;
  }

  @override
  Future<TodayLoadResult> loadToday() async =>
      const TodayLoadResult(groups: <TodayMemberGroup>[], isOffline: false);
}

class _Scheduler implements NotificationScheduler {
  List<DoseProjection>? reconciled;

  @override
  Future<void> cancelDose(String doseId) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> reconcile(List<DoseProjection> doses) async {
    reconciled = List<DoseProjection>.from(doses);
  }

  @override
  Future<void> scheduleDose(DoseProjection dose) async {}

  @override
  Future<void> snoozeDose(DoseProjection dose) async {}
}

DoseProjection _dose() {
  final at = DateTime.utc(2026, 9, 24, 2);
  return DoseProjection(
    id: 'dose-1',
    scheduleId: 'schedule-1',
    familyMemberId: 'member-1',
    memberMedicationId: 'med-1',
    medicationName: 'Metformin',
    strength: '500 mg',
    scheduledAt: at,
    scheduledLocalDate: '2026-09-24',
    scheduledLocalTime: '08:00',
    timezone: 'Asia/Dhaka',
    quantityText: '1',
    unit: 'tablet',
    mealRelation: 'after_food',
    status: 'upcoming',
    effectiveReminderAt: at,
  );
}

void main() {
  test('refresh reconciles exactly the server-approved reminder feed', () async {
    final repository = _TodayRepository(<DoseProjection>[_dose()]);
    final scheduler = _Scheduler();
    final coordinator = ReminderCoordinator(
      todayRepository: repository,
      scheduler: scheduler,
    );

    await coordinator.refresh();

    expect(repository.loads, 1);
    expect(scheduler.reconciled?.map((dose) => dose.id), <String>['dose-1']);
  });

  test('clear removes locally scheduled medication reminders', () async {
    final scheduler = _Scheduler();
    final coordinator = ReminderCoordinator(
      todayRepository: _TodayRepository(const <DoseProjection>[]),
      scheduler: scheduler,
    );

    await coordinator.clear();

    expect(scheduler.reconciled, isEmpty);
  });
}
