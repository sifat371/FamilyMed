import 'package:familymed/core/notifications/notification_providers.dart';
import 'package:familymed/core/theme/familymed_theme.dart';
import 'package:familymed/features/schedules/data/notification_preference_repository.dart';
import 'package:familymed/features/schedules/presentation/enable_reminders_screen.dart';
import 'package:familymed/features/schedules/presentation/set_routine_screen.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'medications/manual_medication_flow_test.dart' as fixtures;
import '../core/notifications/notification_scheduler_test.dart'
    show FakeNotificationScheduler;

class _Preferences implements NotificationPreferenceRepository {
  bool fail = false;
  bool enabled = false;
  int writes = 0;
  @override
  Future<NotificationPreference> getPreference(String memberId) async =>
      NotificationPreference(
        memberId: memberId,
        enabled: enabled,
        defaultSnoozeMinutes: 15,
      );
  @override
  Future<NotificationPreference> updatePreference(
    String memberId, {
    bool? enabled,
    int? defaultSnoozeMinutes,
  }) async {
    writes++;
    if (fail) throw Exception('Offline');
    this.enabled = enabled ?? this.enabled;
    return getPreference(memberId);
  }
}

void main() {
  for (final locale in ['en', 'bn']) {
    for (final size in [
      const Size(360, 800),
      const Size(390, 844),
      const Size(480, 960),
    ]) {
      testWidgets('routine and reminders fit $locale $size at large text', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final medications = fixtures.RecordingMedicationRepository()
          ..medications.add(
            MemberMedication(
              id: 'med-1',
              familyMemberId: 'member-id',
              medicineMasterId: null,
              displayName: 'Metformin',
              strength: '500 mg',
              dosageForm: 'tablet',
              status: 'draft',
              startDate: DateTime(2026, 10, 8),
              endDate: null,
            ),
          );
        final container = fixtures.makeContainer(
          medications,
          overrides: [
            notificationPreferenceRepositoryProvider.overrideWithValue(
              _Preferences(),
            ),
          ],
        );
        addTearDown(container.dispose);
        Widget app(Widget screen) => UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: FamilyMedTheme.light,
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!,
            ),
            home: screen,
          ),
        );
        await tester.pumpWidget(
          app(
            const SetRoutineScreen(
              memberId: 'member-id',
              medicationId: 'med-1',
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          app(const EnableRemindersScreen(memberId: 'member-id')),
        );
        await tester.pumpAndSettle();
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -600),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'permission denial never enables preference; failed writes are retryable',
    (tester) async {
      final preferences = _Preferences()..fail = true;
      final scheduler = FakeNotificationScheduler();
      final container = fixtures.makeContainer(
        fixtures.RecordingMedicationRepository(),
        overrides: [
          notificationPreferenceRepositoryProvider.overrideWithValue(
            preferences,
          ),
          notificationSchedulerProvider.overrideWithValue(scheduler),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const EnableRemindersScreen(memberId: 'member-id'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.widgetWithText(FilledButton, 'Enable reminders');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(preferences.writes, 0);
      scheduler.permission = true;
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(preferences.writes, 1);
      expect(preferences.enabled, isFalse);
      expect(tester.takeException(), isNull);
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    },
  );
}
