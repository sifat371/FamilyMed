// Opt-in: requires a dedicated disposable test API/database. Creates synthetic
// accounts and leaves them in that database for inspection. Never use production.
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/account/data/account_repository.dart';
import 'package:familymed/features/auth/data/auth_repository.dart';
import 'package:familymed/features/doses/data/dose_repository.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/history/data/history_repository.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/data/medication_lifecycle_repository.dart';
import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/data/notification_preference_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../core/notifications/notification_scheduler_test.dart'
    show FakeNotificationScheduler;

class _Tokens implements TokenStore {
  AuthTokens? value;
  @override
  Future<AuthTokens?> read() async => value;
  @override
  Future<void> write(AuthTokens tokens) async => value = tokens;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  const url = String.fromEnvironment('FAMILYMED_LIVE_TEST_URL');
  test(
    'real repositories persist manual-care path through HTTP and relogin',
    () async {
      // Deliberately restrict this runner to loopback test servers.
      expect(['127.0.0.1', 'localhost'], contains(Uri.parse(url).host));
      tzdata.initializeTimeZones();
      final tokens = _Tokens();
      final events = SessionEvents();
      addTearDown(events.dispose);
      final dio = Dio(BaseOptions(baseUrl: url));
      final client = ApiClient(
        tokenStore: tokens,
        sessionEvents: events,
        dio: dio,
      );
      final auth = ApiAuthRepository(client);
      final email = 'live-${DateTime.now().microsecondsSinceEpoch}@example.com';
      final session = await auth.register(
        name: 'Synthetic caregiver',
        email: email,
        password: 'test-password-123',
      );
      await tokens.write(session.tokens);
      final family = ApiFamilyRepository(client);
      final timezone = DateTime.now().toUtc().hour < 23
          ? 'UTC'
          : 'Pacific/Honolulu';
      final local = tz.TZDateTime.now(tz.getLocation(timezone));
      final member = await family.createMember(
        name: 'Amma fixture',
        relationship: 'mother',
        preferredLanguage: 'en',
        timezone: timezone,
      );
      final medications = ApiMedicationRepository(client);
      final first = await medications.createMedication(
        member.id,
        displayName: 'Metformin',
        strength: '500 mg',
        dosageForm: 'tablet',
        startDate: local,
      );
      final second = await medications.createMedication(
        member.id,
        displayName: 'Amlodipine',
        strength: '5 mg',
        dosageForm: 'tablet',
        startDate: local,
      );
      String clock(DateTime value) =>
          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
      ScheduleDraft draft(List<String> clocks) => ScheduleDraft(
        timezone: timezone,
        startDate: local,
        times: clocks
            .map(
              (time) => ScheduleDraftTime(
                period: 'morning',
                localTime: time,
                quantityText: '1',
                unit: 'tablet',
              ),
            )
            .toList(),
      );
      final schedules = ApiScheduleRepository(client);
      await schedules.createSchedule(
        first.id,
        draft([clock(local), clock(local.add(const Duration(minutes: 1)))]),
      );
      await schedules.createSchedule(second.id, draft([clock(local)]));
      final preferences = ApiNotificationPreferenceRepository(client);
      await preferences.updatePreference(member.id, enabled: false);
      expect((await schedules.getCurrentSchedule(first.id))!.status, 'active');
      final database = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(database.close);
      final today = ApiTodayRepository(
        client,
        database,
        userId: session.user.id,
      );
      final initial = (await today.loadToday()).groups.single;
      expect(initial.totalCount, 3);
      final sync = SyncCoordinator(
        database: database,
        transport: ApiSyncTransport(client),
        userId: session.user.id,
      );
      addTearDown(sync.dispose);
      final doses = DoseRepository(
        database: database,
        syncCoordinator: sync,
        notificationScheduler: FakeNotificationScheduler(),
        userId: session.user.id,
      );
      final firstDoses = initial.doses
          .where((dose) => dose.memberMedicationId == first.id)
          .toList();
      final otherDose = initial.doses.singleWhere(
        (dose) => dose.memberMedicationId == second.id,
      );
      await doses.snooze(
        otherDose.id,
        occurredAt: DateTime.now().toUtc(),
        snoozedUntil: DateTime.now().toUtc().add(const Duration(minutes: 15)),
      );
      expect(
        (await today.loadToday()).groups.single.doses
            .singleWhere((dose) => dose.id == otherDose.id)
            .snoozedUntil,
        isNotNull,
      );
      for (final dose in firstDoses) {
        await doses.markTaken(dose.id, occurredAt: DateTime.now().toUtc());
      }
      expect((await today.loadToday()).groups.single.takenCount, 2);
      await doses.skip(otherDose.id, occurredAt: DateTime.now().toUtc());
      await doses.correct(
        otherDose.id,
        occurredAt: DateTime.now().toUtc(),
        newStatus: 'taken',
        effectiveAt: DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        ),
        reason: 'Synthetic correction',
      );
      expect(await database.select(database.syncOperations).get(), isEmpty);
      final history = await ApiHistoryRepository(client).load(member.id);
      final corrected = history.days
          .expand((day) => day.doses)
          .singleWhere((item) => item.dose.id == otherDose.id);
      expect(
        corrected.events.map((event) => event.action),
        containsAll(['snoozed', 'skipped', 'corrected']),
      );
      expect(corrected.dose.status, 'taken');
      await AccountRepository(
        client,
      ).update(name: 'Saved caregiver', language: 'bn');
      await tokens.clear();
      final restored = await auth.login(
        email: email,
        password: 'test-password-123',
      );
      await tokens.write(restored.tokens);
      expect(restored.user.preferredLanguage, 'bn');
      final freshDatabase = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(freshDatabase.close);
      final freshSync = SyncCoordinator(
        database: freshDatabase,
        transport: ApiSyncTransport(client),
        userId: restored.user.id,
      );
      addTearDown(freshSync.dispose);
      final freshDoses = DoseRepository(
        database: freshDatabase,
        syncCoordinator: freshSync,
        notificationScheduler: FakeNotificationScheduler(),
        userId: restored.user.id,
      );
      final restoredHistory = await ApiHistoryRepository(
        client,
      ).load(member.id);
      final historyDose = restoredHistory.days
          .expand((day) => day.doses)
          .first
          .dose;
      expect(
        await freshDatabase.select(freshDatabase.cachedDoses).get(),
        isEmpty,
      );
      await freshDoses.correct(
        historyDose.id,
        occurredAt: DateTime.now().toUtc(),
        effectiveAt: DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        ),
        newStatus: 'skipped',
        historyDose: historyDose,
      );
      expect(
        await freshDatabase.select(freshDatabase.syncOperations).get(),
        isEmpty,
      );
      final correctedHistory = await ApiHistoryRepository(
        client,
      ).load(member.id);
      expect(
        correctedHistory.days
            .expand((day) => day.doses)
            .singleWhere((item) => item.dose.id == historyDose.id)
            .dose
            .status,
        'skipped',
      );
      await freshDoses.correct(
        historyDose.id,
        occurredAt: DateTime.now().toUtc(),
        effectiveAt: DateTime.now().toUtc().subtract(
          const Duration(seconds: 1),
        ),
        newStatus: 'taken',
        historyDose: historyDose,
      );
      final freshToday = ApiTodayRepository(
        client,
        freshDatabase,
        userId: restored.user.id,
      );
      expect((await freshToday.loadToday()).groups.single.takenCount, 3);
      final lifecycle = ApiMedicationLifecycleRepository(client);
      expect((await lifecycle.pause(first.id)).status, 'paused');
      expect((await lifecycle.resume(first.id)).status, 'active');
      expect((await lifecycle.end(first.id)).status, 'ended');
      expect(
        (await ApiHistoryRepository(client).load(member.id)).days
            .expand((day) => day.doses)
            .where((dose) => dose.dose.status == 'taken')
            .length,
        3,
      );
      final other = await auth.register(
        name: 'Other fixture',
        email: 'other-$email',
        password: 'test-password-123',
      );
      await tokens.write(other.tokens);
      expect(await family.listMembers(), isEmpty);
      await expectLater(
        medications.getMedication(first.id),
        throwsA(
          isA<ApiError>().having((error) => error.statusCode, 'status', 404),
        ),
      );
    },
    skip: url.isEmpty
        ? 'Set FAMILYMED_LIVE_TEST_URL to a disposable local API.'
        : false,
  );
}
