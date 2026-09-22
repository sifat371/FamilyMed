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

class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.tokens]);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({
    this.loginError,
    this.registerError,
    this.meError,
  });

  ApiError? loginError;
  ApiError? registerError;
  ApiError? meError;
  int loginCalls = 0;
  int registerCalls = 0;

  static const session = AuthSession(
    user: currentUser,
    tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
  );

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    loginCalls++;
    if (loginError != null) throw loginError!;
    return session;
  }

  @override
  Future<CurrentUser> me() async {
    if (meError != null) throw meError!;
    return currentUser;
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    registerCalls++;
    if (registerError != null) throw registerError!;
    return session;
  }
}

class FakeFamilyRepository implements FamilyRepository {
  FakeFamilyRepository(this.members);

  final List<FamilyMember> members;

  @override
  Future<List<FamilyMember>> listMembers() async => members;

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
  Future<FamilyMember> getMember(String id) {
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

ProviderContainer makeContainer({
  FakeTokenStore? tokenStore,
  FakeAuthRepository? authRepository,
  List<FamilyMember> members = const [],
}) {
  return ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokenStore ?? FakeTokenStore()),
      authRepositoryProvider.overrideWithValue(
        authRepository ?? FakeAuthRepository(),
      ),
      familyRepositoryProvider.overrideWithValue(FakeFamilyRepository(members)),
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

Finder createAccountButton() => find.widgetWithText(FilledButton, 'Create account');
Finder signInButton() => find.widgetWithText(FilledButton, 'Sign in');

void main() {
  testWidgets('welcome actions navigate to register and login', (tester) async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(currentPath(container), '/register');

    container.read(routerProvider).go('/welcome');
    await tester.pumpAndSettle();
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(currentPath(container), '/login');
  });

  testWidgets('seven-character password blocks registration', (tester) async {
    final authRepository = FakeAuthRepository();
    final container = makeContainer(authRepository: authRepository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);
    container.read(routerProvider).go('/register');
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('registerName')), 'Sifat');
    await tester.enterText(
      find.byKey(const Key('registerEmail')),
      'sifat@example.com',
    );
    await tester.enterText(find.byKey(const Key('registerPassword')), '1234567');
    await tester.tap(createAccountButton());
    await tester.pumpAndSettle();

    expect(find.text('Password must be 8–128 characters.'), findsOneWidget);
    expect(authRepository.registerCalls, 0);
  });

  testWidgets('failed login preserves form values and shows error', (tester) async {
    final authRepository = FakeAuthRepository(
      loginError: const ApiError(
        code: 'INVALID_CREDENTIALS',
        message: 'Invalid email or password.',
        statusCode: 401,
      ),
    );
    final container = makeContainer(authRepository: authRepository);
    addTearDown(container.dispose);
    await pumpApp(tester, container);
    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('loginEmail')),
      'sifat@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('loginPassword')),
      'password123',
    );
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password.'), findsOneWidget);
    expect(find.text('sifat@example.com'), findsOneWidget);
    expect(find.text('password123'), findsOneWidget);
    expect(authRepository.loginCalls, 1);
  });

  testWidgets('register success routes to care-for onboarding', (tester) async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await pumpApp(tester, container);
    container.read(routerProvider).go('/register');
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
    await tester.tap(createAccountButton());
    await tester.pumpAndSettle();

    expect(currentPath(container), '/care-for');
  });

  testWidgets('login with no members routes to care-for onboarding', (tester) async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await pumpApp(tester, container);
    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('loginEmail')),
      'sifat@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('loginPassword')),
      'password123',
    );
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(currentPath(container), '/care-for');
  });

  testWidgets('login with an existing member routes to family', (tester) async {
    final container = makeContainer(members: const [amma]);
    addTearDown(container.dispose);
    await pumpApp(tester, container);
    container.read(routerProvider).go('/login');
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('loginEmail')),
      'sifat@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('loginPassword')),
      'password123',
    );
    await tester.tap(signInButton());
    await tester.pumpAndSettle();

    expect(currentPath(container), '/family');
  });

  testWidgets('unauthenticated protected route redirects to login', (tester) async {
    final container = makeContainer();
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    container.read(routerProvider).go('/family');
    await tester.pumpAndSettle();

    expect(currentPath(container), '/login');
  });

  testWidgets('restored authenticated session leaves welcome for family', (tester) async {
    final container = makeContainer(
      tokenStore: FakeTokenStore(
        const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      ),
      members: const [amma],
    );
    addTearDown(container.dispose);
    await pumpApp(tester, container);

    expect(currentPath(container), '/family');
  });
}
