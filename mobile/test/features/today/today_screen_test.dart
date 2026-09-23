import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:familymed/features/today/presentation/today_screen.dart';
import 'package:familymed/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTodayRepository implements TodayRepository {
  FakeTodayRepository(this.result);

  final TodayLoadResult result;

  @override
  Future<TodayLoadResult> loadToday() async => result;

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async =>
      result.groups.expand((group) => group.doses).toList(growable: false);

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async =>
      result.groups.expand((group) => group.doses).toList(growable: false);
}

DoseProjection dose({
  required String id,
  required String name,
  required String status,
  required String localTime,
}) {
  return DoseProjection(
    id: id,
    scheduleId: 'schedule-$id',
    familyMemberId: 'member-1',
    memberMedicationId: 'med-$id',
    medicationName: name,
    strength: name == 'Metformin' ? '500 mg' : '5 mg',
    scheduledAt: DateTime.utc(2026, 9, 23, 2),
    scheduledLocalDate: '2026-09-23',
    scheduledLocalTime: localTime,
    timezone: 'Asia/Dhaka',
    quantityText: '1',
    unit: 'tablet',
    mealRelation: 'after_food',
    status: status,
    effectiveReminderAt: DateTime.utc(2026, 9, 23, 2),
  );
}

TodayLoadResult result({required bool offline}) {
  return TodayLoadResult(
    isOffline: offline,
    groups: [
      TodayMemberGroup(
        memberId: 'member-1',
        name: 'Amma',
        relationship: 'mother',
        localDate: '2026-09-23',
        timezone: 'Asia/Dhaka',
        takenCount: 2,
        totalCount: 3,
        doses: [
          dose(id: '1', name: 'Metformin', status: 'taken', localTime: '08:00'),
          dose(id: '2', name: 'Amlodipine', status: 'taken', localTime: '08:00'),
          dose(id: '3', name: 'Metformin', status: 'pending', localTime: '20:00'),
        ],
      ),
    ],
  );
}

Future<void> pumpToday(
  WidgetTester tester, {
  required TodayLoadResult loadResult,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository(loadResult)),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TodayScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

TodayLoadResult emptyResult() {
  return const TodayLoadResult(
    isOffline: false,
    groups: <TodayMemberGroup>[],
  );
}

void main() {
  testWidgets('renders family dose summary with text statuses', (tester) async {
    await pumpToday(tester, loadResult: result(offline: false));

    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('2 / 3 marked taken'), findsOneWidget);
    expect(find.text('Metformin 500 mg'), findsNWidgets(2));
    expect(find.text('Taken'), findsNWidgets(2));
    expect(find.text('Pending'), findsOneWidget);
  });

  testWidgets('empty Today offers Family setup actions', (tester) async {
    await pumpToday(tester, loadResult: emptyResult());

    expect(find.text('No doses scheduled for today.'), findsOneWidget);
    expect(find.byKey(const Key('openFamilyButton')), findsOneWidget);
    expect(find.byKey(const Key('addFamilyMemberFromTodayButton')), findsOneWidget);
  });

  testWidgets('renders cached today with offline indicator', (tester) async {
    await pumpToday(tester, loadResult: result(offline: true));

    expect(find.text('Offline — showing saved doses'), findsOneWidget);
    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
  });
}
