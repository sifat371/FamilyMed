import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/sync/api_activity_events.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSyncTransport implements SyncTransport {
  Object? error;
  DoseProjection? response;
  int calls = 0;
  final List<String> clientActionIds = <String>[];

  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) async {
    calls++;
    clientActionIds.add(operation.clientActionId);
    if (error != null) throw error!;
    return response ?? _dose(status: 'taken');
  }

  test('only replays queued actions belonging to the authenticated account', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = FakeSyncTransport()..response = _dose(status: 'taken');
    final coordinator = SyncCoordinator(
      database: db,
      transport: transport,
      userId: 'user-a',
    );
    addTearDown(coordinator.dispose);

    await _seedOperation(
      db,
      operationId: 'action-a',
      userId: 'user-a',
    );
    await _seedOperation(
      db,
      operationId: 'action-b',
      userId: 'user-b',
    );

    await coordinator.drain();

    expect(transport.clientActionIds, <String>['action-a']);
    final remaining = await db.customSelect(
      'SELECT operation_id FROM sync_operations ORDER BY operation_id',
    ).get();
    expect(
      remaining.map((row) => row.read<String>('operation_id')).toList(),
      <String>['action-b'],
    );
  });

}

DoseProjection _dose({required String status}) {
  final scheduled = DateTime.utc(2026, 9, 23, 14);
  return DoseProjection(
    id: 'dose-1',
    scheduleId: 'schedule-1',
    familyMemberId: 'member-1',
    memberMedicationId: 'med-1',
    medicationName: 'Metformin',
    strength: '500 mg',
    scheduledAt: scheduled,
    scheduledLocalDate: '2026-09-23',
    scheduledLocalTime: '20:00',
    timezone: 'Asia/Dhaka',
    quantityText: '1',
    unit: 'tablet',
    mealRelation: 'after_food',
    status: status,
    effectiveReminderAt: scheduled,
  );
}

Future<void> _seedOperation(
  AppDatabase db, {
  required String operationId,
  String action = 'taken',
  String userId = '',
}) async {
  await db.customInsert(
    'INSERT INTO sync_operations '
    '(operation_id, user_id, dose_id, action, payload_json, created_at, '
    'attempt_count, terminal_failure) VALUES (?, ?, ?, ?, ?, ?, 0, 0)',
    variables: [
      Variable<String>(operationId),
      Variable<String>(userId),
      const Variable<String>('dose-1'),
      Variable<String>(action),
      Variable<String>(jsonEncode(<String, dynamic>{
        'client_action_id': operationId,
        'occurred_at': '2026-09-23T14:05:00Z',
      })),
      Variable<DateTime>(DateTime.utc(2026, 9, 23, 14, 5)),
    ],
  );
}

void main() {
  test('API activity event drains queued operations', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = FakeSyncTransport()..response = _dose(status: 'taken');
    final activityEvents = ApiActivityEvents();
    addTearDown(activityEvents.dispose);
    final coordinator = SyncCoordinator(
      database: db,
      transport: transport,
      activityEvents: activityEvents,
    );
    addTearDown(coordinator.dispose);

    await _seedOperation(db, operationId: 'action-event');
    activityEvents.notifySuccess();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.calls, 1);
    final pending = await db.customSelect(
      'SELECT COUNT(*) AS count FROM sync_operations',
    ).getSingle();
    expect(pending.read<int>('count'), 0);
  });

  test('network failure keeps operation and stable client action id for retry', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = FakeSyncTransport()
      ..error = const ApiError(
        code: 'NETWORK_ERROR',
        message: 'offline',
      );
    final coordinator = SyncCoordinator(database: db, transport: transport);

    await _seedOperation(db, operationId: 'action-1');
    await coordinator.drain();
    await coordinator.drain();

    expect(transport.clientActionIds, <String>['action-1', 'action-1']);
    final row = await db.customSelect(
      'SELECT attempt_count, terminal_failure FROM sync_operations '
      'WHERE operation_id = ?',
      variables: [const Variable<String>('action-1')],
    ).getSingle();
    expect(row.read<int>('attempt_count'), 2);
    expect(row.read<int>('terminal_failure'), 0);
  });

  test('permanent 422 marks operation terminal and never retries it', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = FakeSyncTransport()
      ..error = const ApiError(
        code: 'VALIDATION_ERROR',
        message: 'invalid action',
        statusCode: 422,
      );
    final coordinator = SyncCoordinator(database: db, transport: transport);

    await _seedOperation(db, operationId: 'action-422');
    await coordinator.drain();
    await coordinator.drain();

    expect(transport.calls, 1);
    final row = await db.customSelect(
      'SELECT attempt_count, terminal_failure FROM sync_operations '
      'WHERE operation_id = ?',
      variables: [const Variable<String>('action-422')],
    ).getSingle();
    expect(row.read<int>('attempt_count'), 1);
    expect(row.read<int>('terminal_failure'), 1);
  });

  test('409 adopts server projection and removes queued operation', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = FakeSyncTransport()
      ..error = ApiError(
        code: 'DOSE_ALREADY_FINALIZED',
        message: 'already final',
        statusCode: 409,
        details: <String, dynamic>{
          'current': <String, dynamic>{
            'id': 'dose-1',
            'schedule_id': 'schedule-1',
            'family_member_id': 'member-1',
            'member_medication_id': 'med-1',
            'medication_name': 'Metformin',
            'strength': '500 mg',
            'scheduled_at': '2026-09-23T14:00:00Z',
            'scheduled_local_date': '2026-09-23',
            'scheduled_local_time': '20:00:00',
            'timezone': 'Asia/Dhaka',
            'quantity': '1',
            'unit': 'tablet',
            'meal_relation': 'after_food',
            'status': 'skipped',
            'snoozed_until': null,
            'taken_at': null,
            'skipped_at': '2026-09-23T14:04:00Z',
            'missed_at': null,
            'effective_reminder_at': '2026-09-23T14:00:00Z'
          }
        },
      );
    final coordinator = SyncCoordinator(database: db, transport: transport);

    await _seedOperation(db, operationId: 'action-conflict');
    final eventFuture = coordinator.events.first;
    await coordinator.drain();

    final pending = await db.customSelect(
      'SELECT COUNT(*) AS count FROM sync_operations',
    ).getSingle();
    expect(pending.read<int>('count'), 0);
    final event = await eventFuture;
    expect(event.kind, SyncEventKind.recordChanged);
  });

  test('409 without canonical projection remains visible terminal failure', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = FakeSyncTransport()
      ..error = const ApiError(
        code: 'IDEMPOTENCY_KEY_REUSED',
        message: 'action id was reused',
        statusCode: 409,
      );
    final coordinator = SyncCoordinator(database: db, transport: transport);
    addTearDown(coordinator.dispose);

    await _seedOperation(db, operationId: 'action-bad-409');
    final eventFuture = coordinator.events.first;
    await coordinator.drain();

    final row = await db.customSelect(
      'SELECT attempt_count, terminal_failure FROM sync_operations '
      'WHERE operation_id = ?',
      variables: [const Variable<String>('action-bad-409')],
    ).getSingle();
    expect(row.read<int>('attempt_count'), 1);
    expect(row.read<int>('terminal_failure'), 1);
    expect((await eventFuture).kind, SyncEventKind.terminalFailure);
  });

}
