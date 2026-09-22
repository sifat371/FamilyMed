import 'package:dio/dio.dart';

class ApiError implements Exception {
  const ApiError({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const <String, dynamic>{},
  });

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;

  factory ApiError.fromDio(DioException error) {
    if (error.error is ApiError) {
      return error.error! as ApiError;
    }

    final data = error.response?.data;
    if (data is Map) {
      final envelope = data['error'];
      if (envelope is Map) {
        final rawDetails = envelope['details'];
        return ApiError(
          code: envelope['code']?.toString() ?? 'API_ERROR',
          message: envelope['message']?.toString() ?? 'Request failed.',
          statusCode: error.response?.statusCode,
          details: rawDetails is Map
              ? Map<String, dynamic>.from(rawDetails)
              : const <String, dynamic>{},
        );
      }
    }

    return ApiError(
      code: 'NETWORK_ERROR',
      message: 'Could not connect. Try again.',
      statusCode: error.response?.statusCode,
    );
  }

  @override
  String toString() => 'ApiError($code, $message)';
}
