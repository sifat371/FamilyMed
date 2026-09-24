import 'package:familymed/core/notifications/notification_scheduler.dart';
import 'package:familymed/core/notifications/reminder_coordinator.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/family/domain/family_member.dart';
import 'package:familymed/features/family/presentation/member_profile_screen.dart';
import 'package:familymed/features/medications/data/medication_lifecycle_repository.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _member = FamilyMember(
  id: 'member-1',
  name: 'Amma',
  relationship: 'mother',
  preferredLanguage: 'bn',
  timezone: 'Asia/Dhaka',
);

MemberMedication _medication(String status) => MemberMedication(
      id: 'med-1',
      familyMemberId: 'member-1',
      medicineMasterId: null,
      displayName: 'Metformin',
      strength: '500 mg',
      dosageForm: 'tablet',
      status: status,
      startDate: DateTime(2026, 9, 24),
      endDate: null,
    );

class _FamilyRepository implements FamilyRepository {
  @override
  Future<FamilyMember> getMember(String id) async => _member;

  @override
  Future<List<FamilyMember>> listMembers() async => const [_member];

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
  String status = 'active';

  @override
  Future<List<MemberMedication>> listMedications(String memberId) async =>
      [_medication(status)];

  @override
  Future<MemberMedication> getMedication(String id) async =>
      _medication(status);

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

class _LifecycleRepository implements MedicationLifecycleRepository {
  _LifecycleRepository(this.medications);

  final _MedicationRepository medications;

  @override
  Future<MemberMedication> pause(String medicationId) async {
    medications.status = 'paused';
    return _medication('paused');
  }

  @override
  Future<MemberMedication> resume(String medicationId) async {
    medications.status = 'active';
    return _medication('active');
  }

  @override
  Future<MemberMedication> end(String medicationId) async {
    medications.status = 'ended';
    return _medication('ended');
  }
}

class _TodayRepository implements TodayRepository {
  @override
  Future<List<DoseProjection>> cachedReminderDoses() async => const [];

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async =>
      const [];

  @override
  Future<TodayLoadResult> loadToday() async => const TodayLoadResult(
        groups: <TodayMemberGroup>[],
        isOffline: false,
      );
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

Future<void> _pump(
  WidgetTester tester,
  _MedicationRepository medications,
) async {
  final today = _TodayRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyRepositoryProvider.overrideWithValue(_FamilyRepository()),
        medicationRepositoryProvider.overrideWithValue(medications),
        medicationLifecycleRepositoryProvider.overrideWithValue(
          _LifecycleRepository(medications),
        ),
        todayRepositoryProvider.overrideWithValue(today),
        reminderCoordinatorProvider.overrideWithValue(
          ReminderCoordinator(
            todayRepository: today,
            scheduler: _Scheduler(),
          ),
        ),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MemberProfileScreen(memberId: 'member-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('active medication can pause and resume', (tester) async {
    final medications = _MedicationRepository();
    await _pump(tester, medications);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Pause medicine'), findsOneWidget);

    await tester.tap(find.text('Pause medicine'));
    await tester.pumpAndSettle();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.text('Resume medicine'), findsOneWidget);

    await tester.tap(find.text('Resume medicine'));
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Pause medicine'), findsOneWidget);
  });

  testWidgets('ending medication requires confirmation and preserves card',
      (tester) async {
    final medications = _MedicationRepository();
    await _pump(tester, medications);

    await tester.tap(find.text('End medicine'));
    await tester.pumpAndSettle();

    expect(find.text('End this medicine?'), findsOneWidget);
    expect(
      find.text(
        'Future reminders and untouched doses will stop. Existing history will be kept.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'End medicine'));
    await tester.pumpAndSettle();

    expect(find.text('Ended'), findsOneWidget);
    expect(find.text('Pause medicine'), findsNothing);
    expect(find.text('Resume medicine'), findsNothing);
  });
}
