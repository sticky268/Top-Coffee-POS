import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/network/api_exceptions.dart';

DioException _forbidden({
  required String code,
  required String message,
}) {
  return DioException(
    requestOptions: RequestOptions(path: '/test'),
    response: Response(
      statusCode: 403,
      data: {
        'success': false,
        'message': message,
        'code': code,
      },
      requestOptions: RequestOptions(path: '/test'),
    ),
  );
}

void main() {
  group('ApiExceptionMapper subscription errors', () {
    test('maps SUBSCRIPTION_EXPIRED to SubscriptionException', () {
      final exception = ApiExceptionMapper.fromDioException(
        _forbidden(
          code: 'SUBSCRIPTION_EXPIRED',
          message: 'Your subscription has expired.',
        ),
      );

      expect(exception, isA<SubscriptionException>());

      final subscriptionException = exception as SubscriptionException;

      expect(subscriptionException.code, 'SUBSCRIPTION_EXPIRED');
      expect(subscriptionException.message, 'Your subscription has expired.');
      expect(subscriptionException.isExpired, isTrue);
      expect(subscriptionException.isSuspended, isFalse);
      expect(subscriptionException.isBranchLimitReached, isFalse);
    });

    test('maps BUSINESS_SUSPENDED to SubscriptionException', () {
      final exception = ApiExceptionMapper.fromDioException(
        _forbidden(
          code: 'BUSINESS_SUSPENDED',
          message: 'Your business account is suspended.',
        ),
      );

      expect(exception, isA<SubscriptionException>());

      final subscriptionException = exception as SubscriptionException;

      expect(subscriptionException.code, 'BUSINESS_SUSPENDED');
      expect(
        subscriptionException.message,
        'Your business account is suspended.',
      );
      expect(subscriptionException.isExpired, isFalse);
      expect(subscriptionException.isSuspended, isTrue);
      expect(subscriptionException.isBranchLimitReached, isFalse);
    });

    test('maps BRANCH_LIMIT_REACHED to SubscriptionException', () {
      final exception = ApiExceptionMapper.fromDioException(
        _forbidden(
          code: 'BRANCH_LIMIT_REACHED',
          message: 'Your plan has reached its branch limit.',
        ),
      );

      expect(exception, isA<SubscriptionException>());

      final subscriptionException = exception as SubscriptionException;

      expect(subscriptionException.code, 'BRANCH_LIMIT_REACHED');
      expect(
        subscriptionException.message,
        'Your plan has reached its branch limit.',
      );
      expect(subscriptionException.isExpired, isFalse);
      expect(subscriptionException.isSuspended, isFalse);
      expect(subscriptionException.isBranchLimitReached, isTrue);
    });

    test('keeps an unrelated 403 as AuthException', () {
      final exception = ApiExceptionMapper.fromDioException(
        _forbidden(
          code: 'FORBIDDEN',
          message: 'You do not have permission.',
        ),
      );

      expect(exception, isA<AuthException>());
      expect(exception.message, 'You do not have permission.');
    });

    test('keeps 401 as AuthException', () {
      final exception = ApiExceptionMapper.fromDioException(
        DioException(
          requestOptions: RequestOptions(path: '/auth/me'),
          response: Response(
            statusCode: 401,
            data: {
              'success': false,
              'message': 'Unauthenticated.',
            },
            requestOptions: RequestOptions(path: '/auth/me'),
          ),
        ),
      );

      expect(exception, isA<AuthException>());
      expect(exception.message, 'Unauthenticated.');
    });
  });
}
