import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_test/flutter_test.dart';

class NeverSyncTransport implements SyncTransport {
  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) async {
    throw Exception('offline');
  }
}

class FakeNotificationScheduler implements NotificationScheduler {
  final List<String> cancelled = <String>[];
  final List<String> snoozed = <String>[];

  @override
  Future<void> cancelDose(String doseId) async => cancelled.add(doseId);

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> reconcile(List<DoseProjection> doses) async {}

  @override
  Future<void> scheduleDose(DoseProjection dose) async {}

  @override
  Future<void> snoozeDose(DoseProjection dose) async => snoozed.add(dose.id);
}

Future<void> seedDose(AppDatabase db) async {
  await db.into(db.cachedDoses).insert(
        CachedDosesCompanion.insert(
          doseId: 'dose-1',
          scheduleId: 'schedule-1',
          memberId: 'member-1',
          medicationId: 'med-1',
          medicationName: 'Metformin',
          strength: const Value<String?>('500 mg'),
          quantityText: '1',
          unit: 'tablet',
          mealRelation: const Value<String?>('after_food'),
          scheduledAt: DateTime.utc(2026, 9, 23, 14),
          scheduledLocalDate: '2026-09-23',
          scheduledLocalTime: '20:00',
          timezone: 'Asia/Dhaka',
          status: 'pending',
          effectiveReminderAt: DateTime.utc(2026, 9, 23, 14),
          updatedAt: DateTime.utc(2026, 9, 23, 13),
        ),
      );
}

void main() {
  test('mark taken updates cache immediately and queues one stable action', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDose(db);
    final scheduler = FakeNotificationScheduler();
    final coordinator = SyncCoordinator(
      database: db,
      transport: NeverSyncTransport(),
    );
    final repository = DoseRepository(
      database: db,
      syncCoordinator: coordinator,
      notificationScheduler: scheduler,
      idFactory: () => 'action-1',
    );

    await repository.markTaken(
      'dose-1',
      occurredAt: DateTime.utc(2026, 9, 23, 14, 5),
    );

    final dose = await (db.select(db.cachedDoses)
          ..where((row) => row.doseId.equals('dose-1')))
        .getSingle();
    final operations = await db.select(db.syncOperations).get();
    expect(dose.status, 'taken');
    expect(operations, hasLength(1));
    expect(operations.single.operationId, 'action-1');
    expect(operations.single.payloadJson, contains('"client_action_id":"action-1"'));
    expect(scheduler.cancelled, <String>['dose-1']);
  });

  test('snooze remains pending and reschedules notification', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDose(db);
    final scheduler = FakeNotificationScheduler();
    final coordinator = SyncCoordinator(
      database: db,
      transport: NeverSyncTransport(),
    );
    final repository = DoseRepository(
      database: db,
      syncCoordinator: coordinator,
      notificationScheduler: scheduler,
      idFactory: () => 'action-snooze',
    );
    final snoozedUntil = DateTime.utc(2026, 9, 23, 14, 20);

    await repository.snooze(
      'dose-1',
      occurredAt: DateTime.utc(2026, 9, 23, 14, 5),
      snoozedUntil: snoozedUntil,
    );

    final dose = await (db.select(db.cachedDoses)
          ..where((row) => row.doseId.equals('dose-1')))
        .getSingle();
    expect(dose.status, 'pending');
    expect(dose.snoozedUntil?.toUtc(), snoozedUntil);
    expect(scheduler.snoozed, <String>['dose-1']);
  });

  test('skip updates cache and cancels notification', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDose(db);
    final scheduler = FakeNotificationScheduler();
    final coordinator = SyncCoordinator(
      database: db,
      transport: NeverSyncTransport(),
    );
    final repository = DoseRepository(
      database: db,
      syncCoordinator: coordinator,
      notificationScheduler: scheduler,
      idFactory: () => 'action-skip',
    );

    await repository.skip(
      'dose-1',
      occurredAt: DateTime.utc(2026, 9, 23, 14, 5),
    );

    final dose = await (db.select(db.cachedDoses)
          ..where((row) => row.doseId.equals('dose-1')))
        .getSingle();
    expect(dose.status, 'skipped');
    expect(scheduler.cancelled, <String>['dose-1']);
  });
}
