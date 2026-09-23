import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/app/app.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/auth_controller.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/core/sync/sync_coordinator.dart';
import 'package:familymed/features/auth/data/auth_repository.dart';
import 'package:familymed/features/auth/domain/auth_session.dart';
import 'package:familymed/features/auth/domain/current_user.dart';
import 'package:familymed/features/today/data/today_repository.dart';
import 'package:familymed/features/today/domain/dose_projection.dart';
import 'package:familymed/features/today/domain/today_member_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TokenStore implements TokenStore {
  AuthTokens? tokens =
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh');

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

class _AuthRepository implements AuthRepository {
  static const user = CurrentUser(
    id: 'user-1',
    name: 'Sifat',
    email: 'sifat@example.com',
    preferredLanguage: 'en',
    timezone: 'Asia/Dhaka',
  );

  @override
  Future<CurrentUser> me() async => user;

  @override
  Future<AuthSession> login({
    required String email,
    required String password,
  }) async =>
      const AuthSession(
        user: user,
        tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      );

  @override
  Future<AuthSession> register({
    required String name,
    required String email,
    required String password,
  }) async =>
      const AuthSession(
        user: user,
        tokens: AuthTokens(accessToken: 'access', refreshToken: 'refresh'),
      );
}

class _TodayRepository implements TodayRepository {
  int reminderLoads = 0;

  @override
  Future<List<DoseProjection>> cachedReminderDoses() async => const [];

  @override
  Future<List<DoseProjection>> loadReminderDoses({int days = 30}) async {
    reminderLoads++;
    return const [];
  }

  @override
  Future<TodayLoadResult> loadToday() async =>
      const TodayLoadResult(groups: <TodayMemberGroup>[], isOffline: false);
}

class _Transport implements SyncTransport {
  int calls = 0;
  Object? error;

  @override
  Future<DoseProjection> submit(SyncOperationEnvelope operation) async {
    calls++;
    if (error != null) throw error!;
    final scheduled = DateTime.utc(2026, 9, 23, 14);
    return DoseProjection(
      id: operation.doseId,
      scheduleId: 'schedule-1',
      familyMemberId: 'member-1',
      memberMedicationId: 'med-1',
      medicationName: 'Metformin',
      strength: '500 mg',
      scheduledAt: scheduled,
      scheduledLocalDate: '2026-09-23',
      scheduledLocalTime: '20:00',
      timezone: 'Asia/Dhaka',
      quantityText: '1',
      unit: 'tablet',
      mealRelation: 'after_food',
      status: 'taken',
      effectiveReminderAt: scheduled,
    );
  }
}

Future<void> _seed(AppDatabase db, String operationId) async {
  await db.customInsert(
    'INSERT INTO sync_operations '
    '(operation_id, dose_id, action, payload_json, created_at, '
    'attempt_count, terminal_failure) VALUES (?, ?, ?, ?, ?, 0, 0)',
    variables: [
      Variable<String>(operationId),
      Variable<String>('dose-$operationId'),
      const Variable<String>('taken'),
      Variable<String>(jsonEncode(<String, dynamic>{
        'client_action_id': operationId,
        'occurred_at': '2026-09-23T14:05:00Z',
      })),
      Variable<DateTime>(DateTime.utc(2026, 9, 23, 14, 5)),
    ],
  );
}

void main() {
  testWidgets('authenticated restore and app resume drain queued actions',
      (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = _Transport();
    final todayRepository = _TodayRepository();
    final coordinator = SyncCoordinator(database: db, transport: transport);
    addTearDown(coordinator.dispose);
    await _seed(db, 'restore-action');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(_TokenStore()),
          authRepositoryProvider.overrideWithValue(_AuthRepository()),
          todayRepositoryProvider.overrideWithValue(todayRepository),
          syncCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const FamilyMedApp(locale: Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    expect(transport.calls, 1);
    expect(todayRepository.reminderLoads, 1);

    await _seed(db, 'resume-action');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(transport.calls, 2);
    expect(todayRepository.reminderLoads, 2);
  });

  testWidgets('terminal sync failure is visible to the caregiver', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final transport = _Transport()
      ..error = const ApiError(
        code: 'VALIDATION_ERROR',
        message: 'invalid action',
        statusCode: 422,
      );
    final coordinator = SyncCoordinator(database: db, transport: transport);
    addTearDown(coordinator.dispose);
    await _seed(db, 'terminal-action');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(_TokenStore()),
          authRepositoryProvider.overrideWithValue(_AuthRepository()),
          todayRepositoryProvider.overrideWithValue(_TodayRepository()),
          syncCoordinatorProvider.overrideWithValue(coordinator),
        ],
        child: const FamilyMedApp(locale: Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Could not sync this dose change. Review it and try again.'),
      findsOneWidget,
    );
  });
}
