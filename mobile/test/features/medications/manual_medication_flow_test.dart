import 'dart:async';

import 'package:familymed/app/app.dart';
import 'package:familymed/app/router.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/features/auth/data/auth_repository.dart';
import 'package:familymed/features/auth/domain/auth_session.dart';
import 'package:familymed/features/auth/domain/current_user.dart';
import 'package:familymed/features/family/data/family_repository.dart';
import 'package:familymed/features/family/domain/family_member.dart';
import 'package:familymed/features/medications/data/medication_repository.dart';
import 'package:familymed/features/medications/domain/member_medication.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const currentUser = CurrentUser(
  id: 'user-id',
  name: 'Sifat',
  email: 'sifat@example.com',
  preferredLanguage: 'en',
  timezone: 'Asia/Dhaka',
);

const amma = FamilyMember(
  id: 'member-id',
  name: 'Amma',
  relationship: 'mother',
  preferredLanguage: 'bn',
  timezone: 'Asia/Dhaka',
);

class StoredTokenStore implements TokenStore {
  AuthTokens? tokens = const AuthTokens(
    accessToken: 'access',
    refreshToken: 'refresh',
  );

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

class MedicationAuthRepository implements AuthRepository {
  @override
  Future<AuthSession> login({required String email, required String password}) {
    throw UnimplementedError();
  }

  @override
  Future<CurrentUser> me() async => currentUser;

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) {
    throw UnimplementedError();
  }
}

class MedicationFamilyRepository implements FamilyRepository {
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
  Future<FamilyMember> getMember(String id) async => amma;

  @override
  Future<List<FamilyMember>> listMembers() async => const [amma];

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

class RecordingMedicationRepository implements MedicationRepository {
  final List<MemberMedication> medications = [];
  ApiError? createError;
  Completer<void>? createGate;
  int createCalls = 0;

  @override
  Future<MemberMedication> createMedication(
    String memberId, {
    required String displayName,
    String? strength,
    String? dosageForm,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    createCalls++;
    if (createGate != null) await createGate!.future;
    if (createError != null) throw createError!;
    final medication = MemberMedication(
      id: 'med-${medications.length + 1}',
      familyMemberId: memberId,
      medicineMasterId: null,
      displayName: displayName,
      strength: strength,
      dosageForm: dosageForm,
      status: 'draft',
      startDate: startDate,
      endDate: endDate,
    );
    medications.add(medication);
    return medication;
  }

  @override
  Future<MemberMedication> getMedication(String id) async {
    return medications.firstWhere((item) => item.id == id);
  }

  @override
  Future<List<MemberMedication>> listMedications(String memberId) async {
    return medications.where((item) => item.familyMemberId == memberId).toList();
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

class EmptyTodayRepository implements TodayRepository {
  @override
  Future<List<DoseProjection>> cachedReminderDoses() async => const [];

  @override
  Future<TodayLoadResult> loadToday() async => const TodayLoadResult(
        groups: <TodayMemberGroup>[],
        isOffline: false,
      );

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async =>
      const [];
}

ProviderContainer makeContainer(RecordingMedicationRepository repository) {
  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(StoredTokenStore()),
      authRepositoryProvider.overrideWithValue(MedicationAuthRepository()),
      familyRepositoryProvider.overrideWithValue(MedicationFamilyRepository()),
      medicationRepositoryProvider.overrideWithValue(repository),
      todayRepositoryProvider.overrideWithValue(EmptyTodayRepository()),
    ],
  );
}

Future<void> pumpApp(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const FamilyMedApp(locale: Locale('en')),
    ),
  );
  await tester.pumpAndSettle();
}

String currentPath(ProviderContainer container) {
  return container.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
}

void main() {
  testWidgets('profile exposes active Add manually action', (tester) async {
    final repository = RecordingMedicationRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add manually'));
    await tester.pumpAndSettle();

    expect(find.text('Add medication manually'), findsOneWidget);
    expect(find.byKey(const Key('medicationName')), findsOneWidget);
  });

  testWidgets('manual form requires name and defaults start date to today', (tester) async {
    final repository = RecordingMedicationRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id/medications/new');
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final expected = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final startField = tester.widget<TextFormField>(
      find.byKey(const Key('medicationStartDate')),
    );
    expect(startField.controller?.text, expected);

    await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
    await tester.pumpAndSettle();
    expect(find.text('This field is required.'), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets('end date before start date blocks submit', (tester) async {
    final repository = RecordingMedicationRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id/medications/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medicationName')), 'Metformin');
    await tester.enterText(find.byKey(const Key('medicationStartDate')), '2026-09-23');
    await tester.enterText(find.byKey(const Key('medicationEndDate')), '2026-09-22');
    await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
    await tester.pumpAndSettle();

    expect(find.text('End date cannot be before start date.'), findsOneWidget);
    expect(repository.createCalls, 0);
  });

  testWidgets('network failure retains all entered medication values', (tester) async {
    final repository = RecordingMedicationRepository()
      ..createError = const ApiError(
        code: 'NETWORK_ERROR',
        message: 'Could not connect. Try again.',
      );
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id/medications/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medicationName')), 'Metformin');
    await tester.enterText(find.byKey(const Key('medicationStrength')), '500 mg');
    await tester.enterText(find.byKey(const Key('medicationDosageForm')), 'tablet');
    await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
    await tester.pumpAndSettle();

    expect(find.text('Could not connect. Try again.'), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('500 mg'), findsOneWidget);
    expect(find.text('tablet'), findsOneWidget);
  });

  testWidgets('loading state blocks duplicate medication submit', (tester) async {
    final repository = RecordingMedicationRepository()..createGate = Completer<void>();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id/medications/new');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medicationName')), 'Metformin');
    await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(repository.createCalls, 1);

    repository.createGate!.complete();
    await tester.pumpAndSettle();
    expect(repository.createCalls, 1);
  });

  testWidgets('successful create returns to profile and refreshes medication list', (tester) async {
    final repository = RecordingMedicationRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add manually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('medicationName')), 'Metformin');
    await tester.enterText(find.byKey(const Key('medicationStrength')), '500 mg');
    await tester.enterText(find.byKey(const Key('medicationDosageForm')), 'tablet');
    await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
    await tester.pumpAndSettle();

    expect(currentPath(container), '/family/member-id');
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('500 mg • tablet'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });

  testWidgets('manual medication form does not contain scheduling inputs', (tester) async {
    final repository = RecordingMedicationRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id/medications/new');
    await tester.pumpAndSettle();

    expect(find.text('Frequency'), findsNothing);
    expect(find.text('Reminder time'), findsNothing);
    expect(find.text('Meal relation'), findsNothing);
  });
}
