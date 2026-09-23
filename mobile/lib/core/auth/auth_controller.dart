import 'dart:async';

import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_state.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/core/storage/secure_token_store.dart';
import 'package:familymed/core/sync/api_activity_events.dart';
import 'package:familymed/features/auth/data/auth_repository.dart';
import 'package:familymed/features/auth/domain/current_user.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AuthController extends StateNotifier<AuthState> {
  AuthController({
    required AuthRepository repository,
    required TokenStore tokenStore,
    required SessionEvents sessionEvents,
  })  : _repository = repository,
        _tokenStore = tokenStore,
        _sessionEvents = sessionEvents,
        super(const AuthState.loading()) {
    _expiredSubscription = _sessionEvents.expired.listen((_) {
      unawaited(_expireSession());
    });
  }

  final AuthRepository _repository;
  final TokenStore _tokenStore;
  final SessionEvents _sessionEvents;
  late final StreamSubscription<void> _expiredSubscription;

  Future<void> restore() async {
    state = const AuthState.loading();
    final tokens = await _tokenStore.read();
    if (tokens == null) {
      state = const AuthState.unauthenticated();
      return;
    }

    try {
      final user = await _repository.me();
      state = AuthState.authenticated(user);
    } on ApiError catch (error) {
      if (error.code == 'INVALID_TOKEN') {
        await _tokenStore.clear();
      }
      state = AuthState.unauthenticated(error.message);
    }
  }

  Future<CurrentUser> register({
    required String name,
    required String email,
    required String password,
  }) async {
    state = const AuthState.loading();
    try {
      final session = await _repository.register(
        name: name,
        email: email,
        password: password,
      );
      await _tokenStore.write(session.tokens);
      state = AuthState.authenticated(session.user);
      return session.user;
    } on ApiError catch (error) {
      state = AuthState.unauthenticated(error.message);
      rethrow;
    }
  }

  Future<CurrentUser> login({
    required String email,
    required String password,
  }) async {
    state = const AuthState.loading();
    try {
      final session = await _repository.login(email: email, password: password);
      await _tokenStore.write(session.tokens);
      state = AuthState.authenticated(session.user);
      return session.user;
    } on ApiError catch (error) {
      state = AuthState.unauthenticated(error.message);
      rethrow;
    }
  }

  Future<void> logout() async {
    await _tokenStore.clear();
    state = const AuthState.unauthenticated();
  }

  Future<void> _expireSession() async {
    await _tokenStore.clear();
    state = const AuthState.unauthenticated();
  }

  @override
  void dispose() {
    _expiredSubscription.cancel();
    super.dispose();
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final sessionEventsProvider = Provider<SessionEvents>((ref) {
  final events = SessionEvents();
  ref.onDispose(events.dispose);
  return events;
});

final apiActivityEventsProvider = Provider<ApiActivityEvents>((ref) {
  final events = ApiActivityEvents();
  ref.onDispose(events.dispose);
  return events;
});

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStore: ref.watch(tokenStoreProvider),
    sessionEvents: ref.watch(sessionEventsProvider),
    activityEvents: ref.watch(apiActivityEventsProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return ApiAuthRepository(ref.watch(apiClientProvider));
});

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  final controller = AuthController(
    repository: ref.watch(authRepositoryProvider),
    tokenStore: ref.watch(tokenStoreProvider),
    sessionEvents: ref.watch(sessionEventsProvider),
  );
  unawaited(controller.restore());
  return controller;
});
