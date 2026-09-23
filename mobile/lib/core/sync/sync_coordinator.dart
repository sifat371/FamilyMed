import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/sync/api_activity_events.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncEventKind { recordChanged, terminalFailure }

class SyncEvent {
  const SyncEvent({
    required this.kind,
    required this.doseId,
    this.message,
  });

  final SyncEventKind kind;
  final String doseId;
  final String? message;
}

class SyncOperationEnvelope {
  const SyncOperationEnvelope({
    required this.operationId,
    required this.doseId,
    required this.action,
    required this.payload,
  });

  final String operationId;
  final String doseId;
  final String action;
  final Map<String, dynamic> payload;

  String get clientActionId => operationId;
}

abstract interface class SyncTransport {
  Future<DoseProjection> submit(SyncOperationEnvelope operation);
}

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport(this._client);

  final ApiClient _client;

  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) async {
    final response = await _client.post<Map<String, dynamic>>(
      '/doses/${operation.doseId}/${operation.action}',
      data: operation.payload,
    );
    return DoseProjection.fromJson(response.data!);
  }
}

class SyncCoordinator {
  SyncCoordinator({
    required AppDatabase database,
    required SyncTransport transport,
    ApiActivityEvents? activityEvents,
    String userId = '',
  })  : _database = database,
        _transport = transport,
        _userId = userId {
    _activitySubscription = activityEvents?.successes.listen((_) {
      unawaited(drain());
    });
  }

  final AppDatabase _database;
  final SyncTransport _transport;
  final String _userId;
  final StreamController<SyncEvent> _events =
      StreamController<SyncEvent>.broadcast();
  Future<void>? _drainFuture;
  StreamSubscription<void>? _activitySubscription;

  Stream<SyncEvent> get events => _events.stream;

  Future<void> drain() {
    return _drainFuture ??= _drain().whenComplete(() {
      _drainFuture = null;
    });
  }

  Future<void> _drain() async {
    final rows = await (_database.select(_database.syncOperations)
          ..where(
            (row) =>
                row.terminalFailure.equals(false) &
                row.userId.equals(_userId),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();

    for (final row in rows) {
      final payload = Map<String, dynamic>.from(
        jsonDecode(row.payloadJson) as Map,
      );
      final envelope = SyncOperationEnvelope(
        operationId: row.operationId,
        doseId: row.doseId,
        action: row.action,
        payload: payload,
      );
      try {
        final serverDose = await _transport.submit(envelope);
        await _replaceCachedDose(serverDose);
        await _deleteOperation(row.operationId);
      } on ApiError catch (error) {
        if (error.statusCode == 409) {
          final current = error.details['current'];
          if (current is Map) {
            await _replaceCachedDose(
              DoseProjection.fromJson(Map<String, dynamic>.from(current)),
            );
            await _deleteOperation(row.operationId);
            _events.add(
              SyncEvent(
                kind: SyncEventKind.recordChanged,
                doseId: row.doseId,
                message: error.message,
              ),
            );
          } else {
            await _markTerminalFailure(
              row.operationId,
              row.attemptCount,
              error.message,
            );
            _events.add(
              SyncEvent(
                kind: SyncEventKind.terminalFailure,
                doseId: row.doseId,
                message: error.message,
              ),
            );
          }
          continue;
        }
        if (error.statusCode == 404) {
          await _database.transaction(() async {
            await (_database.delete(_database.cachedDoses)
                  ..where(
                    (dose) =>
                        dose.doseId.equals(row.doseId) &
                        dose.userId.equals(_userId),
                  ))
                .go();
            await _deleteOperation(row.operationId);
          });
          continue;
        }
        if (error.statusCode == 422) {
          await _markTerminalFailure(
            row.operationId,
            row.attemptCount,
            error.message,
          );
          _events.add(
            SyncEvent(
              kind: SyncEventKind.terminalFailure,
              doseId: row.doseId,
              message: error.message,
            ),
          );
          continue;
        }
        await _recordTransientFailure(
          row.operationId,
          row.attemptCount,
          error.message,
        );
      } on Object catch (error) {
        await _recordTransientFailure(
          row.operationId,
          row.attemptCount,
          error.toString(),
        );
      }
    }
  }

  Future<void> _deleteOperation(String operationId) {
    return (_database.delete(_database.syncOperations)
          ..where(
            (item) =>
                item.operationId.equals(operationId) &
                item.userId.equals(_userId),
          ))
        .go();
  }

  Future<void> _markTerminalFailure(
    String operationId,
    int attempts,
    String message,
  ) {
    return (_database.update(_database.syncOperations)
          ..where(
            (item) =>
                item.operationId.equals(operationId) &
                item.userId.equals(_userId),
          ))
        .write(
      SyncOperationsCompanion(
        attemptCount: Value<int>(attempts + 1),
        lastError: Value<String?>(message),
        terminalFailure: const Value<bool>(true),
      ),
    );
  }

  Future<void> _recordTransientFailure(
    String operationId,
    int attempts,
    String message,
  ) {
    return (_database.update(_database.syncOperations)
          ..where(
            (item) =>
                item.operationId.equals(operationId) &
                item.userId.equals(_userId),
          ))
        .write(
      SyncOperationsCompanion(
        attemptCount: Value<int>(attempts + 1),
        lastError: Value<String?>(message),
      ),
    );
  }

  Future<void> _replaceCachedDose(DoseProjection dose) async {
    final existing = await (_database.select(_database.cachedDoses)
          ..where(
            (row) =>
                row.doseId.equals(dose.id) &
                row.userId.equals(_userId),
          ))
        .getSingleOrNull();
    final reminderEligible = _isFinal(dose.status)
        ? false
        : existing?.reminderEligible ?? false;

    await _database.into(_database.cachedDoses).insertOnConflictUpdate(
          CachedDosesCompanion.insert(
            doseId: dose.id,
            userId: Value<String>(_userId),
            reminderEligible: Value<bool>(reminderEligible),
            scheduleId: dose.scheduleId,
            memberId: dose.familyMemberId,
            medicationId: dose.memberMedicationId,
            medicationName: dose.medicationName,
            strength: Value<String?>(dose.strength),
            quantityText: dose.quantityText,
            unit: dose.unit,
            mealRelation: Value<String?>(dose.mealRelation),
            scheduledAt: dose.scheduledAt,
            scheduledLocalDate: dose.scheduledLocalDate,
            scheduledLocalTime: dose.scheduledLocalTime,
            timezone: dose.timezone,
            status: dose.status,
            snoozedUntil: Value<DateTime?>(dose.snoozedUntil),
            takenAt: Value<DateTime?>(dose.takenAt),
            skippedAt: Value<DateTime?>(dose.skippedAt),
            missedAt: Value<DateTime?>(dose.missedAt),
            effectiveReminderAt: dose.effectiveReminderAt,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
  }

  bool _isFinal(String status) =>
      status == 'taken' || status == 'skipped' || status == 'missed';

  Future<void> dispose() async {
    await _activitySubscription?.cancel();
    await _events.close();
  }
}

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final userId = ref.watch(authControllerProvider).user?.id ?? '';
  final coordinator = SyncCoordinator(
    database: ref.watch(appDatabaseProvider),
    transport: ApiSyncTransport(ref.watch(apiClientProvider)),
    activityEvents: ref.watch(apiActivityEventsProvider),
    userId: userId,
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final syncEventsProvider = StreamProvider<SyncEvent>((ref) {
  return ref.watch(syncCoordinatorProvider).events;
});
