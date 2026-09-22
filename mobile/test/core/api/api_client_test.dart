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
    final normalAdapter = DioAdapter(dio: normalDio);
    final refreshAdapter = DioAdapter(dio: refreshDio);
    final store = MemoryTokenStore(
      const AuthTokens(accessToken: 'old-access', refreshToken: 'refresh-token'),
    );
    final events = SessionEvents();
    addTearDown(events.dispose);

    var protectedRequestCount = 0;
    var refreshRequestCount = 0;
    normalAdapter.onGet('/protected', (server) {
      protectedRequestCount++;
      if (protectedRequestCount <= 2) {
        server.reply(401, {
          'error': {
            'code': 'INVALID_TOKEN',
            'message': 'Authentication is invalid or expired.',
            'details': <String, dynamic>{},
          },
        });
      } else {
        server.reply(200, {'ok': true});
      }
    });
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
      client.get<dynamic>('/protected'),
      client.get<dynamic>('/protected'),
    ]);

    expect(refreshRequestCount, 1);
    expect(protectedRequestCount, 4);
    expect((await store.read())!.accessToken, 'new-access');
    expect(results[0].statusCode, 200);
    expect(results[1].statusCode, 200);
  });
}
