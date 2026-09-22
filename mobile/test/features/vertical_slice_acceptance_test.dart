import 'package:familymed/app/app.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const user = CurrentUser(
  id: 'user-id',
  name: 'Sifat',
  email: 'sifat@example.com',
  preferredLanguage: 'en',
  timezone: 'Asia/Dhaka',
);

class AcceptanceTokenStore implements TokenStore {
  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

class AcceptanceAuthRepository implements AuthRepository {
  static const session = AuthSession(
    user: user,
    tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
  );

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    return session;
  }

  @override
  Future<CurrentUser> me() async => user;

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return session;
  }
}

class AcceptanceFamilyRepository implements FamilyRepository {
  final List<FamilyMember> members = [];

  @override
  Future<FamilyMember> createMember({
    required String name,
    required String relationship,
    DateTime? dateOfBirth,
    required String preferredLanguage,
    required String timezone,
  }) async {
    final member = FamilyMember(
      id: 'amma-id',
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
    return members.firstWhere((item) => item.id == id);
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

class AcceptanceMedicationRepository implements MedicationRepository {
  final List<MemberMedication> medications = [];

  @override
  Future<MemberMedication> createMedication(
    String memberId, {
    required String displayName,
    String? strength,
    String? dosageForm,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final medication = MemberMedication(
      id: 'metformin-id',
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

void main() {
  testWidgets('register to Amma manual medication golden path', (tester) async {
    final tokenStore = AcceptanceTokenStore();
    final familyRepository = AcceptanceFamilyRepository();
    final medicationRepository = AcceptanceMedicationRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokenStore),
          authRepositoryProvider.overrideWithValue(AcceptanceAuthRepository()),
          familyRepositoryProvider.overrideWithValue(familyRepository),
          medicationRepositoryProvider.overrideWithValue(medicationRepository),
        ],
        child: const FamilyMedApp(locale: Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('registerName')), 'Sifat');
    await tester.enterText(
      find.byKey(const Key('registerEmail')),
      'sifat@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('registerPassword')),
      'password123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('Who do you care for?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('familyName')), 'Amma');
    await tester.tap(find.widgetWithText(FilledButton, 'Add family member'));
    await tester.pumpAndSettle();

    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('No medicines yet'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add manually'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('medicationName')), 'Metformin');
    await tester.enterText(find.byKey(const Key('medicationStrength')), '500 mg');
    await tester.enterText(find.byKey(const Key('medicationDosageForm')), 'tablet');
    await tester.tap(find.widgetWithText(FilledButton, 'Save medicine'));
    await tester.pumpAndSettle();

    expect(find.text('Amma'), findsOneWidget);
    expect(find.text('Metformin'), findsOneWidget);
    expect(find.text('500 mg • tablet'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);
  });
}
