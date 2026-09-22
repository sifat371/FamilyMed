import 'package:dio/dio.dart';
import 'package:familymed/core/api/api_client.dart';
import 'package:familymed/core/auth/auth_tokens.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore(this.tokens);

  AuthTokens? tokens;

  @override
  Future<void> clear() async => tokens = null;

  @override
  Future<AuthTokens?> read() async => tokens;

  @override
  Future<void> write(AuthTokens value) async => tokens = value;
}

void main() {
  test('concurrent 401 responses share one refresh and retry with new access token', () async {
    final normalDio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://test/api/v1'));
    final normalAdapter = DioAdapter(
      dio: normalDio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );
    final refreshAdapter = DioAdapter(
      dio: refreshDio,
      matcher: const UrlRequestMatcher(matchMethod: true),
    );
    final store = MemoryTokenStore(
      const AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-token'),
    );
    final events = SessionEvents();
    addTearDown(events.dispose);

    var refreshRequestCount = 0;
    const invalidToken = {
      'error': {
        'code': 'INVALID_TOKEN',
        'message': 'Authentication is invalid or expired.',
        'details': <String, dynamic>{},
      },
    };

    normalAdapter.onGet(
      '/protected/one',
      (server) => server.reply(401, invalidToken),
    );
    normalAdapter.onGet(
      '/protected/one',
      (server) => server.reply(200, {'ok': true}),
    );
    normalAdapter.onGet(
      '/protected/two',
      (server) => server.reply(401, invalidToken),
    );
    normalAdapter.onGet(
      '/protected/two',
      (server) => server.reply(200, {'ok': true}),
    );
    refreshAdapter.onPost(
      '/auth/refresh',
      (server) {
        refreshRequestCount++;
        server.reply(200, {'access_token': 'new-access', 'token_type': 'bearer'});
      },
      data: {'refresh_token': 'refresh-token'},
    );

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

    expect(refreshRequestCount, 1);
    expect((await store.read())!.accessToken, 'new-access');
    expect(results[0].statusCode, 200);
    expect(results[1].statusCode, 200);
  });
}
