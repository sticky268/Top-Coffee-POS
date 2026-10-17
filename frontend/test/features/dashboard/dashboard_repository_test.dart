import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/core/network/api_client.dart';
import 'package:top_coffee_pos/features/dashboard/data/dashboard_repository.dart';

class _Api extends Mock implements ApiClient {}

Response<dynamic> _response(int orders) => Response(
  requestOptions: RequestOptions(path: '/dashboard'),
  data: {'data': {
    'stats': {'todays_sales': 20, 'todays_orders': orders,
      'average_order_value': 10, 'low_stock_item_count': 1},
    'recent_orders': [], 'sales_overview': [],
  }},
);

void main() {
  test('concurrent dashboard readers share one snapshot; next refresh fetches fresh', () async {
    final api = _Api();
    final response = Completer<Response<dynamic>>();
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) => response.future);
    final repository = ApiDashboardRepository(api, branchId: 3);
    final stats = repository.getStats();
    final orders = repository.getRecentOrders();
    final sales = repository.getSalesOverview();
    verify(() => api.request<Response<dynamic>>(any())).called(1);
    response.complete(_response(2));
    expect((await stats).todaysOrders, 2);
    expect(await orders, isEmpty);
    expect(await sales, isEmpty);
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) async => _response(4));
    expect((await repository.getStats()).todaysOrders, 4);
    verify(() => api.request<Response<dynamic>>(any())).called(1);
  });
  test('failed shared request is cleared so a retry can recover', () async {
    final api = _Api();
    final response = Completer<Response<dynamic>>();
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) => response.future);
    final repository = ApiDashboardRepository(api, branchId: 3);
    final readers = Future.wait<Object>([
      repository.getStats(), repository.getRecentOrders(), repository.getSalesOverview(),
    ]);
    final expectation = expectLater(readers, throwsA(isA<StateError>()));
    response.completeError(StateError('offline'));
    await expectation;
    verify(() => api.request<Response<dynamic>>(any())).called(1);
    when(() => api.request<Response<dynamic>>(any()))
        .thenAnswer((_) async => _response(6));
    expect((await repository.getStats()).todaysOrders, 6);
  });
}
