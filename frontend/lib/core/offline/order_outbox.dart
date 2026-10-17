import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../network/api_exceptions.dart';
import 'local_store.dart';

class QueuedOrderException implements Exception {
  const QueuedOrderException(this.uuid);
  final String uuid;
}

class UnresolvedOrderException implements Exception {
  const UnresolvedOrderException(this.uuid);
  final String uuid;
}

class PendingOrder {
  const PendingOrder({
    required this.uuid,
    required this.userId,
    required this.branchId,
    required this.endpoint,
    required this.payload,
    required this.createdAt,
    required this.fingerprint,
    this.status = 'pending',
    this.error,
    this.orderId,
    this.confirmedAt,
  });
  final String uuid;
  final int userId;
  final int branchId;
  final String endpoint;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String fingerprint;
  final String status;
  final String? error;
  final int? orderId;

  /// Device-recorded time of server acknowledgement; absent in legacy records.
  final DateTime? confirmedAt;

  factory PendingOrder.fromJson(Map<String, dynamic> json) => PendingOrder(
        uuid: json['uuid'] as String,
        userId: json['user_id'] as int,
        branchId: json['branch_id'] as int,
        endpoint: json['endpoint'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        createdAt: DateTime.parse(json['created_at'] as String),
        fingerprint: json['fingerprint'] as String,
        status: json['status'] as String,
        error: json['error'] as String?,
        orderId: json['order_id'] as int?,
        confirmedAt: DateTime.tryParse(json['confirmed_at'] as String? ?? ''),
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'user_id': userId,
        'branch_id': branchId,
        'endpoint': endpoint,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'fingerprint': fingerprint,
        'status': status,
        'error': error,
        'order_id': orderId,
        'confirmed_at': confirmedAt?.toIso8601String(),
      };
}

/// A durable write-ahead journal. The server remains authoritative for prices,
/// inventory, permissions and table availability. An uncertain response never
/// creates a new UUID; replay always uses the exact original request.
class OrderOutbox {
  OrderOutbox(this.store, {String Function()? newUuid})
      : _newUuid = newUuid ?? const Uuid().v4;
  final LocalStore store;
  final String Function() _newUuid;
  Future<void> _tail = Future.value();
  final Map<String, Future<void>> _requestLocks = {};
  final StreamController<void> _changes = StreamController.broadcast();
  Stream<void> get changes => _changes.stream;

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<T> withRequestLock<T>(String uuid, Future<T> Function() action) {
    final next = (_requestLocks[uuid] ?? Future<void>.value()).then(
      (_) => action(),
    );
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _requestLocks[uuid] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_requestLocks[uuid], tail)) _requestLocks.remove(uuid);
      }),
    );
    return next;
  }

  Future<List<PendingOrder>> list(int userId, int branchId) async {
    final entries = await store.entries('order:$userId:$branchId:');
    final orders = entries.values
        .map(
          (value) => PendingOrder.fromJson(
            Map<String, dynamic>.from(jsonDecode(value) as Map),
          ),
        )
        .toList();
    orders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return orders;
  }

  // A cashier may retry with different tender or payment method, or add the
  // same items in a different order. Those changes do not establish a new sale.
  // Keep this advisory match separate from the exact replay fingerprint.
  String _saleMatch(Map<String, dynamic> payload) {
    final items = (payload['items'] as List? ?? []).map((value) {
      final item = value as Map;
      return jsonEncode([
        item['product_id'],
        item['product_variant_id'],
        item['quantity'],
      ]);
    }).toList()
      ..sort();
    return jsonEncode([
      payload['order_type'],
      payload['table_id'],
      payload['customer_id'],
      (payload['discount_total'] as num? ?? 0).toDouble(),
      items,
    ]);
  }

  Future<PendingOrder> prepare({
    required int userId,
    required int branchId,
    required String endpoint,
    required Map<String, dynamic> payload,
    bool checkUnresolvedSales = false,
    List<String> acknowledgedPendingUuids = const [],
  }) =>
      _serialized(() async {
        final requestUuid = payload['uuid'] as String?;
        final canonical = {...payload}..remove('uuid');
        final fingerprint = jsonEncode([
          endpoint,
          {...canonical}..remove('shift_id'),
        ]);
        final orders = await list(userId, branchId);
        for (final order in orders) {
          // Explicit IDs represent individual sales, even when baskets match.
          // Legacy callers without an ID retain payload-based retry recovery.
          if (requestUuid != null
              ? order.uuid == requestUuid
              : order.fingerprint == fingerprint && order.status != 'synced') {
            return order;
          }
        }
        if (checkUnresolvedSales && requestUuid != null) {
          for (final order in orders) {
            if (order.status != 'synced' &&
                order.endpoint == endpoint &&
                _saleMatch(order.payload) == _saleMatch(payload) &&
                !acknowledgedPendingUuids.contains(order.uuid)) {
              throw UnresolvedOrderException(order.uuid);
            }
          }
        }
        final uuid = requestUuid ?? _newUuid();
        final order = PendingOrder(
          uuid: uuid,
          userId: userId,
          branchId: branchId,
          endpoint: endpoint,
          payload: {...canonical, 'uuid': uuid, 'expected_cashier_id': userId},
          createdAt: DateTime.now().toUtc(),
          fingerprint: fingerprint,
        );
        await _save(order);
        return order;
      });

  Future<void> _save(PendingOrder order) async {
    await store.write(
      'order:${order.userId}:${order.branchId}:${order.uuid}',
      jsonEncode(order.toJson()),
    );
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<bool> _acknowledged(PendingOrder order) async {
    final stored = await store.read(
      'order:${order.userId}:${order.branchId}:${order.uuid}',
    );
    return stored != null &&
        PendingOrder.fromJson(
              Map<String, dynamic>.from(jsonDecode(stored) as Map),
            ).status ==
            'synced';
  }

  Future<void> finish(PendingOrder order, {int? orderId, Object? error}) =>
      _serialized(() async {
        if (await _acknowledged(order)) return;
        final value = order.toJson();
        value['status'] = error == null
            ? 'synced'
            : error is NetworkException || error is ServerException
                ? 'pending'
                : 'review';
        value['order_id'] = orderId;
        if (error == null) {
          value['confirmed_at'] = DateTime.now().toUtc().toIso8601String();
        }
        value['error'] =
            error is ApiException ? error.message : error?.toString();
        await _save(PendingOrder.fromJson(value));
      });

  Future<void> retry(PendingOrder order) => _serialized(() async {
        if (await _acknowledged(order)) return;
        final value = order.toJson();
        value['status'] = 'pending';
        value['error'] = null;
        await _save(PendingOrder.fromJson(value));
      });

  /// Only acknowledged records can be cleared: uncertain payments are retained.
  Future<void> clearAcknowledged(int userId, int branchId) =>
      _serialized(() async {
        for (final order in await list(userId, branchId)) {
          if (order.status == 'synced') {
            await store.delete('order:$userId:$branchId:${order.uuid}');
          }
        }
        if (!_changes.isClosed) _changes.add(null);
      });

  Future<void> close() => _changes.close();
}

final orderOutboxProvider = Provider<OrderOutbox>((ref) {
  final outbox = OrderOutbox(ref.watch(localStoreProvider));
  ref.onDispose(outbox.close);
  return outbox;
});
