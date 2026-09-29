import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/branches/application/branch_list_controller.dart';
import 'package:top_coffee_pos/features/branches/application/branch_list_state.dart';
import 'package:top_coffee_pos/features/branches/data/branch_repository.dart';
import 'package:top_coffee_pos/features/branches/domain/branch_models.dart';

class MockBranchRepository extends Mock implements BranchRepository {}

Branch _branch(int id) => Branch(
      id: id,
      name: 'Branch $id',
      code: 'PP-0$id',
      address: 'Phnom Penh',
      phone: '012345678',
      timezone: 'Asia/Phnom_Penh',
      isActive: true,
      usersCount: id,
      createdAt: null,
      updatedAt: null,
    );

void main() {
  late MockBranchRepository repository;

  setUp(() {
    repository = MockBranchRepository();
  });

  BranchListController buildController() {
    final controller = BranchListController(repository);
    addTearDown(controller.dispose);
    return controller;
  }

  test('loads page 1 into BranchListLoaded', () async {
    when(
      () => repository.getBranches(
        page: 1,
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(1), _branch(2)],
        currentPage: 1,
        lastPage: 2,
        perPage: 20,
        total: 3,
      ),
    );

    final controller = buildController();

    await controller.initialization;

    expect(controller.state, isA<BranchListLoaded>());

    final state = controller.state as BranchListLoaded;

    expect(state.branches, hasLength(2));
    expect(state.branches.first.id, 1);
    expect(state.hasMore, isTrue);
  });

  test(
    'a repository failure results in BranchListError, never a stuck Loading',
    () async {
      when(
        () => repository.getBranches(
          page: 1,
        ),
      ).thenThrow(Exception('network down'));

      final controller = buildController();

      await controller.initialization;

      expect(controller.state, isNot(isA<BranchListLoading>()));
      expect(controller.state, isA<BranchListError>());
    },
  );

  test(
    'refresh() reloads page 1 from scratch and can recover from an error',
    () async {
      when(
        () => repository.getBranches(
          page: 1,
        ),
      ).thenThrow(Exception('down'));

      final controller = buildController();

      await controller.initialization;

      expect(controller.state, isA<BranchListError>());

      when(
        () => repository.getBranches(
          page: 1,
        ),
      ).thenAnswer(
        (_) async => BranchListPage(
          data: [_branch(1)],
          currentPage: 1,
          lastPage: 1,
          perPage: 20,
          total: 1,
        ),
      );

      await controller.refresh();

      expect(controller.state, isA<BranchListLoaded>());

      final state = controller.state as BranchListLoaded;

      expect(state.branches.single.id, 1);
    },
  );

  test('applySearch reloads page 1 with the search value', () async {
    when(
      () => repository.getBranches(
        page: 1,
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(1)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      ),
    );

    when(
      () => repository.getBranches(
        page: 1,
        search: 'Riverside',
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(2)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      ),
    );

    final controller = buildController();

    await controller.initialization;
    await controller.applySearch('Riverside');

    final state = controller.state as BranchListLoaded;

    expect(state.branches.single.id, 2);

    verify(
      () => repository.getBranches(
        page: 1,
        search: 'Riverside',
      ),
    ).called(1);
  });

  test('setActive reloads page 1 with the active filter', () async {
    when(
      () => repository.getBranches(
        page: 1,
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(1)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      ),
    );

    when(
      () => repository.getBranches(
        page: 1,
        isActive: false,
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(2)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      ),
    );

    final controller = buildController();

    await controller.initialization;
    await controller.setActive(false);

    final state = controller.state as BranchListLoaded;

    expect(state.branches.single.id, 2);

    verify(
      () => repository.getBranches(
        page: 1,
        isActive: false,
      ),
    ).called(1);
  });

  test('clearFilters reloads page 1 without filters', () async {
    when(
      () => repository.getBranches(
        page: 1,
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(1)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      ),
    );

    when(
      () => repository.getBranches(
        page: 1,
        search: 'Riverside',
        isActive: false,
      ),
    ).thenAnswer(
      (_) async => BranchListPage(
        data: [_branch(2)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      ),
    );

    final controller = buildController();

    await controller.initialization;
    await controller.applySearch('Riverside');
    await controller.setActive(false);
    await controller.clearFilters();

    final state = controller.state as BranchListLoaded;

    expect(state.branches.single.id, 1);

    verify(
      () => repository.getBranches(
        page: 1,
      ),
    ).called(2);
  });

  group('loadMore', () {
    test(
      'appends the next page and advances currentPage',
      () async {
        when(
          () => repository.getBranches(
            page: 1,
          ),
        ).thenAnswer(
          (_) async => BranchListPage(
            data: [_branch(1)],
            currentPage: 1,
            lastPage: 2,
            perPage: 20,
            total: 2,
          ),
        );

        when(
          () => repository.getBranches(
            page: 2,
          ),
        ).thenAnswer(
          (_) async => BranchListPage(
            data: [_branch(2)],
            currentPage: 2,
            lastPage: 2,
            perPage: 20,
            total: 2,
          ),
        );

        final controller = buildController();

        await controller.initialization;
        await controller.loadMore();

        final state = controller.state as BranchListLoaded;

        expect(state.branches, hasLength(2));
        expect(state.branches.map((branch) => branch.id), [1, 2]);
        expect(state.currentPage, 2);
        expect(state.hasMore, isFalse);
      },
    );

    test('is a no-op when there is no next page', () async {
      when(
        () => repository.getBranches(
          page: 1,
        ),
      ).thenAnswer(
        (_) async => BranchListPage(
          data: [_branch(1)],
          currentPage: 1,
          lastPage: 1,
          perPage: 20,
          total: 1,
        ),
      );

      final controller = buildController();

      await controller.initialization;
      await controller.loadMore();

      verifyNever(
        () => repository.getBranches(
          page: 2,
        ),
      );
    });

    test(
      'a failed loadMore keeps the already-loaded branches and clears isLoadingMore',
      () async {
        when(
          () => repository.getBranches(
            page: 1,
          ),
        ).thenAnswer(
          (_) async => BranchListPage(
            data: [_branch(1)],
            currentPage: 1,
            lastPage: 2,
            perPage: 20,
            total: 2,
          ),
        );

        when(
          () => repository.getBranches(
            page: 2,
          ),
        ).thenThrow(Exception('down'));

        final controller = buildController();

        await controller.initialization;
        await controller.loadMore();

        final state = controller.state as BranchListLoaded;

        expect(state.branches, hasLength(1));
        expect(state.branches.single.id, 1);
        expect(state.isLoadingMore, isFalse);
      },
    );
  });

  test('does not throw when disposed during loading', () async {
    when(
      () => repository.getBranches(
        page: 1,
      ),
    ).thenAnswer((_) async {
      await Future<void>.delayed(
        const Duration(milliseconds: 50),
      );

      return BranchListPage(
        data: [_branch(1)],
        currentPage: 1,
        lastPage: 1,
        perPage: 20,
        total: 1,
      );
    });

    final controller = BranchListController(repository);

    controller.dispose();

    await expectLater(
      controller.initialization,
      completes,
    );
  });
}
