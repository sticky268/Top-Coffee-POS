import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/operations_repository.dart';
import 'operation_form.dart';

class PaymentOperationsScreen extends ConsumerStatefulWidget {
  const PaymentOperationsScreen({super.key, required this.orderId});
  final int orderId;
  @override
  ConsumerState<PaymentOperationsScreen> createState() =>
      _PaymentOperationsScreenState();
}

class _PaymentOperationsScreenState
    extends ConsumerState<PaymentOperationsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _data = null;
        _error = null;
      });
    }
    try {
      final data = await ref
          .read(operationsRepositoryProvider)
          .get('/orders/${widget.orderId}/financials');
      if (mounted && generation == _generation) {
        setState(() => _data = Map<String, dynamic>.from(data as Map));
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e is ApiException ? e.message : '$e');
      }
    }
  }

  Future<void> _action(bool refund) async {
    final branch = ref.read(currentBranchProvider)?.id;
    await showOperationForm(
      context,
      title: refund ? 'Refund payment' : 'Additional charge',
      explanation: refund
          ? 'Consumed keeps stock unchanged. Restock or wastage applies only to a first, full-sale refund. Cash refunds require your open shift. This records the refund; any card/QR provider refund must also be completed separately.'
          : 'Record a charge correction with a reason. For extra products, create a new sale so their stock usage is recorded. Card/QR payment is recorded by the cashier, not verified by a bank.',
      fields: [
        const OperationField('amount', 'Amount', number: true),
        if (refund)
          const OperationField(
            'inventory_disposition',
            'Ingredient handling',
            options: ['consumed', 'restock', 'wastage'],
          )
        else ...[
          const OperationField(
            'method',
            'Payment method',
            options: ['cash', 'card', 'qr'],
          ),
          const OperationField(
            'tendered',
            'Cash received (cash only)',
            number: true,
            optional: true,
          ),
        ],
        const OperationField('reason', 'Reason'),
      ],
      save: (values) async {
        if (ref.read(currentBranchProvider)?.id != branch) {
          throw const AuthException('Branch changed.');
        }
        await ref
            .read(operationsRepositoryProvider)
            .write(
              '/orders/${widget.orderId}/${refund ? 'refund' : 'additional-charge'}',
              values,
            );
      },
    );
    if (mounted) {
      ref.invalidate(shiftsProvider);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentBranchProvider, (old, next) {
      if (old?.id != next?.id) _load();
    });
    final auth = ref.watch(authControllerProvider);
    final canAdjust =
        auth is AuthAuthenticated && auth.user.hasPermission('orders.refund');
    final money = NumberFormat.currency(symbol: '\$');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment History'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: PageContent(maxWidth: 1000, child: _error != null
          ? Center(child: Text(_error!))
          : _data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Paid: ${money.format(_data!['paid'])}'),
                        Text('Refunded: ${money.format(_data!['refunded'])}'),
                        Text('Net paid: ${money.format(_data!['net_paid'])}'),
                        const SizedBox(height: 12),
                        if (canAdjust)
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _action(true),
                                child: const Text('Refund'),
                              ),
                              FilledButton(
                                onPressed: () => _action(false),
                                child: const Text('Additional charge'),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                for (final payment in _data!['payments'] as List)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '${payment['method']} · ${money.format(num.parse('${payment['amount']}'))} · ${payment['status']}',
                          ),
                          Text(
                            'Verification: ${payment['verification'] ?? 'cashier_recorded'}',
                          ),
                          for (final refund in payment['refunds'] as List)
                            Text(
                              'Refund ${money.format(num.parse('${refund['amount']}'))} · ${refund['inventory_disposition']} · ${refund['reason']}',
                            ),
                        ],
                      ),
                    ),
                  ),
                const Text(
                  'Pending corrections are retained in Daily Operations if confirmation is interrupted.',
                ),
              ],
            )),
    );
  }
}
