import 'package:familymed/core/api/api_error.dart';
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
  ) async {
    updatedDraft = draft;
    throw const ApiError(
      code: 'TEST_STOP',
      message: 'Captured update draft.',
      statusCode: 500,
    );
  }
}

Widget _app(_FakeScheduleRepository repository) {
  return ProviderScope(
    overrides: [
      scheduleRepositoryProvider.overrideWithValue(repository),
    ],
    child: const MaterialApp(
      locale: Locale('en'),
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: <Locale>[Locale('en'), Locale('bn')],
      home: SetRoutineScreen(
        memberId: 'member-1',
        medicationId: 'med-1',
      ),
    ),
  );
}

void main() {
  testWidgets('routine screen separates reminder times from prescription text',
      (tester) async {
    await tester.pumpWidget(_app(_FakeScheduleRepository()));
    await tester.pumpAndSettle();

    expect(
      find.text('Reminder times are not part of the prescription.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('routineInstruction')), findsOneWidget);
    expect(find.byKey(const Key('routineTime0')), findsOneWidget);
  });

  testWidgets('editing routine preserves existing timezone and date boundaries',
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

    await tester.enterText(find.byKey(const Key('routineTime0')), '09:00');
    await tester.tap(find.widgetWithText(FilledButton, 'Save routine'));
    await tester.pumpAndSettle();

    final draft = repository.updatedDraft;
    expect(draft, isNotNull);
    expect(draft!.timezone, 'Asia/Kolkata');
    expect(draft.startDate, DateTime(2026, 1, 10));
    expect(draft.endDate, DateTime(2026, 12, 20));
  });
}
