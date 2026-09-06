import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';
import 'api_exceptions.dart';

/// Thin wrapper around Dio: injects the auth token, maps errors to typed
/// [ApiException]s, and centralizes base config. Feature repositories should
/// depend on this, not on Dio directly.
class ApiClient {
  ApiClient({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _dio = Dio(BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
        )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.read(key: _tokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  final Dio _dio;
  final FlutterSecureStorage _secureStorage;
  static const _tokenKey = 'auth_token';

  Dio get dio => _dio;

  Future<void> saveToken(String token) => _secureStorage.write(key: _tokenKey, value: token);
  Future<void> clearToken() => _secureStorage.delete(key: _tokenKey);
  Future<String?> readToken() => _secureStorage.read(key: _tokenKey);

  /// Wraps a Dio call, converting DioException into a typed ApiException.
  Future<T> request<T>(Future<T> Function(Dio dio) call) async {
    try {
      return await call(_dio);
    } on DioException catch (e) {
      throw ApiExceptionMapper.fromDioException(e);
    }
  }
}
