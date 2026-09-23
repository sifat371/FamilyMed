import 'package:familymed/app/app.dart';
import 'package:familymed/app/router.dart';
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

class FamilyAuthRepository implements AuthRepository {
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

class RecordingFamilyRepository implements FamilyRepository {
  RecordingFamilyRepository([List<FamilyMember> members = const []])
      : members = List<FamilyMember>.from(members);

  final List<FamilyMember> members;
  String? createdName;
  String? createdRelationship;
  DateTime? createdDateOfBirth;
  String? createdPreferredLanguage;
  String? createdTimezone;

  @override
  Future<FamilyMember> createMember({
    required String name,
    required String relationship,
    DateTime? dateOfBirth,
    required String preferredLanguage,
    required String timezone,
  }) async {
    createdName = name;
    createdRelationship = relationship;
    createdDateOfBirth = dateOfBirth;
    createdPreferredLanguage = preferredLanguage;
    createdTimezone = timezone;
    final member = FamilyMember(
      id: 'created-member',
      name: name,
      relationship: relationship,
      dateOfBirth: dateOfBirth,
      preferredLanguage: preferredLanguage,
      timezone: timezone,
    );
    members.add(member);
    return member;
  }

  @override
  Future<FamilyMember> getMember(String id) async {
    return members.firstWhere((member) => member.id == id);
  }

  @override
  Future<List<FamilyMember>> listMembers() async => List.unmodifiable(members);

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

class EmptyMedicationRepository implements MedicationRepository {
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
  Future<MemberMedication> getMedication(String id) {
    throw UnimplementedError();
  }

  @override
  Future<List<MemberMedication>> listMedications(String memberId) async => const [];

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

ProviderContainer makeContainer(RecordingFamilyRepository repository) {
  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(StoredTokenStore()),
      authRepositoryProvider.overrideWithValue(FamilyAuthRepository()),
      familyRepositoryProvider.overrideWithValue(repository),
      medicationRepositoryProvider.overrideWithValue(EmptyMedicationRepository()),
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
  testWidgets('care-for screen shows choices and parent pre-fills parent', (tester) async {
    final repository = RecordingFamilyRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/care-for');
    await tester.pumpAndSettle();

    expect(find.text('Who do you care for?'), findsOneWidget);
    expect(find.text('My parent'), findsOneWidget);
    expect(find.text('My spouse'), findsOneWidget);
    expect(find.text('My child'), findsOneWidget);
    expect(find.text('Myself'), findsOneWidget);
    expect(find.text('Someone else'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(currentPath(container), '/family/new');
    final relationship = tester.widget<TextFormField>(
      find.byKey(const Key('familyRelationship')),
    );
    expect(relationship.controller?.text, 'parent');
  });

  testWidgets('adding Amma submits Bangla and Asia Dhaka defaults', (tester) async {
    final repository = RecordingFamilyRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/new?relationship=mother');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('familyName')), 'Amma');
    await tester.tap(find.widgetWithText(FilledButton, 'Add family member'));
    await tester.pumpAndSettle();

    expect(repository.createdName, 'Amma');
    expect(repository.createdRelationship, 'mother');
    expect(repository.createdPreferredLanguage, 'bn');
    expect(repository.createdTimezone, 'Asia/Dhaka');
    expect(currentPath(container), '/family/created-member');
  });

  testWidgets('date of birth picker does not allow future dates', (tester) async {
    final repository = RecordingFamilyRepository();
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/new?relationship=mother');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('familyDob')));
    await tester.pumpAndSettle();

    final dialog = tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(dialog.lastDate, today);
    expect(repository.createdName, isNull);
  });

  testWidgets('family list renders member cards and opens profile', (tester) async {
    final repository = RecordingFamilyRepository(const [amma]);
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family');
    await tester.pumpAndSettle();

    expect(find.text('Your family'), findsOneWidget);
    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('Add family member'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);

    await tester.tap(find.text('Amma'));
    await tester.pumpAndSettle();
    expect(currentPath(container), '/family/member-id');
  });

  testWidgets('bottom navigation switches between Today and Family', (tester) async {
    final repository = RecordingFamilyRepository(const [amma]);
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    expect(currentPath(container), '/today');
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.byKey(const Key('familyTab')));
    await tester.pumpAndSettle();
    expect(currentPath(container), '/family');

    await tester.tap(find.byKey(const Key('todayTab')));
    await tester.pumpAndSettle();
    expect(currentPath(container), '/today');
  });

  testWidgets('member profile shows identity empty state and disabled scan', (tester) async {
    final repository = RecordingFamilyRepository(const [amma]);
    final container = makeContainer(repository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family/member-id');
    await tester.pumpAndSettle();

    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('mother'), findsOneWidget);
    expect(find.text('No medicines yet'), findsOneWidget);
    expect(find.text('Scan prescription — coming soon'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    final scanButton = tester.widget<FilledButton>(
      find.byKey(const Key('scanPrescriptionButton')),
    );
    expect(scanButton.onPressed, isNull);
  });
}
