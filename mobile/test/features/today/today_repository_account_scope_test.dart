import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/core/database/app_database.dart';
import 'package:familymed/features/today/data/today_repository.dart';
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

class _TodayAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = <Map<String, dynamic>>[
      <String, dynamic>{
        'member_id': 'member-a',
        'member_name': 'Amma',
        'relationship': 'mother',
        'local_date': '2026-09-23',
        'timezone': 'Asia/Dhaka',
        'taken_count': 0,
        'total_count': 1,
        'doses': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'dose-a',
            'schedule_id': 'schedule-a',
            'family_member_id': 'member-a',
            'member_medication_id': 'med-a',
            'medication_name': 'Metformin',
            'strength': '500 mg',
            'scheduled_at': '2026-09-23T14:00:00Z',
            'scheduled_local_date': '2026-09-23',
            'scheduled_local_time': '20:00:00',
            'timezone': 'Asia/Dhaka',
            'quantity': '1',
            'unit': 'tablet',
            'meal_relation': 'after_food',
            'status': 'pending',
            'snoozed_until': null,
            'taken_at': null,
            'skipped_at': null,
            'missed_at': null,
            'effective_reminder_at': '2026-09-23T14:00:00Z',
          },
        ],
      },
    ];
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _seedDose(
  AppDatabase db, {
  required String userId,
  required String doseId,
  String status = 'pending',
}) async {
  await db.into(db.cachedDoses).insert(
        CachedDosesCompanion.insert(
          doseId: doseId,
          userId: Value<String>(userId),
          scheduleId: 'schedule-$userId',
          memberId: 'member-$userId',
          medicationId: 'med-$userId',
          medicationName: 'Metformin',
          quantityText: '1',
          unit: 'tablet',
          scheduledAt: DateTime.utc(2026, 9, 23, 14),
          scheduledLocalDate: '2026-09-23',
          scheduledLocalTime: '20:00',
          timezone: 'Asia/Dhaka',
          status: status,
          effectiveReminderAt: DateTime.utc(2026, 9, 23, 14),
          updatedAt: DateTime.utc(2026, 9, 23, 13),
        ),
      );
}

void main() {
  test('cached reminder doses never cross account boundaries', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedDose(db, userId: 'user-a', doseId: 'dose-a');
    await _seedDose(db, userId: 'user-b', doseId: 'dose-b');

    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final events = SessionEvents();
    addTearDown(events.dispose);
    addTearDown(dio.close);

    final repository = ApiTodayRepository(
      ApiClient(
        tokenStore: _TokenStore(),
        sessionEvents: events,
        dio: dio,
      ),
      db,
      userId: 'user-a',
    );

    final doses = await repository.cachedReminderDoses();

    expect(doses.map((dose) => dose.id), <String>['dose-a']);
  });

  test('today refresh does not overwrite a dose with a queued local action',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.cachedTodayMembers).insert(
          CachedTodayMembersCompanion.insert(
            memberId: 'member-a',
            userId: const Value<String>('user-a'),
            name: 'Amma',
            relationship: 'mother',
            localDate: '2026-09-23',
            timezone: 'Asia/Dhaka',
            updatedAt: DateTime.utc(2026, 9, 23, 13),
          ),
        );
    await _seedDose(
      db,
      userId: 'user-a',
      doseId: 'dose-a',
      status: 'taken',
    );
    await db.into(db.syncOperations).insert(
          SyncOperationsCompanion.insert(
            operationId: 'action-a',
            userId: const Value<String>('user-a'),
            doseId: 'dose-a',
            action: 'taken',
            payloadJson: jsonEncode(<String, dynamic>{
              'client_action_id': 'action-a',
              'occurred_at': '2026-09-23T14:05:00Z',
            }),
            createdAt: DateTime.utc(2026, 9, 23, 14, 5),
          ),
        );

    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = _TodayAdapter();
    final events = SessionEvents();
    addTearDown(events.dispose);
    addTearDown(dio.close);
    final repository = ApiTodayRepository(
      ApiClient(
        tokenStore: _TokenStore(),
        sessionEvents: events,
        dio: dio,
      ),
      db,
      userId: 'user-a',
    );

    await repository.loadToday();

    final row = await (db.select(db.cachedDoses)
          ..where((dose) => dose.doseId.equals('dose-a')))
        .getSingle();
    expect(row.status, 'taken');
  });
}
