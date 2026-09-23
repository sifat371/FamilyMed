import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/history/domain/member_history.dart';
import 'package:familymed/features/history/presentation/correct_record_screen.dart';
import 'package:familymed/features/history/presentation/member_history_screen.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _HistoryRepository implements HistoryRepository {
  @override
  Future<MemberHistory> load(
    String memberId, {
    DateTime? from,
    DateTime? to,
  }) async {
    final scheduled = DateTime.utc(2026, 9, 23, 2);
    return MemberHistory(
      memberId: memberId,
      memberName: 'Amma',
      timezone: 'Asia/Dhaka',
      fromDate: '2026-08-25',
      toDate: '2026-09-23',
      markedAdherencePercentage: '50.00',
      days: [
        HistoryDay(
          localDate: '2026-09-23',
          doses: [
            HistoryDose(
              dose: DoseProjection(
                id: 'dose-1',
                scheduleId: 'schedule-1',
                familyMemberId: memberId,
                memberMedicationId: 'med-1',
                medicationName: 'Metformin',
                strength: '500 mg',
                scheduledAt: scheduled,
                scheduledLocalDate: '2026-09-23',
                scheduledLocalTime: '08:00',
                timezone: 'Asia/Dhaka',
                quantityText: '1',
                unit: 'tablet',
                mealRelation: 'after_food',
                status: 'taken',
                missedAt: DateTime.utc(2026, 9, 23, 18),
                takenAt: DateTime.utc(2026, 9, 23, 12, 12),
                effectiveReminderAt: scheduled,
              ),
              events: [
                DoseHistoryEvent(
                  action: 'missed',
                  occurredAt: DateTime.utc(2026, 9, 23, 18),
                  recordedAt: DateTime.utc(2026, 9, 23, 18),
                  metadata: const {},
                ),
                DoseHistoryEvent(
                  action: 'corrected',
                  occurredAt: DateTime.utc(2026, 9, 23, 19),
                  recordedAt: DateTime.utc(2026, 9, 23, 19),
                  metadata: const {
                    'previous_status': 'missed',
                    'new_status': 'taken',
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _OfflineTransport implements SyncTransport {
  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) {
    throw Exception('offline');
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

Widget _localized(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  testWidgets('history shows marked adherence and preserves correction trail',
      (tester) async {
    await tester.pumpWidget(
      _localized(
        MemberHistoryScreen(
          memberId: 'member-1',
          repository: _HistoryRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Marked adherence'), findsOneWidget);
    expect(find.text('50.00%'), findsOneWidget);
    expect(find.text('Missed'), findsOneWidget);
    expect(find.text('Corrected'), findsOneWidget);
    expect(find.text('Correct record'), findsOneWidget);
  });

  testWidgets('correction queues durable correct action', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final scheduled = DateTime.utc(2026, 9, 23, 2);
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
            scheduledAt: scheduled,
            scheduledLocalDate: '2026-09-23',
            scheduledLocalTime: '08:00',
            timezone: 'Asia/Dhaka',
            status: 'missed',
            missedAt: Value<DateTime?>(DateTime.utc(2026, 9, 23, 18)),
            effectiveReminderAt: scheduled,
            updatedAt: DateTime.utc(2026, 9, 23, 19),
          ),
        );
    final coordinator = SyncCoordinator(
      database: db,
      transport: _OfflineTransport(),
    );
    final repository = DoseRepository(
      database: db,
      syncCoordinator: coordinator,
      notificationScheduler: _Scheduler(),
      idFactory: () => 'correction-1',
    );

    await tester.pumpWidget(
      _localized(
        CorrectRecordScreen(
          doseId: 'dose-1',
          repository: repository,
          initialStatus: 'missed',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Taken'));
    await tester.enterText(
      find.byKey(const Key('effectiveAtField')),
      '2026-09-23T12:12:00Z',
    );
    await tester.tap(find.text('Save correction'));
    await tester.pumpAndSettle();

    final operations = await db.select(db.syncOperations).get();
    expect(operations, hasLength(1));
    expect(operations.single.action, 'correct');
    expect(operations.single.operationId, 'correction-1');
  });
}
