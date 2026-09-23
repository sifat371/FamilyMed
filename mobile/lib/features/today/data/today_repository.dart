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
  ApiTodayRepository(this._client, this._database);

  final ApiClient _client;
  final AppDatabase _database;

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
      return TodayLoadResult(groups: groups, isOffline: false);
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
      final doses = response.data!
          .map(
            (item) => DoseProjection.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      await _database.transaction(() async {
        for (final dose in doses) {
          await _upsertDose(dose);
        }
      });
      return doses;
    } on ApiError catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) rethrow;
      return cachedReminderDoses();
    }
  }

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async {
    final rows = await (_database.select(_database.cachedDoses)
          ..where((row) => row.status.isNotIn(<String>['taken', 'skipped', 'missed']))
          ..orderBy([
            (row) => OrderingTerm.asc(row.effectiveReminderAt),
          ]))
        .get();
    return rows.map(_doseFromRow).toList(growable: false);
  }

  Future<void> _replaceTodayCache(List<TodayMemberGroup> groups) async {
    await _database.transaction(() async {
      await _database.delete(_database.cachedTodayMembers).go();
      for (final group in groups) {
        await _database.into(_database.cachedTodayMembers).insertOnConflictUpdate(
              CachedTodayMembersCompanion.insert(
                memberId: group.memberId,
                name: group.name,
                relationship: group.relationship,
                localDate: group.localDate,
                timezone: group.timezone,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
        await (_database.delete(_database.cachedDoses)
              ..where(
                (row) =>
                    row.memberId.equals(group.memberId) &
                    row.scheduledLocalDate.equals(group.localDate),
              ))
            .go();
        for (final dose in group.doses) {
          await _upsertDose(dose);
        }
      }
    });
  }

  Future<void> _upsertDose(DoseProjection dose) {
    return _database.into(_database.cachedDoses).insertOnConflictUpdate(
          CachedDosesCompanion.insert(
            doseId: dose.id,
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

  Future<List<TodayMemberGroup>> _readTodayCache() async {
    final memberRows = await _database.select(_database.cachedTodayMembers).get();
    final groups = <TodayMemberGroup>[];
    for (final member in memberRows) {
      final doseRows = await (_database.select(_database.cachedDoses)
            ..where(
              (row) =>
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

  DoseProjection _doseFromRow(CachedDose row) {
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

final todayRepositoryProvider = Provider<TodayRepository>((ref) {
  return ApiTodayRepository(
    ref.watch(apiClientProvider),
    ref.watch(appDatabaseProvider),
  );
});

final todayProvider = FutureProvider<TodayLoadResult>((ref) {
  return ref.watch(todayRepositoryProvider).loadToday();
});
