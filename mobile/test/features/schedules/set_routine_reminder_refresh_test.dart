import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:familymed/features/schedules/presentation/set_routine_screen.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _ScheduleRepository implements ScheduleRepository {
  final schedule = MedicationSchedule(
    id: 'schedule-1',
    memberMedicationId: 'med-1',
    rawInstruction: '1+0+1',
    mealRelation: 'after_food',
    timezone: 'Asia/Dhaka',
    startDate: DateTime(2026, 9, 23),
    status: 'active',
    times: const <ScheduleTimeEntry>[
      ScheduleTimeEntry(
        id: 'time-1',
        period: 'morning',
        localTime: '08:00',
        quantityText: '1',
        unit: 'tablet',
        sortOrder: 0,
      ),
    ],
  );

  @override
  Future<MedicationSchedule?> getCurrentSchedule(String medicationId) async =>
      schedule;

  @override
  Future<MedicationSchedule> createSchedule(
    String medicationId,
    ScheduleDraft draft,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<MedicationSchedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  ) async =>
      schedule;
}

class _TodayRepository implements TodayRepository {
  int reminderLoads = 0;

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async => const [];

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async {
    reminderLoads++;
    final at = DateTime.utc(2026, 9, 24, 3);
    return <DoseProjection>[
      DoseProjection(
        id: 'dose-1',
        scheduleId: 'schedule-1',
        familyMemberId: 'member-1',
        memberMedicationId: 'med-1',
        medicationName: 'Metformin',
        scheduledAt: at,
        scheduledLocalDate: '2026-09-24',
        scheduledLocalTime: '09:00',
        timezone: 'Asia/Dhaka',
        quantityText: '1',
        unit: 'tablet',
        status: 'upcoming',
        effectiveReminderAt: at,
      ),
    ];
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

void main() {
  testWidgets('editing a routine refreshes reminders and returns to Today',
      (tester) async {
    final todayRepository = _TodayRepository();
    final scheduler = _Scheduler();
    late final GoRouter router;
    router = GoRouter(
      initialLocation: '/routine',
      routes: <RouteBase>[
        GoRoute(
          path: '/routine',
          builder: (context, state) => const SetRoutineScreen(
            memberId: 'member-1',
            medicationId: 'med-1',
          ),
        ),
        GoRoute(
          path: '/today',
          builder: (context, state) =>
              const Scaffold(body: Text('Today destination')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scheduleRepositoryProvider.overrideWithValue(_ScheduleRepository()),
          todayRepositoryProvider.overrideWithValue(todayRepository),
          notificationSchedulerProvider.overrideWithValue(scheduler),
        ],
        child: MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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

    await tester.enterText(find.byKey(const Key('routineTime0')), '09:00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save routine'));
    await tester.pumpAndSettle();

    expect(todayRepository.reminderLoads, 1);
    expect(scheduler.reconciled?.map((dose) => dose.id), <String>['dose-1']);
    expect(find.text('Today destination'), findsOneWidget);
  });
}
