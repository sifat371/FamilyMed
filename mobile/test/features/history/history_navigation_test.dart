import 'package:drift/native.dart';
import 'package:familymed/app/app.dart';
import 'package:familymed/app/router.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:familymed/features/history/presentation/correct_record_screen.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../core/notifications/notification_scheduler_test.dart'
    show FakeNotificationScheduler;
import '../medications/manual_medication_flow_test.dart' as fixtures;

class _HistoryServer implements HistoryRepository, SyncTransport {
  int loads = 0;
  int corrections = 0;
  bool failRefresh = false;
  DoseProjection dose = DoseProjection(
    id: 'historical-dose',
    scheduleId: 'schedule',
    familyMemberId: 'member-id',
    memberMedicationId: 'medicine',
    medicationName: 'History medicine',
    scheduledAt: DateTime.utc(2026, 9, 23, 2),
    scheduledLocalDate: '2026-09-23',
    scheduledLocalTime: '08:00',
    timezone: 'Asia/Dhaka',
    quantityText: '1',
    unit: 'tablet',
    status: 'taken',
    effectiveReminderAt: DateTime.utc(2026, 9, 23, 2),
  );

  @override
  Future<MemberHistory> load(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    loads++;
    if (failRefresh) throw Exception('History unavailable');
    return MemberHistory(
      memberId: memberId,
      memberName: 'Amma',
      timezone: 'Asia/Dhaka',
      fromDate: '2026-09-01',
      toDate: '2026-10-09',
      markedAdherencePercentage: null,
      days: [
        HistoryDay(
          localDate: '2026-09-23',
          doses: [HistoryDose(dose: dose, events: const [])],
        ),
      ],
    );
  }

  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) async {
    expect(operation.action, 'correct');
    corrections++;
    dose = dose.copyWith(status: operation.payload['new_status'] as String);
    return dose;
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _HistoryServer server, {
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final scheduler = FakeNotificationScheduler();
  final sync = SyncCoordinator(
    database: db,
    transport: server,
    userId: fixtures.currentUser.id,
  );
  addTearDown(sync.dispose);
  final container = fixtures.makeContainer(
    fixtures.RecordingMedicationRepository(),
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      notificationSchedulerProvider.overrideWithValue(scheduler),
      syncCoordinatorProvider.overrideWithValue(sync),
      historyRepositoryProvider.overrideWithValue(server),
      doseRepositoryProvider.overrideWithValue(
        DoseRepository(
          database: db,
          syncCoordinator: sync,
          notificationScheduler: scheduler,
          userId: fixtures.currentUser.id,
        ),
      ),
    ],
  );
  addTearDown(container.dispose);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: FamilyMedApp(locale: locale),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final path in ['/history', '/family/member-id/history']) {
    for (final save in [true, false]) {
      testWidgets(
        '$path correction ${save ? 'saves and refreshes' : 'cancels and returns'} through real routes',
        (tester) async {
          final server = _HistoryServer();
          final container = await _pump(tester, server);
          container.read(routerProvider).go(path);
          await tester.pumpAndSettle();
          final before = server.loads;
          await tester.ensureVisible(find.text('Correct record'));
          await tester.tap(find.text('Correct record'));
          await tester.pumpAndSettle();
          expect(find.byType(CorrectRecordScreen), findsOneWidget);
          expect(find.byType(NavigationBar), findsNothing);
          if (save) {
            await tester.tap(find.text('Skipped'));
            await tester.ensureVisible(find.text('Save correction'));
            await tester.tap(find.text('Save correction'));
          } else {
            await tester.tap(find.byType(BackButton));
          }
          await tester.pumpAndSettle();
          expect(find.byType(CorrectRecordScreen), findsNothing);
          expect(
            container
                .read(routerProvider)
                .routeInformationProvider
                .value
                .uri
                .path,
            path,
          );
          expect(server.loads, greaterThan(before));
          expect(server.corrections, save ? 1 : 0);
          expect(
            find.textContaining(save ? 'Skipped' : 'Taken'),
            findsOneWidget,
          );
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            2,
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'failed history refresh after correction offers retry without uncaught errors',
    (tester) async {
      final server = _HistoryServer();
      final container = await _pump(tester, server);
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correct record'));
      await tester.pumpAndSettle();
      server.failRefresh = true;
      await tester.tap(find.text('Skipped'));
      await tester.tap(find.text('Save correction'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Retry'), findsOneWidget);
      server.failRefresh = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Skipped'), findsOneWidget);
      expect(server.corrections, 1);
    },
  );

  for (final locale in ['en', 'bn']) {
    testWidgets('compact $locale navigation remains usable with large text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = await _pump(
        tester,
        _HistoryServer(),
        locale: Locale(locale),
        scale: 1.5,
      );
      for (final entry in {
        'familyTab': 1,
        'historyTab': 2,
        'meTab': 3,
        'todayTab': 0,
      }.entries) {
        await tester.tap(find.byKey(Key(entry.key)));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          entry.value,
        );
        expect(tester.takeException(), isNull);
      }
      container.read(routerProvider).go('/history');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(NavigationBar));
      final l10n = AppLocalizations.of(context);
      await tester.scrollUntilVisible(
        find.text(l10n.correctRecord),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.correctRecord));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(l10n.saveCorrection),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.saveCorrection).hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('historyTab')).hitTestable(), findsOneWidget);
    });
  }
}
