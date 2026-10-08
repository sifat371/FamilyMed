import 'package:familymed/core/api/api_error.dart';
import '../medications/manual_medication_flow_test.dart' as fixtures;
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/schedules/data/schedule_repository.dart';
import 'package:familymed/features/schedules/domain/medication_schedule.dart';
import 'package:familymed/features/schedules/presentation/set_routine_screen.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeScheduleRepository implements ScheduleRepository {
  _FakeScheduleRepository({this.schedule});

  final MedicationSchedule? schedule;
  ScheduleDraft? updatedDraft;
  bool failLoad = false;

  @override
  Future<MedicationSchedule?> getCurrentSchedule(String medicationId) async {
    if (failLoad) {
      throw const ApiError(code: 'NETWORK_ERROR', message: 'Offline');
    }
    return schedule;
  }

  @override
  Future<MedicationSchedule> createSchedule(
    String medicationId,
    ScheduleDraft draft,
  ) async {
    updatedDraft = draft;
    throw const ApiError(code: 'TEST_STOP', message: 'Captured create draft.');
  }

  @override
  Future<MedicationSchedule> updateSchedule(
    String scheduleId,
    ScheduleDraft draft,
  ) async {
    updatedDraft = draft;
    throw const ApiError(
      code: 'TEST_STOP',
      message: 'Captured update draft.',
      statusCode: 500,
    );
  }
}

Widget _app(
  _FakeScheduleRepository repository, {
  Locale locale = const Locale('en'),
}) {
  return ProviderScope(
    overrides: [
      familyRepositoryProvider.overrideWithValue(
        fixtures.MedicationFamilyRepository(),
      ),
      medicationRepositoryProvider.overrideWithValue(
        fixtures.RecordingMedicationRepository()
          ..medications.add(
            MemberMedication(
              id: 'med-1',
              familyMemberId: 'member-1',
              medicineMasterId: null,
              displayName: 'Test medicine',
              strength: null,
              dosageForm: null,
              status: 'draft',
              startDate: DateTime(2027, 2, 1),
              endDate: DateTime(2027, 3, 1),
            ),
          ),
      ),
      scheduleRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: <Locale>[Locale('en'), Locale('bn')],
      home: const SetRoutineScreen(memberId: 'member-1', medicationId: 'med-1'),
    ),
  );
}

void main() {
  testWidgets('new routine preserves medication dates and member timezone', (
    tester,
  ) async {
    final repository = _FakeScheduleRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save routine'));
    await tester.pumpAndSettle();
    expect(repository.updatedDraft!.startDate, DateTime(2027, 2, 1));
    expect(repository.updatedDraft!.endDate, DateTime(2027, 3, 1));
    expect(repository.updatedDraft!.timezone, fixtures.amma.timezone);
  });

  testWidgets('failed lookup blocks save until a successful retry', (
    tester,
  ) async {
    final repository = _FakeScheduleRepository()..failLoad = true;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save routine'),
          )
          .onPressed,
      isNull,
    );
    expect(repository.updatedDraft, isNull);
    repository.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save routine'),
          )
          .onPressed,
      isNotNull,
    );
  });
  testWidgets(
    'routine screen separates reminder times from prescription text',
    (tester) async {
      await tester.pumpWidget(_app(_FakeScheduleRepository()));
      await tester.pumpAndSettle();

      expect(
        find.text('Reminder times are not part of the prescription.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('routineInstruction')), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('routineTime0')), findsOneWidget);
    },
  );

  testWidgets(
    'editing routine preserves existing timezone and date boundaries',
    (tester) async {
      final repository = _FakeScheduleRepository(
        schedule: MedicationSchedule(
          id: 'schedule-1',
          memberMedicationId: 'med-1',
          rawInstruction: '1+0+1 PC',
          mealRelation: 'after_food',
          timezone: 'Asia/Kolkata',
          startDate: DateTime(2026, 1, 10),
          endDate: DateTime(2026, 12, 20),
          status: 'active',
          times: const [
            ScheduleTimeEntry(
              id: 'time-1',
              period: 'morning',
              localTime: '08:00',
              quantityText: '1',
              unit: 'tablet',
              sortOrder: 0,
            ),
          ],
        ),
      );
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save routine'));
      await tester.pumpAndSettle();

      final draft = repository.updatedDraft;
      expect(draft, isNotNull);
      expect(draft!.timezone, 'Asia/Kolkata');
      expect(draft.startDate, DateTime(2026, 1, 10));
      expect(draft.endDate, DateTime(2026, 12, 20));
    },
  );
  testWidgets('routine meal relation choices use localized labels', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeScheduleRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unspecified'));
    await tester.pumpAndSettle();

    expect(find.text('Before food'), findsOneWidget);
    expect(find.text('After food'), findsOneWidget);
    expect(find.text('With food'), findsOneWidget);
    expect(find.text('No meal relation'), findsOneWidget);
    expect(find.text('before_food'), findsNothing);
    expect(find.text('after_food'), findsNothing);
  });

  testWidgets('duplicate reminder validation is localized in Bangla', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_FakeScheduleRepository(), locale: const Locale('bn')),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('addReminderTimeButton')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('addReminderTimeButton')));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'রুটিন সংরক্ষণ করুন'));
    await tester.pump();

    expect(find.text('রিমাইন্ডারের সময়গুলো আলাদা হতে হবে।'), findsOneWidget);
    expect(find.text('Reminder times must be unique.'), findsNothing);
  });
}
