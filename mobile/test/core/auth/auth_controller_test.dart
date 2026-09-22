import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_state.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/features/auth/data/auth_repository.dart';
import 'package:familymed/features/auth/domain/auth_session.dart';
import 'package:familymed/features/auth/domain/current_user.dart';
import 'package:flutter_test/flutter_test.dart';

const user = CurrentUser(
  id: 'user-id',
  name: 'Sifat',
  email: 'sifat@example.com',
  preferredLanguage: 'en',
  timezone: 'Asia/Dhaka',
);

class FakeTokenStore implements TokenStore {
  FakeTokenStore([this.tokens]);

  AuthTokens? tokens;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount++;
    tokens = null;
  }

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async {
    tokens = value;
  }
}

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.meResult = user, this.meError});

  final CurrentUser meResult;
  final ApiError? meError;

  @override
  Future<CurrentUser> me() async {
    if (meError != null) throw meError!;
    return meResult;
  }

  @override
  Future<AuthSession> login({required String email, required String password}) async {
    return const AuthSession(
      user: user,
      tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
  }

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async {
    return const AuthSession(
      user: user,
      tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
  }
}

void main() {
  test('restore without stored tokens becomes unauthenticated', () async {
    final store = FakeTokenStore();
    final events = SessionEvents();
    addTearDown(events.dispose);
    final controller = AuthController(
      repository: FakeAuthRepository(),
      tokenStore: store,
      sessionEvents: events,
    );
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.status, AuthStatus.unauthenticated);
  });

  test('restore with valid stored tokens becomes authenticated', () async {
    final store = FakeTokenStore(
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final events = SessionEvents();
    addTearDown(events.dispose);
    final controller = AuthController(
      repository: FakeAuthRepository(),
      tokenStore: store,
      sessionEvents: events,
    );
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.status, AuthStatus.authenticated);
    expect(controller.state.user, user);
  });

  test('invalid restored session clears tokens', () async {
    final store = FakeTokenStore(
      const AuthTokens(accessToken: 'expired', refreshToken: 'bad-refresh'),
    );
    final events = SessionEvents();
    addTearDown(events.dispose);
    final controller = AuthController(
      repository: FakeAuthRepository(
        meError: const ApiError(
          code: 'INVALID_TOKEN',
          message: 'Authentication is invalid or expired.',
          statusCode: 401,
        ),
      ),
      tokenStore: store,
      sessionEvents: events,
    );
    addTearDown(controller.dispose);

    await controller.restore();

    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(store.tokens, isNull);
    expect(store.clearCount, 1);
  });

  test('login stores session and logout clears it', () async {
    final store = FakeTokenStore();
    final events = SessionEvents();
    addTearDown(events.dispose);
    final controller = AuthController(
      repository: FakeAuthRepository(),
      tokenStore: store,
      sessionEvents: events,
    );
    addTearDown(controller.dispose);

    await controller.login(email: 'sifat@example.com', password: 'password123');
    expect(controller.state.status, AuthStatus.authenticated);
    expect(store.tokens?.accessToken, 'access');

    await controller.logout();
    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(store.tokens, isNull);
  });

  test('expired session event clears tokens and auth state', () async {
    final store = FakeTokenStore(
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
    );
    final events = SessionEvents();
    addTearDown(events.dispose);
    final controller = AuthController(
      repository: FakeAuthRepository(),
      tokenStore: store,
      sessionEvents: events,
    );
    addTearDown(controller.dispose);
    await controller.restore();

    events.notifyExpired();
    await Future<void>.delayed(Duration.zero);

    expect(controller.state.status, AuthStatus.unauthenticated);
    expect(store.tokens, isNull);
  });
}
