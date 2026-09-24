import 'package:drift/drift.dart';
import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class TodayRepository {
  Future<TodayLoadResult> loadToday();
  Future<List<DoseProjection>> loadReminderDoses({int days = 30});
  Future<List<DoseProjection>> cachedReminderDoses();
}

class ApiTodayRepository implements TodayRepository {
  ApiTodayRepository(
    this._client,
    this._database, {
    String userId = '',
  }) : _userId = userId;

  final ApiClient _client;
  final AppDatabase _database;
  final String _userId;

  @override
  Future<TodayLoadResult> loadToday() async {
    try {
      final response = await _client.get<List<dynamic>>('/today');
      final groups = response.data!
          .map(
            (item) => TodayMemberGroup.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      await _replaceTodayCache(groups);
      return TodayLoadResult(
        groups: await _readTodayCache(),
        isOffline: false,
      );
    } on ApiError catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      final cached = await _readTodayCache();
      if (cached.isEmpty) rethrow;
      return TodayLoadResult(groups: cached, isOffline: true);
    }
  }

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async {
    try {
      final response = await _client.get<List<dynamic>>(
        '/reminder-doses',
        queryParameters: <String, dynamic>{'days': days},
      );
      final serverDoses = response.data!
          .map(
            (item) => DoseProjection.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);

      final effectiveDoses = <DoseProjection>[];
      await _database.transaction(() async {
        await (_database.update(_database.cachedDoses)
              ..where((row) => row.userId.equals(_userId)))
            .write(
          const CachedDosesCompanion(
            reminderEligible: Value<bool>(false),
          ),
        );

        final queuedDoseIds = await _queuedDoseIds();
        for (final serverDose in serverDoses) {
          if (queuedDoseIds.contains(serverDose.id)) {
            final localDose = await _cachedDose(serverDose.id);
            if (localDose != null && !_isFinal(localDose.status)) {
              await _setReminderEligible(serverDose.id, true);
              effectiveDoses.add(localDose);
            }
            continue;
          }

          await _upsertDose(serverDose, reminderEligible: true);
          effectiveDoses.add(serverDose);
        }
      });
      return effectiveDoses;
    } on ApiError catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      return cachedReminderDoses();
    }
  }

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async {
    final rows = await (_database.select(_database.cachedDoses)
          ..where(
            (row) =>
                row.userId.equals(_userId) &
                row.reminderEligible.equals(true) &
                row.status.isNotIn(<String>['taken', 'skipped', 'missed']),
          )
          ..orderBy([
            (row) => OrderingTerm.asc(row.effectiveReminderAt),
          ]))
        .get();
    return rows.map(_doseFromRow).toList(growable: false);
  }

  Future<void> _replaceTodayCache(List<TodayMemberGroup> groups) async {
    await _database.transaction(() async {
      final queuedDoseIds = await _queuedDoseIds();
      await (_database.delete(_database.cachedTodayMembers)
            ..where((row) => row.userId.equals(_userId)))
          .go();

      for (final group in groups) {
        await _database.into(_database.cachedTodayMembers).insertOnConflictUpdate(
              CachedTodayMembersCompanion.insert(
                memberId: group.memberId,
                userId: Value<String>(_userId),
                name: group.name,
                relationship: group.relationship,
                localDate: group.localDate,
                timezone: group.timezone,
                updatedAt: DateTime.now().toUtc(),
              ),
            );

        final existing = await (_database.select(_database.cachedDoses)
              ..where(
                (row) =>
                    row.userId.equals(_userId) &
                    row.memberId.equals(group.memberId) &
                    row.scheduledLocalDate.equals(group.localDate),
              ))
            .get();
        final serverDoseIds = group.doses.map((dose) => dose.id).toSet();

        for (final row in existing) {
          if (queuedDoseIds.contains(row.doseId)) continue;
          if (serverDoseIds.contains(row.doseId)) continue;
          await (_database.delete(_database.cachedDoses)
                ..where(
                  (dose) =>
                      dose.doseId.equals(row.doseId) &
                      dose.userId.equals(_userId),
                ))
              .go();
        }

        for (final dose in group.doses) {
          if (!queuedDoseIds.contains(dose.id)) {
            await _upsertDose(dose);
          }
        }
      }
    });
  }

  Future<Set<String>> _queuedDoseIds() async {
    final rows = await (_database.select(_database.syncOperations)
          ..where((row) => row.userId.equals(_userId)))
        .get();
    return rows.map((row) => row.doseId).toSet();
  }

  Future<DoseProjection?> _cachedDose(String doseId) async {
    final row = await (_database.select(_database.cachedDoses)
          ..where(
            (dose) =>
                dose.doseId.equals(doseId) &
                dose.userId.equals(_userId),
          ))
        .getSingleOrNull();
    return row == null ? null : _doseFromRow(row);
  }

  Future<void> _setReminderEligible(String doseId, bool eligible) {
    return (_database.update(_database.cachedDoses)
          ..where(
            (dose) =>
                dose.doseId.equals(doseId) &
                dose.userId.equals(_userId),
          ))
        .write(
      CachedDosesCompanion(
        reminderEligible: Value<bool>(eligible),
      ),
    );
  }

  Future<void> _upsertDose(
    DoseProjection dose, {
    bool? reminderEligible,
  }) async {
    final existing = await (_database.select(_database.cachedDoses)
          ..where(
            (row) =>
                row.doseId.equals(dose.id) &
                row.userId.equals(_userId),
          ))
        .getSingleOrNull();
    final eligible = reminderEligible ?? existing?.reminderEligible ?? false;
    final medicationName =
        dose.medicationName == 'Medication' && existing != null
            ? existing.medicationName
            : dose.medicationName;
    final strength = dose.strength ?? existing?.strength;
    final memberName = dose.familyMemberName ??
        (existing == null || existing.memberName.isEmpty
            ? null
            : existing.memberName);

    await _database.into(_database.cachedDoses).insertOnConflictUpdate(
          CachedDosesCompanion.insert(
            doseId: dose.id,
            userId: Value<String>(_userId),
            reminderEligible: Value<bool>(eligible),
            scheduleId: dose.scheduleId,
            memberId: dose.familyMemberId,
            memberName: Value<String>(memberName ?? ''),
            medicationId: dose.memberMedicationId,
            medicationName: medicationName,
            strength: Value<String?>(strength),
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

  Future<List<TodayMemberGroup>> _readTodayCache() async {
    final memberRows = await (_database.select(_database.cachedTodayMembers)
          ..where((row) => row.userId.equals(_userId)))
        .get();
    final groups = <TodayMemberGroup>[];
    for (final member in memberRows) {
      final doseRows = await (_database.select(_database.cachedDoses)
            ..where(
              (row) =>
                  row.userId.equals(_userId) &
                  row.memberId.equals(member.memberId) &
                  row.scheduledLocalDate.equals(member.localDate),
            )
            ..orderBy([
              (row) => OrderingTerm.asc(row.effectiveReminderAt),
            ]))
          .get();
      final doses = doseRows.map(_doseFromRow).toList(growable: false);
      groups.add(
        TodayMemberGroup(
          memberId: member.memberId,
          name: member.name,
          relationship: member.relationship,
          localDate: member.localDate,
          timezone: member.timezone,
          takenCount: doses.where((dose) => dose.status == 'taken').length,
          totalCount: doses.length,
          doses: doses,
        ),
      );
    }
    return groups;
  }

  bool _isFinal(String status) =>
      status == 'taken' || status == 'skipped' || status == 'missed';

  DoseProjection _doseFromRow(CachedDose row) {
    return DoseProjection(
      id: row.doseId,
      scheduleId: row.scheduleId,
      familyMemberId: row.memberId,
      familyMemberName: row.memberName.isEmpty ? null : row.memberName,
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

final todayRepositoryProvider = Provider<TodayRepository>((ref) {
  final userId = ref.watch(authControllerProvider).user?.id ?? '';
  return ApiTodayRepository(
    ref.watch(apiClientProvider),
    ref.watch(appDatabaseProvider),
    userId: userId,
  );
});

final todayProvider = FutureProvider<TodayLoadResult>((ref) {
  return ref.watch(todayRepositoryProvider).loadToday();
});
