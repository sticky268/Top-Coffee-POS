import 'package:dio/dio.dart';

sealed class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
}

class NetworkException extends ApiException {
  const NetworkException([super.message = 'No internet connection']);
}

class ValidationException extends ApiException {
  const ValidationException(this.errors, [super.message = 'Validation failed']);
  final Map<String, dynamic> errors;
}

class AuthException extends ApiException {
  const AuthException([super.message = 'Authentication failed']);
}

class ServerException extends ApiException {
  const ServerException([super.message = 'Server error, please try again']);
}

class UnknownApiException extends ApiException {
  const UnknownApiException([super.message = 'Something went wrong']);
}

class ApiExceptionMapper {
  static ApiException fromDioException(DioException e) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const NetworkException();
    }

    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      final data = e.response?.data;
      final message = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'Authentication failed';
      return AuthException(message);
    }
    if (status == 422) {
      final data = e.response?.data;
      final errors = (data is Map && data['errors'] is Map)
          ? Map<String, dynamic>.from(data['errors'])
          : <String, dynamic>{};
      return ValidationException(errors);
    }
    if (status != null && status >= 500) {
      return const ServerException();
    }
    return const UnknownApiException();
  }
}
