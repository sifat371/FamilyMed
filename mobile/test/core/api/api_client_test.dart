import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:familymed/core/sync/api_activity_events.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore(this.tokens);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;

  test('successful public request emits one API activity event', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    dio.httpClientAdapter = SuccessAdapter();
    final store = MemoryTokenStore(
      const AuthTokens(accessToken: 'access', refreshToken: 'refresh-token'),
    );
    final sessionEvents = SessionEvents();
    final activityEvents = ApiActivityEvents();
    addTearDown(sessionEvents.dispose);
    addTearDown(activityEvents.dispose);
    addTearDown(dio.close);

    final client = ApiClient(
      tokenStore: store,
      sessionEvents: sessionEvents,
      activityEvents: activityEvents,
      dio: dio,
      refreshDio: Dio(BaseOptions(baseUrl: 'http://test/api/v1')),
    );

    final event = activityEvents.successes.first;
    final response = await client.get<dynamic>('/today');
    await event;

    expect(response.statusCode, 200);
  });

}

class ProtectedAdapter implements HttpClientAdapter {
  int oldAccessRequests = 0;
  int newAccessRequests = 0;
  final Completer<void> _bothOldRequestsSeen = Completer<void>();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final authorization = options.headers['Authorization']?.toString();
    if (authorization == 'Bearer old-access') {
      oldAccessRequests++;
      if (oldAccessRequests == 2 && !_bothOldRequestsSeen.isCompleted) {
        _bothOldRequestsSeen.complete();
      }
      await _bothOldRequestsSeen.future;
      return _jsonResponse(
        401,
        {
          'error': {
            'code': 'INVALID_TOKEN',
            'message': 'Authentication is invalid or expired.',
            'details': <String, dynamic>{},
          },
        },
      );
    }

    if (authorization == 'Bearer new-access') {
      newAccessRequests++;
      return _jsonResponse(200, {'ok': true});
    }

    return _jsonResponse(
      401,
      {
        'error': {
          'code': 'INVALID_TOKEN',
          'message': 'Authentication is invalid or expired.',
          'details': <String, dynamic>{},
        },
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class RefreshAdapter implements HttpClientAdapter {
  int refreshRequests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    refreshRequests++;
    expect(options.path, '/auth/refresh');
    expect(options.data, {'refresh_token': 'refresh-token'});
    return _jsonResponse(
      200,
      {'access_token': 'new-access', 'token_type': 'bearer'},
    );
  }

  @override
  void close({bool force = false}) {}
}



class SuccessAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _jsonResponse(200, {'ok': true});
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(int statusCode, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

void main() {
  test('concurrent 401 responses share one refresh and retry with new access token', () async {
    final normalDio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final protectedAdapter = ProtectedAdapter();
    final refreshAdapter = RefreshAdapter();
    normalDio.httpClientAdapter = protectedAdapter;
    refreshDio.httpClientAdapter = refreshAdapter;

    final store = MemoryTokenStore(
      const AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-token'),
    );
    final events = SessionEvents();
    addTearDown(events.dispose);
    addTearDown(normalDio.close);
    addTearDown(refreshDio.close);

    final client = ApiClient(
      tokenStore: store,
      sessionEvents: events,
      dio: normalDio,
      refreshDio: refreshDio,
    );

    final results = await Future.wait([
      client.get<dynamic>('/protected/one'),
      client.get<dynamic>('/protected/two'),
    ]);

    expect(protectedAdapter.oldAccessRequests, 2);
    expect(protectedAdapter.newAccessRequests, 2);
    expect(refreshAdapter.refreshRequests, 1);
    expect((await store.read())!.accessToken, 'new-access');
    expect(results[0].statusCode, 200);
    expect(results[1].statusCode, 200);
  });
}
