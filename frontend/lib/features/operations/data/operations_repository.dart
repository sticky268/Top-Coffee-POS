import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/offline/local_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/data/auth_repository.dart';

typedef OperationsScope = ({int userId, int branchId});

class OperationsRepository {
  OperationsRepository(this.api, this.store, this.scope);
  final ApiClient api;
  final LocalStore store;
  final OperationsScope? Function() scope;
  Future<void> _tail = Future.value();

  Future<dynamic> get(
    String path, {
    Map<String, dynamic> query = const {},
    int? branchId,
  }) async {
    final selected = scope();
    if (selected == null) throw const AuthException('Select a branch first.');
    final response = await api.request(
      (dio) => dio.get(
        path,
        queryParameters: {...query, 'branch_id': branchId ?? selected.branchId},
      ),
    );
    if (scope() != selected) throw const AuthException('Branch changed.');
    final data = response.data['data'];
    if (path == '/shifts' && data is List) {
      final mine = data.where(
        (s) => s['user_id'] == selected.userId && s['status'] == 'open',
      );
      final key = 'active-shift:${selected.userId}:${selected.branchId}';
      if (mine.isEmpty) {
        await store.delete(key);
      } else {
        await store.write(key, '${mine.first['id']}');
      }
    }
    return data;
  }

  String _prefix(OperationsScope selected) =>
      'operation:${selected.userId}:${selected.branchId}:';

  Future<List<Map<String, dynamic>>> pending() async {
    final selected = scope();
    if (selected == null) return [];
    final entries = await store.entries(_prefix(selected));
    return entries.values
        .map((v) => Map<String, dynamic>.from(jsonDecode(v) as Map))
        .toList();
  }

  Future<void> dismissRejected(Map<String, dynamic> operation) async {
    final selected = scope();
    if (selected == null ||
        operation['branch_id'] != selected.branchId ||
        operation['user_id'] != selected.userId ||
        operation['rejected'] != true) {
      throw const AuthException(
        'Only a confirmed rejected request can be dismissed.',
      );
    }
    await store.delete('${_prefix(selected)}${operation['uuid']}');
  }

  Future<dynamic> write(
    String path,
    Map<String, dynamic> values, {
    String? managerPin,
  }) {
    if (values.keys.any(
      (key) => const [
        'pin',
        'manager_pin',
        'current_password',
        'pin_confirmation',
        'password',
        'authorization',
        'x-manager-pin',
      ].contains(key.toLowerCase()),
    )) {
      throw ArgumentError('Credentials must never enter a saved operation.');
    }
    final selected = scope();
    if (selected == null) throw const AuthException('Select a branch first.');
    final next = _tail.then((_) async {
      if (scope() != selected) throw const AuthException('Branch changed.');
      final payload = {
        ...values,
        'branch_id': selected.branchId,
        'expected_user_id': selected.userId,
      };
      // An uncertain identical request is resumed with the original UUID.
      final existing = await pending();
      final fingerprint = jsonEncode([path, payload]);
      final matched = existing.where(
        (o) => o['fingerprint'] == fingerprint && o['rejected'] != true,
      );
      final operation = matched.isNotEmpty
          ? matched.first
          : <String, dynamic>{
              'uuid': const Uuid().v4(),
              'user_id': selected.userId,
              'branch_id': selected.branchId,
              'path': path,
              'payload': payload,
              'fingerprint': fingerprint,
              'rejected': false,
            };
      return _send(operation, selected, managerPin: managerPin);
    });
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<dynamic> retry(Map<String, dynamic> operation, {String? managerPin}) {
    final selected = scope();
    if (selected == null ||
        selected.userId != operation['user_id'] ||
        selected.branchId != operation['branch_id']) {
      throw const AuthException('Request belongs to a different session.');
    }
    final next = _tail.then(
      (_) => _send(operation, selected, managerPin: managerPin),
    );
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<dynamic> _send(
    Map<String, dynamic> operation,
    OperationsScope selected, {
    String? managerPin,
  }) async {
    if (scope() != selected) throw const AuthException('Branch changed.');
    final key = '${_prefix(selected)}${operation['uuid']}';
    final previouslyUncertain =
        operation['attempted'] == true && operation['rejected'] != true;
    operation['attempted'] = true;
    await store.write(key, jsonEncode(operation));
    try {
      final response = await api.dio.post(
        operation['path'] as String,
        options: Options(
          headers: {
            if (managerPin != null && managerPin.isNotEmpty)
              'X-Manager-Pin': managerPin,
          },
        ),
        data: {
          ...Map<String, dynamic>.from(operation['payload'] as Map),
          'uuid': operation['uuid'],
        },
      );
      await store.delete(key);
      return response.data['data'];
    } on DioException catch (e) {
      // A received 4xx response confirms rejection. Timeouts and 5xx responses
      // remain uncertain and must retain their original request reference.
      final status = e.response?.statusCode;
      operation['rejected'] = !previouslyUncertain &&
          status != null &&
          status >= 400 &&
          status < 500;
      operation['error'] = ApiExceptionMapper.fromDioException(e).message;
      await store.write(key, jsonEncode(operation));
      if (previouslyUncertain &&
          status != null &&
          status >= 400 &&
          status < 500) {
        throw UncertainOperationException(
          '${operation['error']}. The earlier result is still unconfirmed; retry the original request after restoring access.',
        );
      }
      throw ApiExceptionMapper.fromDioException(e);
    }
  }
}

final operationsRepositoryProvider = Provider<OperationsRepository>((ref) {
  return OperationsRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
    () {
      final auth = ref.read(authControllerProvider);
      final branch = ref.read(currentBranchProvider);
      return auth is AuthAuthenticated && branch != null
          ? (userId: auth.user.id, branchId: branch.id)
          : null;
    },
  );
});

final shiftsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((
  ref,
) async {
  ref.watch(currentBranchProvider);
  ref.watch(authControllerProvider);
  final data = await ref.watch(operationsRepositoryProvider).get('/shifts');
  return (data as List)
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
});
