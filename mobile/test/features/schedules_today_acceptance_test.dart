import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/doses/presentation/dose_action_screen.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/family/domain/family_member.dart';
import 'package:familymed/features/family/presentation/member_profile_screen.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:familymed/features/history/presentation/correct_record_screen.dart';
import 'package:familymed/features/history/presentation/member_history_screen.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:familymed/features/schedules/data/notification_preference_repository.dart';
import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:familymed/features/schedules/presentation/enable_reminders_screen.dart';
import 'package:familymed/features/schedules/presentation/set_routine_screen.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:familymed/features/today/presentation/today_screen.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _member = FamilyMember(
  id: 'member-1',
  name: 'Amma',
  relationship: 'mother',
  preferredLanguage: 'bn',
  timezone: 'Asia/Dhaka',
);

final _medication = MemberMedication(
  id: 'med-1',
  familyMemberId: 'member-1',
  medicineMasterId: null,
  displayName: 'Metformin',
  strength: '500 mg',
  dosageForm: 'tablet',
  status: 'draft',
  startDate: DateTime(2026, 9, 23),
  endDate: null,
);

DoseProjection _dose(
  String id,
  String localTime, {
  String status = 'pending',
  DateTime? snoozedUntil,
}) {
  final hour = int.parse(localTime.split(':').first) - 6;
  final scheduled = DateTime.utc(2026, 9, 23, hour < 0 ? hour + 24 : hour);
  return DoseProjection(
    id: id,
    scheduleId: 'schedule-1',
    familyMemberId: 'member-1',
    memberMedicationId: 'med-1',
    medicationName: 'Metformin',
    strength: '500 mg',
    scheduledAt: scheduled,
    scheduledLocalDate: '2026-09-23',
    scheduledLocalTime: localTime,
    timezone: 'Asia/Dhaka',
    quantityText: '1',
    unit: 'tablet',
    mealRelation: 'after_food',
    status: status,
    snoozedUntil: snoozedUntil,
    takenAt: status == 'taken' ? DateTime.utc(2026, 9, 23, 8) : null,
    effectiveReminderAt: snoozedUntil ?? scheduled,
  );
}

class _FamilyRepository implements FamilyRepository {
  @override
  Future<List<FamilyMember>> listMembers() async => const [_member];

  @override
  Future<FamilyMember> getMember(String id) async => _member;

  @override
  Future<FamilyMember> createMember({
    required String name,
    required String relationship,
    DateTime? dateOfBirth,
    required String preferredLanguage,
    required String timezone,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<FamilyMember> updateMember(
    String id, {
    String? name,
    String? relationship,
    DateTime? dateOfBirth,
    String? preferredLanguage,
    String? timezone,
  }) {
    throw UnimplementedError();
  }
}

class _MedicationRepository implements MedicationRepository {
  @override
  Future<List<MemberMedication>> listMedications(String memberId) async =>
      [_medication];

  @override
  Future<MemberMedication> getMedication(String id) async => _medication;

  @override
  Future<MemberMedication> createMedication(
    String memberId, {
    required String displayName,
    String? strength,
    String? dosageForm,
    required DateTime startDate,
    DateTime? endDate,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<MemberMedication> updateMedication(
    String id, {
    String? displayName,
    String? strength,
    String? dosageForm,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    throw UnimplementedError();
  }
}

class _NotificationPreferenceRepository
    implements NotificationPreferenceRepository {
  bool enabled = false;

  @override
  Future<NotificationPreference> getPreference(String memberId) async {
    return NotificationPreference(
      memberId: memberId,
      enabled: enabled,
      defaultSnoozeMinutes: 15,
    );
  }

  @override
  Future<NotificationPreference> updatePreference(
    String memberId, {
    bool? enabled,
    int? defaultSnoozeMinutes,
  }) async {
    this.enabled = enabled ?? this.enabled;
    return NotificationPreference(
      memberId: memberId,
      enabled: this.enabled,
      defaultSnoozeMinutes: defaultSnoozeMinutes ?? 15,
    );
  }
}

class _ScheduleRepository implements ScheduleRepository {
  MedicationSchedule? current;

  @override
  Future<MedicationSchedule?> getCurrentSchedule(String medicationId) async =>
      current;

  @override
  Future<MedicationSchedule> createSchedule(
    String medicationId,
    ScheduleDraft draft,
  ) async {
    current = MedicationSchedule(
      id: 'schedule-1',
      memberMedicationId: medicationId,
      rawInstruction: draft.rawInstruction,
      mealRelation: draft.mealRelation,
      timezone: draft.timezone,
      startDate: draft.startDate,
      status: 'active',
      times: [
        for (var index = 0; index < draft.times.length; index++)
          ScheduleTimeEntry(
            id: 'time-$index',
            period: draft.times[index].period,
            localTime: draft.times[index].localTime,
            quantityText: draft.times[index].quantityText,
            unit: draft.times[index].unit,
            sortOrder: index,
          ),
      ],
    );
    return current!;
  }

  @override
  Future<MedicationSchedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  ) =>
      createSchedule('med-1', draft);
}

class _TodayRepository implements TodayRepository {
  @override
  Future<TodayLoadResult> loadToday() async => TodayLoadResult(
        isOffline: false,
        groups: [
          TodayMemberGroup(
            memberId: 'member-1',
            name: 'Amma',
            relationship: 'mother',
            localDate: '2026-09-23',
            timezone: 'Asia/Dhaka',
            takenCount: 0,
            totalCount: 2,
            doses: [
              _dose('dose-1', '08:00'),
              _dose('dose-2', '20:00'),
            ],
          ),
        ],
      );

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async =>
      [_dose('dose-1', '08:00'), _dose('dose-2', '20:00')];

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async =>
      loadReminderDoses();
}

class _HistoryRepository implements HistoryRepository {
  @override
  Future<MemberHistory> load(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final dose = _dose('dose-1', '08:00', status: 'taken');
    return MemberHistory(
      memberId: memberId,
      memberName: 'Amma',
      timezone: 'Asia/Dhaka',
      fromDate: '2026-08-25',
      toDate: '2026-09-23',
      markedAdherencePercentage: '100.00',
      days: [
        HistoryDay(
          localDate: '2026-09-23',
          doses: [
            HistoryDose(
              dose: dose,
              events: [
                DoseHistoryEvent(
                  action: 'marked_taken',
                  occurredAt: DateTime.utc(2026, 9, 23, 8),
                  recordedAt: DateTime.utc(2026, 9, 23, 8),
                  metadata: const {},
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _Scheduler implements NotificationScheduler {
  @override
  Future<void> cancelDose(String doseId) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> reconcile(List<DoseProjection> doses) async {}

  @override
  Future<void> scheduleDose(DoseProjection dose) async {}

  @override
  Future<void> snoozeDose(DoseProjection dose) async {}
}

class _MutableTransport implements SyncTransport {
  bool online = true;

  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) async {
    if (!online) throw Exception('offline');
    if (operation.action == 'taken') {
      return _dose(operation.doseId, '08:00', status: 'taken');
    }
    if (operation.action == 'snooze') {
      final until = DateTime.parse(
        operation.payload['snoozed_until'].toString(),
      ).toUtc();
      return _dose(
        operation.doseId,
        '20:00',
        status: 'pending',
        snoozedUntil: until,
      );
    }
    if (operation.action == 'correct') {
      return _dose(
        operation.doseId,
        '08:00',
        status: operation.payload['new_status'].toString(),
      );
    }
    return _dose(operation.doseId, '20:00', status: 'skipped');
  }
}

Future<void> _seedDose(
  AppDatabase db,
  DoseProjection dose,
) {
  return db.into(db.cachedDoses).insert(
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
          effectiveReminderAt: dose.effectiveReminderAt,
          updatedAt: DateTime.utc(2026, 9, 23, 7),
        ),
      );
}

void main() {
  testWidgets('golden medication-care path works across online and offline state',
      (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await _seedDose(database, _dose('dose-1', '08:00'));
    await _seedDose(database, _dose('dose-2', '20:00'));

    final transport = _MutableTransport();
    final coordinator = SyncCoordinator(
      database: database,
      transport: transport,
    );
    addTearDown(coordinator.dispose);
    var nextId = 0;
    final doseRepository = DoseRepository(
      database: database,
      syncCoordinator: coordinator,
      notificationScheduler: _Scheduler(),
      idFactory: () => 'action-${++nextId}',
    );
    final scheduleRepository = _ScheduleRepository();
    final historyRepository = _HistoryRepository();

    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/family/member-1',
      routes: [
        GoRoute(
          path: '/family/:memberId',
          builder: (context, state) => MemberProfileScreen(
            memberId: state.pathParameters['memberId']!,
          ),
        ),
        GoRoute(
          path: '/family/:memberId/medications/:medicationId/routine',
          builder: (context, state) => SetRoutineScreen(
            memberId: state.pathParameters['memberId']!,
            medicationId: state.pathParameters['medicationId']!,
          ),
        ),
        GoRoute(
          path: '/family/:memberId/medications/:medicationId/reminders',
          builder: (context, state) => EnableRemindersScreen(
            memberId: state.pathParameters['memberId']!,
          ),
        ),
        GoRoute(
          path: '/today',
          builder: (context, state) => const TodayScreen(),
        ),
        GoRoute(
          path: '/doses/:doseId',
          builder: (context, state) => DoseActionScreen(
            doseId: state.pathParameters['doseId']!,
            repository: doseRepository,
          ),
        ),
        GoRoute(
          path: '/family/:memberId/history',
          builder: (context, state) => MemberHistoryScreen(
            memberId: state.pathParameters['memberId']!,
            repository: historyRepository,
          ),
        ),
        GoRoute(
          path: '/doses/:doseId/correct',
          builder: (context, state) => CorrectRecordScreen(
            doseId: state.pathParameters['doseId']!,
            repository: doseRepository,
            initialStatus: state.uri.queryParameters['status'] ?? 'taken',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyRepositoryProvider.overrideWithValue(_FamilyRepository()),
          medicationRepositoryProvider.overrideWithValue(
            _MedicationRepository(),
          ),
          scheduleRepositoryProvider.overrideWithValue(scheduleRepository),
          notificationPreferenceRepositoryProvider.overrideWithValue(
            _NotificationPreferenceRepository(),
          ),
          todayRepositoryProvider.overrideWithValue(_TodayRepository()),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Amma'), findsOneWidget);
    await tester.tap(find.text('Set routine'));
    await tester.pumpAndSettle();

    expect(
      find.text('Reminder times are not part of the prescription.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('routineInstruction')),
      '1+0+1 PC',
    );
    await tester.ensureVisible(
      find.byKey(const Key('addReminderTimeButton')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addReminderTimeButton')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('routineTime1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('routineTime1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save routine'));
    await tester.pumpAndSettle();

    expect(find.text('Enable reminders'), findsWidgets);
    await tester.tap(find.text('Continue to Today'));
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    await tester.tap(find.byKey(const Key('doseCard-dose-1')));
    await tester.pumpAndSettle();
    expect(
      find.text('Taken status is based on family/user confirmation.'),
      findsOneWidget,
    );

    transport.online = true;
    await tester.tap(find.text('Mark as taken'));
    await tester.pumpAndSettle();
    final taken = await doseRepository.cachedDose('dose-1');
    expect(taken?.status, 'taken');
    expect(await database.select(database.syncOperations).get(), isEmpty);

    router.go('/today');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('doseCard-dose-2')));
    await tester.pumpAndSettle();

    transport.online = false;
    await tester.tap(find.text('Snooze 15 min'));
    await tester.pumpAndSettle();
    var operations = await database.select(database.syncOperations).get();
    expect(operations, hasLength(1));
    expect(operations.single.action, 'snooze');

    transport.online = true;
    await coordinator.drain();
    operations = await database.select(database.syncOperations).get();
    expect(operations, isEmpty);
    expect((await doseRepository.cachedDose('dose-2'))?.status, 'pending');

    router.go('/family/member-1/history');
    await tester.pumpAndSettle();
    expect(find.text('Marked adherence'), findsOneWidget);
    expect(find.text('Correct record'), findsOneWidget);

    await tester.tap(find.text('Correct record'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save correction'));
    await tester.pumpAndSettle();

    expect(await database.select(database.syncOperations).get(), isEmpty);
  });
}
