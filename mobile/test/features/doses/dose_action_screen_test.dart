import 'package:drift/native.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/doses/presentation/dose_action_screen.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _OfflineTransport implements SyncTransport {
  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) {
    throw Exception('offline');
  }
}

class _FakeScheduler implements NotificationScheduler {
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

Future<DoseRepository> _repository() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  await db.customInsert(
    'INSERT INTO cached_doses '
    '(dose_id, schedule_id, member_id, medication_id, medication_name, '
    'strength, quantity_text, unit, meal_relation, scheduled_at, '
    'scheduled_local_date, scheduled_local_time, timezone, status, '
    'effective_reminder_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('dose-1'),
      const Variable<String>('schedule-1'),
      const Variable<String>('member-1'),
      const Variable<String>('med-1'),
      const Variable<String>('Metformin'),
      const Variable<String>('500 mg'),
      const Variable<String>('1'),
      const Variable<String>('tablet'),
      const Variable<String>('after_food'),
      Variable<DateTime>(DateTime.utc(2026, 9, 23, 14)),
      const Variable<String>('2026-09-23'),
      const Variable<String>('20:00'),
      const Variable<String>('Asia/Dhaka'),
      const Variable<String>('pending'),
      Variable<DateTime>(DateTime.utc(2026, 9, 23, 14)),
      Variable<DateTime>(DateTime.utc(2026, 9, 23, 13)),
    ],
  );
  return DoseRepository(
    database: db,
    syncCoordinator: SyncCoordinator(database: db, transport: _OfflineTransport()),
    notificationScheduler: _FakeScheduler(),
    idFactory: () => 'action-1',
  );
}

void main() {
  testWidgets('pending dose shows confirmation-safe actions', (tester) async {
    final repository = await _repository();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: DoseActionScreen(
          doseId: 'dose-1',
          repository: repository,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(
      find.text('Taken status is based on family/user confirmation.'),
      findsOneWidget,
    );
    expect(find.text('Mark as taken'), findsOneWidget);
    expect(find.text('Snooze 15 min'), findsOneWidget);
    expect(find.text('Skip this dose'), findsOneWidget);
  });
}
