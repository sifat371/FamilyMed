import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

class DoseRepository {
  DoseRepository({
    required AppDatabase database,
    required SyncCoordinator syncCoordinator,
    required NotificationScheduler notificationScheduler,
    String Function()? idFactory,
  })  : _database = database,
        _syncCoordinator = syncCoordinator,
        _notificationScheduler = notificationScheduler,
        _idFactory = idFactory ?? const Uuid().v4;

  final AppDatabase _database;
  final SyncCoordinator _syncCoordinator;
  final NotificationScheduler _notificationScheduler;
  final String Function() _idFactory;

  Future<void> markTaken(
    String doseId, {
    required DateTime occurredAt,
  }) async {
    final actionId = _idFactory();
    await _queue(
      doseId,
      action: 'taken',
      actionId: actionId,
      payload: <String, dynamic>{
        'client_action_id': actionId,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      optimisticStatus: 'taken',
      takenAt: occurredAt.toUtc(),
      clearSnooze: true,
    );
    await _notificationScheduler.cancelDose(doseId);
    await _syncCoordinator.drain();
  }

  Future<void> skip(
    String doseId, {
    required DateTime occurredAt,
  }) async {
    final actionId = _idFactory();
    await _queue(
      doseId,
      action: 'skip',
      actionId: actionId,
      payload: <String, dynamic>{
        'client_action_id': actionId,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
      optimisticStatus: 'skipped',
      skippedAt: occurredAt.toUtc(),
      clearSnooze: true,
    );
    await _notificationScheduler.cancelDose(doseId);
    await _syncCoordinator.drain();
  }

  Future<void> snooze(
    String doseId, {
    required DateTime occurredAt,
    required DateTime snoozedUntil,
  }) async {
    final actionId = _idFactory();
    await _queue(
      doseId,
      action: 'snooze',
      actionId: actionId,
      payload: <String, dynamic>{
        'client_action_id': actionId,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'snoozed_until': snoozedUntil.toUtc().toIso8601String(),
      },
      optimisticStatus: 'pending',
      snoozedUntil: snoozedUntil.toUtc(),
      effectiveReminderAt: snoozedUntil.toUtc(),
    );
    final dose = await cachedDose(doseId);
    if (dose != null) {
      await _notificationScheduler.snoozeDose(dose);
    }
    await _syncCoordinator.drain();
  }

  Future<void> correct(
    String doseId, {
    required DateTime occurredAt,
    required String newStatus,
    required DateTime effectiveAt,
    String? reason,
  }) async {
    final actionId = _idFactory();
    final payload = <String, dynamic>{
      'client_action_id': actionId,
      'occurred_at': occurredAt.toUtc().toIso8601String(),
      'new_status': newStatus,
      'effective_at': effectiveAt.toUtc().toIso8601String(),
      'reason': reason,
    };
    await _queue(
      doseId,
      action: 'correct',
      actionId: actionId,
      payload: payload,
      optimisticStatus: newStatus,
      takenAt: newStatus == 'taken' ? effectiveAt.toUtc() : null,
      skippedAt: newStatus == 'skipped' ? effectiveAt.toUtc() : null,
      missedAt: newStatus == 'missed' ? effectiveAt.toUtc() : null,
      clearSnooze: true,
    );
    await _notificationScheduler.cancelDose(doseId);
    await _syncCoordinator.drain();
  }

  Future<DoseProjection?> cachedDose(String doseId) async {
    final row = await (_database.select(_database.cachedDoses)
          ..where((dose) => dose.doseId.equals(doseId)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<void> _queue(
    String doseId, {
    required String action,
    required String actionId,
    required Map<String, dynamic> payload,
    required String optimisticStatus,
    DateTime? snoozedUntil,
    DateTime? takenAt,
    DateTime? skippedAt,
    DateTime? missedAt,
    DateTime? effectiveReminderAt,
    bool clearSnooze = false,
  }) async {
    await _database.transaction(() async {
      final current = await (_database.select(_database.cachedDoses)
            ..where((dose) => dose.doseId.equals(doseId)))
          .getSingle();
      final queuedPayload = <String, dynamic>{
        ...payload,
        '_previous': _rowSnapshot(current),
      };
      await (_database.update(_database.cachedDoses)
            ..where((dose) => dose.doseId.equals(doseId)))
          .write(
        CachedDosesCompanion(
          status: Value<String>(optimisticStatus),
          snoozedUntil: clearSnooze
              ? const Value<DateTime?>(null)
              : Value<DateTime?>(snoozedUntil ?? current.snoozedUntil),
          takenAt: Value<DateTime?>(takenAt ?? current.takenAt),
          skippedAt: Value<DateTime?>(skippedAt ?? current.skippedAt),
          missedAt: Value<DateTime?>(missedAt ?? current.missedAt),
          effectiveReminderAt: Value<DateTime>(
            effectiveReminderAt ?? current.effectiveReminderAt,
          ),
          updatedAt: Value<DateTime>(DateTime.now().toUtc()),
        ),
      );
      await _database.into(_database.syncOperations).insert(
            SyncOperationsCompanion.insert(
              operationId: actionId,
              doseId: doseId,
              action: action,
              payloadJson: jsonEncode(queuedPayload),
              createdAt: DateTime.now().toUtc(),
            ),
          );
    });
  }

  Map<String, dynamic> _rowSnapshot(CachedDose row) {
    return <String, dynamic>{
      'status': row.status,
      'snoozed_until': row.snoozedUntil?.toUtc().toIso8601String(),
      'taken_at': row.takenAt?.toUtc().toIso8601String(),
      'skipped_at': row.skippedAt?.toUtc().toIso8601String(),
      'missed_at': row.missedAt?.toUtc().toIso8601String(),
      'effective_reminder_at': row.effectiveReminderAt.toUtc().toIso8601String(),
    };
  }

  DoseProjection _fromRow(CachedDose row) {
    return DoseProjection(
      id: row.doseId,
      scheduleId: row.scheduleId,
      familyMemberId: row.memberId,
      memberMedicationId: row.medicationId,
      medicationName: row.medicationName,
      strength: row.strength,
      scheduledAt: row.scheduledAt.toUtc(),
      scheduledLocalDate: row.scheduledLocalDate,
      scheduledLocalTime: row.scheduledLocalTime,
      timezone: row.timezone,
      quantityText: row.quantityText,
      unit: row.unit,
      mealRelation: row.mealRelation,
      status: row.status,
      snoozedUntil: row.snoozedUntil?.toUtc(),
      takenAt: row.takenAt?.toUtc(),
      skippedAt: row.skippedAt?.toUtc(),
      missedAt: row.missedAt?.toUtc(),
      effectiveReminderAt: row.effectiveReminderAt.toUtc(),
    );
  }
}


final doseRepositoryProvider = Provider<DoseRepository>((ref) {
  return DoseRepository(
    database: ref.watch(appDatabaseProvider),
    syncCoordinator: ref.watch(syncCoordinatorProvider),
    notificationScheduler: ref.watch(notificationSchedulerProvider),
  );
});
