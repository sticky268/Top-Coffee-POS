import 'package:dio/dio.dart';

sealed class ApiException implements Exception {
  const ApiException(this.message);

  final String message;
}

class NetworkException extends ApiException {
  const NetworkException([super.message = 'No internet connection']);
}

class ValidationException extends ApiException {
  const ValidationException(
    this.errors, [
    super.message = 'Validation failed',
  ]);

  final Map<String, dynamic> errors;
}

class AuthException extends ApiException {
  const AuthException([super.message = 'Authentication failed']);
}

class SubscriptionException extends ApiException {
  const SubscriptionException(
    this.code, [
    super.message = 'Subscription access restricted',
  ]);

  final String code;

  bool get isExpired => code == 'SUBSCRIPTION_EXPIRED';

  bool get isSuspended => code == 'BUSINESS_SUSPENDED';

  bool get isBranchLimitReached => code == 'BRANCH_LIMIT_REACHED';
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
    final data = e.response?.data;

    if (status == 401) {
      final message = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'Authentication failed';

      return AuthException(message);
    }

    if (status == 403) {
      final code = (data is Map && data['code'] is String)
          ? data['code'] as String
          : null;

      final message = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'Access denied';

      if (code != null &&
          (code == 'SUBSCRIPTION_EXPIRED' ||
              code == 'BUSINESS_SUSPENDED' ||
              code == 'BRANCH_LIMIT_REACHED')) {
        return SubscriptionException(code, message);
      }

      return AuthException(message);
    }

    if (status == 422) {
      final errors = (data is Map && data['errors'] is Map)
          ? Map<String, dynamic>.from(data['errors'])
          : <String, dynamic>{};

      final message = (data is Map && data['message'] is String)
          ? data['message'] as String
          : 'Validation failed';

      return ValidationException(errors, message);
    }

    if (status != null && status >= 500) {
      return const ServerException();
    }

    final message = (data is Map && data['message'] is String)
        ? data['message'] as String
        : 'HTTP ${status ?? 'unknown'}';

    return UnknownApiException(message);
  }
}
