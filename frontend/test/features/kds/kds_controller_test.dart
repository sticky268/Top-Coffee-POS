import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:top_coffee_pos/features/kds/application/kds_controller.dart';
import 'package:top_coffee_pos/features/kds/data/kds_repository.dart';
import 'package:top_coffee_pos/features/kds/domain/kds_models.dart';

class MockKdsRepository extends Mock implements KdsRepository {}

KitchenTicket makeTicket({String status = 'new'}) => KitchenTicket(
      id: 12,
      status: status,
      order: KitchenOrder(
        id: 105,
        orderType: 'dine_in',
        status: 'held',
        total: 5,
        createdAt: DateTime(2026, 10, 6),
        items: const [
          KitchenOrderItem(
            id: 3,
            productName: 'Latte',
            quantity: 2,
            unitPrice: 2.5,
          ),
        ],
        table: const KitchenTable(id: 1, name: 'T1'),
      ),
    );

void main() {
  late MockKdsRepository repository;
  late ProviderContainer container;
  late KdsController controller;

  setUp(() {
    repository = MockKdsRepository();
    when(() => repository.getTickets(branchId: any(named: 'branchId')))
        .thenAnswer((_) async => [makeTicket()]);
    container = ProviderContainer(overrides: [
      kdsRepositoryProvider.overrideWithValue(repository),
    ]);
    controller = container.read(kdsControllerProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('status change retains ticket order details and items', () async {
    await controller.loadTickets();
    when(() => repository.updateTicketStatus(ticketId: 12, status: 'preparing'))
        .thenAnswer((_) async {});

    await controller.updateStatus(ticketId: 12, status: 'preparing');

    final ticket = container.read(kdsControllerProvider).tickets.single;
    expect(ticket.status, 'preparing');
    expect(ticket.order.items.single.productName, 'Latte');
    expect(ticket.order.table?.name, 'T1');
  });

  test('acknowledgement removes cancelled ticket from active view', () async {
    when(() => repository.getTickets(branchId: any(named: 'branchId')))
        .thenAnswer((_) async => [makeTicket(status: 'cancelled')]);
    await controller.loadTickets();
    when(() => repository.acknowledgeCancellation(ticketId: 12))
        .thenAnswer((_) async {});

    await controller.acknowledgeCancellation(ticketId: 12);

    expect(container.read(kdsControllerProvider).tickets, isEmpty);
    expect(container.read(kdsControllerProvider).updatingTicketId, isNull);
  });

  test('switching branches clears old tickets while new data loads', () async {
    await controller.loadTickets(branchId: 74);
    expect(container.read(kdsControllerProvider).tickets, hasLength(1));

    final secondBranch = Completer<List<KitchenTicket>>();
    when(() => repository.getTickets(branchId: 75))
        .thenAnswer((_) => secondBranch.future);

    final switching = controller.loadTickets(branchId: 75);
    expect(container.read(kdsControllerProvider).tickets, isEmpty);
    expect(container.read(kdsControllerProvider).isLoading, isTrue);

    secondBranch.complete([makeTicket(status: 'ready')]);
    await switching;
    expect(container.read(kdsControllerProvider).tickets.single.status, 'ready');
  });

  test('slower response from previous branch cannot replace current branch', () async {
    final previousBranch = Completer<List<KitchenTicket>>();
    when(() => repository.getTickets(branchId: 74))
        .thenAnswer((_) => previousBranch.future);
    when(() => repository.getTickets(branchId: 75))
        .thenAnswer((_) async => [makeTicket(status: 'ready')]);

    final staleLoad = controller.loadTickets(branchId: 74);
    await controller.loadTickets(branchId: 75);
    previousBranch.complete([makeTicket(status: 'new')]);
    await staleLoad;

    expect(container.read(kdsControllerProvider).tickets.single.status, 'ready');
  });

  test('branch switch while updating cannot restore previous branch ticket', () async {
    await controller.loadTickets(branchId: 74);
    final pendingUpdate = Completer<void>();
    when(() => repository.updateTicketStatus(ticketId: 12, status: 'preparing'))
        .thenAnswer((_) => pendingUpdate.future);
    when(() => repository.getTickets(branchId: 75))
        .thenAnswer((_) async => [makeTicket(status: 'ready')]);

    final updating = controller.updateStatus(ticketId: 12, status: 'preparing');
    expect(container.read(kdsControllerProvider).updatingTicketId, 12);

    await controller.loadTickets(branchId: 75);
    expect(container.read(kdsControllerProvider).updatingTicketId, isNull);
    expect(container.read(kdsControllerProvider).tickets.single.status, 'ready');

    pendingUpdate.complete();
    await updating;
    expect(container.read(kdsControllerProvider).tickets.single.status, 'ready');
  });

  test('stale refresh cannot undo successful status change', () async {
    await controller.loadTickets();
    final oldRefresh = Completer<List<KitchenTicket>>();
    when(() => repository.getTickets(branchId: any(named: 'branchId')))
        .thenAnswer((_) => oldRefresh.future);
    final pendingRefresh = controller.loadTickets();
    when(() => repository.updateTicketStatus(ticketId: 12, status: 'preparing'))
        .thenAnswer((_) async {});

    await controller.updateStatus(ticketId: 12, status: 'preparing');
    oldRefresh.complete([makeTicket()]);
    await pendingRefresh;

    expect(container.read(kdsControllerProvider).tickets.single.status,
        'preparing');
    expect(container.read(kdsControllerProvider).isLoading, isFalse);
  });
}
