import 'package:dio/dio.dart';
import 'package:familymed/core/api/api_config.dart';
import 'package:familymed/core/api/api_error.dart';
import 'package:familymed/core/auth/session_events.dart';
import 'package:familymed/core/auth/token_store.dart';

class ApiClient {
  ApiClient({
    required this.tokenStore,
    required this.sessionEvents,
    Dio? dio,
    Dio? refreshDio,
  })  : _dio = dio ?? Dio(BaseOptions(baseUrl: apiBaseUrl)),
        _refreshDio = refreshDio ?? Dio(BaseOptions(baseUrl: apiBaseUrl)) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _onRequest,
        onError: _onError,
      ),
    );
  }

  final TokenStore tokenStore;
  final SessionEvents sessionEvents;
  final Dio _dio;
  final Dio _refreshDio;
  Future<void>? _refreshFuture;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.get<T>(
        path,
        queryParameters: queryParameters,
        options: Options(extra: {'skipAuth': skipAuth}),
      );
    } on DioException catch (error) {
      throw ApiError.fromDio(error);
    }
  }

  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.post<T>(
        path,
        data: data,
        options: Options(extra: {'skipAuth': skipAuth}),
      );
    } on DioException catch (error) {
      throw ApiError.fromDio(error);
    }
  }

  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    bool skipAuth = false,
  }) async {
    try {
      return await _dio.patch<T>(
        path,
        data: data,
        options: Options(extra: {'skipAuth': skipAuth}),
      );
    } on DioException catch (error) {
      throw ApiError.fromDio(error);
    }
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (options.extra['skipAuth'] != true && !_isPublicAuthPath(options.path)) {
      final tokens = await tokenStore.read();
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    final canRefresh = error.response?.statusCode == 401 &&
        request.extra['skipAuth'] != true &&
        request.extra['authRetried'] != true &&
        !_isPublicAuthPath(request.path);
    if (!canRefresh) {
      handler.next(error);
      return;
    }

    try {
      final before = await tokenStore.read();
      if (before == null) {
        await _expireSession();
        throw _invalidToken();
      }

      final failedAuthorization = request.headers['Authorization']?.toString();
      if (failedAuthorization == 'Bearer ${before.accessToken}') {
        await _refreshOnce();
      }

      final latest = await tokenStore.read();
      if (latest == null) {
        throw _invalidToken();
      }

      request.headers['Authorization'] = 'Bearer ${latest.accessToken}';
      request.extra['authRetried'] = true;
      final response = await _dio.fetch<dynamic>(request);
      handler.resolve(response);
    } on ApiError catch (apiError) {
      handler.reject(
        DioException(
          requestOptions: request,
          response: error.response,
          type: DioExceptionType.badResponse,
          error: apiError,
        ),
      );
    } on Object {
      handler.reject(
        DioException(
          requestOptions: request,
          response: error.response,
          type: DioExceptionType.badResponse,
          error: _invalidToken(),
        ),
      );
    }
  }

  Future<void> _refreshOnce() {
    return _refreshFuture ??= _performRefresh().whenComplete(() {
      _refreshFuture = null;
    });
  }

  Future<void> _performRefresh() async {
    final tokens = await tokenStore.read();
    if (tokens == null) {
      await _expireSession();
      throw _invalidToken();
    }

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': tokens.refreshToken},
      );
      final accessToken = response.data?['access_token'] as String?;
      if (accessToken == null || accessToken.isEmpty) {
        throw _invalidToken();
      }
      await tokenStore.write(tokens.copyWith(accessToken: accessToken));
    } on Object catch (error) {
      await _expireSession();
      if (error is ApiError) rethrow;
      throw _invalidToken();
    }
  }

  Future<void> _expireSession() async {
    await tokenStore.clear();
    sessionEvents.notifyExpired();
  }

  bool _isPublicAuthPath(String path) {
    return path.endsWith('/auth/register') ||
        path.endsWith('/auth/login') ||
        path.endsWith('/auth/refresh') ||
        path == '/auth/register' ||
        path == '/auth/login' ||
        path == '/auth/refresh';
  }

  ApiError _invalidToken() {
    return const ApiError(
      code: 'INVALID_TOKEN',
      message: 'Authentication is invalid or expired.',
      statusCode: 401,
    );
  }
}
