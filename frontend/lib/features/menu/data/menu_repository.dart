import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exceptions.dart';

typedef MenuRecord = Map<String, dynamic>;

String menuError(Object error) {
  if (error is ValidationException) {
    return error.errors.values.expand((v) => v is List ? v : [v]).join('\n');
  }
  return error is ApiException
      ? error.message
      : 'Could not save changes. Please try again.';
}

class MenuRepository {
  MenuRepository(this.api);
  final ApiClient api;

  Future<void> saveAvailability(
          int product, int branch, bool available, String? price) =>
      api.request((dio) async {
        await dio.patch('/products/$product', data: {
          'branches': [
            {
              'branch_id': branch,
              'is_available': available,
              'price_override': price
            }
          ]
        });
      });

  Future<MenuRecord> load(int branch) => api.request((dio) async {
        final response = await dio.get(
          '/menu',
          queryParameters: {'branch_id': branch},
        );
        return Map<String, dynamic>.from(response.data['data'] as Map);
      });

  Future<void> save(String section, int branch, MenuRecord data) =>
      api.request((dio) async {
        final id = data['id'];
        final payload = {...data, 'branch_id': branch};
        if (id == null) {
          await dio.post('/menu/$section', data: payload);
        } else {
          await dio.put('/menu/$section/$id', data: payload);
        }
      });
}

final menuRepositoryProvider = Provider(
  (ref) => MenuRepository(ref.watch(apiClientProvider)),
);
final menuDataProvider = FutureProvider.autoDispose<MenuRecord>((ref) {
  final branch = ref.watch(currentBranchProvider);
  if (branch == null) throw StateError('Select a branch on the dashboard.');
  return ref.watch(menuRepositoryProvider).load(branch.id);
});
