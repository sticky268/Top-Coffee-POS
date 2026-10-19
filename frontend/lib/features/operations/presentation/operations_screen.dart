import 'package:top_coffee_pos/core/widgets/page_app_bar.dart';
import '../../auth/presentation/manager_pin_prompt.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/offline/order_sync.dart';
import '../../../core/offline/order_sync_summary.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/operations_repository.dart';
import '../../inventory/domain/inventory_models.dart';
import 'operation_form.dart';
import 'operation_display.dart';

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({
    super.key,
    this.initialSection,
    this.initialShiftId,
    this.initialDifferencesOnly = false,
  });
  final String? initialSection;
  final int? initialShiftId;
  final bool initialDifferencesOnly;
  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  String _section = 'Shifts';
  bool _differencesOnly = false;
  int _days = 1;
  bool _compare = false;
  List<Map<String, dynamic>> _comparisons = [];
  dynamic _data;
  List<Map<String, dynamic>> _pending = [];
  String? _error;
  bool _loading = true;
  bool _pendingBusy = false;
  int? _shiftFilterId;
  int _generation = 0;
  final _money = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
    _section =
        widget.initialSection == 'Owner report' ? 'Owner report' : 'Shifts';
    _differencesOnly = widget.initialDifferencesOnly;
    _shiftFilterId = widget.initialShiftId;
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _data = null;
        _pending = [];
        _comparisons = [];
      });
    }
    if (ref.read(currentBranchProvider) == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final repo = ref.read(operationsRepositoryProvider);
      final saved = await repo.pending();
      if (mounted && generation == _generation) {
        setState(() => _pending = saved);
      }
      final now = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final start = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.now().subtract(Duration(days: _days - 1)));
      final path = switch (_section) {
        'Stock counts' => '/ingredients',
        'Availability' => '/products/availability',
        'Owner report' => '/reports/operations',
        _ => '/shifts',
      };
      final data = await repo.get(
        path,
        query: _section == 'Owner report'
            ? {'date_from': start, 'date_to': now}
            : _section == 'Shifts' && _shiftFilterId != null
                ? {'shift_id': _shiftFilterId}
                : {},
      );
      final comparisons = <Map<String, dynamic>>[];
      final auth = ref.read(authControllerProvider);
      if (_section == 'Owner report' && _compare && auth is AuthAuthenticated) {
        for (final branch in auth.user.branches) {
          final values = await repo.get(
            '/reports/operations',
            branchId: branch.id,
            query: {'date_from': start, 'date_to': now},
          );
          comparisons.add({
            'branch': branch.name,
            ...Map<String, dynamic>.from(values as Map),
          });
        }
      }
      final pending = await repo.pending();
      if (mounted && generation == _generation) {
        setState(() {
          _data = data;
          _comparisons = comparisons;
          _pending = pending;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = e is ApiException ? e.message : e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _form(
    String title,
    String path,
    List<OperationField> fields, {
    Map<String, dynamic> extra = const {},
    String? explanation,
    num? expectedCash,
  }) async {
    final selected = ref.read(currentBranchProvider)?.id;
    await showOperationForm(
      context,
      title: title,
      fields: fields,
      explanation: explanation,
      expectedCash: expectedCash,
      save: (values) async {
        if (ref.read(currentBranchProvider)?.id != selected) {
          throw const AuthException('Branch changed. Reopen this action.');
        }
        await ref.read(operationsRepositoryProvider).write(path, {
          ...extra,
          ...values,
        });
      },
    );
    if (mounted) {
      ref.invalidate(shiftsProvider);
      await _load();
    }
  }

  Widget _card(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
  Widget _value(String label, Object? value) =>
      DetailValue(label: label, value: '$value');
  String _cash(dynamic value) => _money.format(num.tryParse('$value') ?? 0);

  Widget _shifts(AuthAuthenticated auth) {
    final list = (_data as List).cast<Map<String, dynamic>>();
    final shown = _differencesOnly
        ? list
            .where(
              (s) =>
                  s['status'] == 'closed' &&
                  ((num.tryParse('${s['difference']}') ?? 0).abs() >= 0.005) &&
                  s['reviewed_at'] == null,
            )
            .toList()
        : list;
    final mine = list.where(
      (s) => s['user_id'] == auth.user.id && s['status'] == 'open',
    );
    final pendingOrders = ref.watch(pendingOrdersProvider).asData?.value;
    final syncSummary = pendingOrders == null
        ? null
        : OrderSyncSummary.fromOrders(pendingOrders);
    final closeSafe =
        syncSummary != null && !syncSummary.hasUnconfirmed && _pending.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_shiftFilterId != null)
          TextButton.icon(
            onPressed: () {
              setState(() {
                _shiftFilterId = null;
                _differencesOnly = false;
              });
              _load();
            },
            icon: const Icon(Icons.list),
            label: const Text('Show all shifts'),
          ),
        if (_shiftFilterId == null &&
            mine.isEmpty &&
            (auth.user.hasPermission('orders.create') ||
                auth.user.hasPermission('orders.refund')))
          FilledButton.icon(
            onPressed: () => _form('Open shift', '/shifts', const [
              OperationField(
                'opening_cash',
                'Opening cash',
                initial: '0',
                number: true,
              ),
            ]),
            icon: const Icon(Icons.lock_open),
            label: const Text('Open shift'),
          ),
        if (auth.user.hasPermission('reports.view'))
          SwitchListTile(
            title: const Text('Show unreviewed cash differences only'),
            value: _differencesOnly,
            onChanged: (value) => setState(() => _differencesOnly = value),
          ),
        for (final shift in shown)
          _card('Shift #${shift['id']} · ${shift['status']}', [
            _value('Cashier', shiftCashierName(shift, auth.user)),
            _value(
              'Opened (device time)',
              operationDeviceTime(shift['created_at']),
            ),
            _value(
              'Expected drawer cash',
              _cash(shift['expected_cash'] ?? shift['live_expected_cash']),
            ),
            if (shift['status'] == 'closed') ...[
              _value('Counted cash', _cash(shift['counted_cash'])),
              _value('Difference', _cash(shift['difference'])),
              Text(
                cashDifferenceDescription(shift['difference']),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _value(
                'Closed (device time)',
                operationDeviceTime(shift['closed_at']),
              ),
              if (shift['closing_reason'] != null)
                _value('Closing note', shift['closing_reason']),
              _value(
                'Review',
                shift['reviewed_at'] == null
                    ? 'Awaiting manager review'
                    : 'Reviewed',
              ),
              if (auth.user.hasPermission('reports.view') &&
                  shift['reviewed_at'] == null)
                OutlinedButton(
                  onPressed: () => _form(
                    'Review shift',
                    '/shifts/${shift['id']}/review',
                    const [],
                    explanation:
                        'Check the expected cash breakdown, recorded cash movements and closing note before confirming review.',
                  ),
                  child: const Text('Confirm review'),
                ),
            ],
            _cashBreakdown(shift, auth),
            if (shift['status'] == 'open' &&
                shift['user_id'] == auth.user.id) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => _form(
                      'Cash movement',
                      '/shifts/${shift['id']}/movements',
                      const [
                        OperationField(
                          'type',
                          'Direction',
                          options: ['in', 'out'],
                          optionLabels: {
                            'in': 'Add cash',
                            'out': 'Remove cash',
                          },
                        ),
                        OperationField('amount', 'Amount', number: true),
                        OperationField('reason', 'Reason'),
                      ],
                    ),
                    child: const Text('Add / remove cash'),
                  ),
                  FilledButton(
                    onPressed: !closeSafe
                        ? null
                        : () => _form(
                              'Close shift',
                              '/shifts/${shift['id']}/close',
                              const [
                                OperationField(
                                  'counted_cash',
                                  'Counted cash',
                                  number: true,
                                ),
                                OperationField(
                                  'reason',
                                  'Explain any difference',
                                  optional: true,
                                ),
                              ],
                              expectedCash: num.tryParse(
                                '${shift['expected_cash'] ?? shift['live_expected_cash']}',
                              ),
                              explanation:
                                  'Count the cash in the drawer. Compare it with the expected amount below; explain any shortage or overage. The server checks the final balance when you confirm.',
                            ),
                    child: const Text('Close shift'),
                  ),
                ],
              ),
              if (!closeSafe) ...[
                const SizedBox(height: 8),
                Text(
                  syncSummary == null
                      ? 'Check saved orders before closing. Their status is not available yet.'
                      : syncSummary.hasUnconfirmed
                          ? '${syncSummary.description}. Resolve these before closing.'
                          : 'Resolve the ${_pending.length} saved operations below before closing.',
                ),
                TextButton.icon(
                  onPressed: () => context.go('/pending-orders'),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('View saved orders'),
                ),
              ],
            ],
          ]),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _differencesOnly
                  ? 'No unreviewed cash differences in these shifts.'
                  : 'No shifts for this branch yet.',
            ),
          ),
      ],
    );
  }

  Widget _cashBreakdown(
    Map<String, dynamic> shift,
    AuthAuthenticated auth,
  ) =>
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('How expected cash is calculated'),
        children: [
          _value('Opening cash', _cash(shift['opening_cash'])),
          _value('Plus cash sales', _cash(shift['cash_sales'])),
          _value('Minus cash refunds', _cash(shift['cash_refunds'])),
          _value('Plus cash added', _cash(shift['cash_in'])),
          _value('Minus cash removed', _cash(shift['cash_out'])),
          if ((shift['cash_refund_orders'] as List?)?.isNotEmpty == true) ...[
            const Divider(),
            const Text('Cash refunds taken from this shift'),
            for (final refund in shift['cash_refund_orders'] as List)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Order #${refund['order_id']} · ${_cash(refund['amount'])} cash refund',
                ),
                subtitle: Text(
                  '${refund['reason'] ?? 'Reason not recorded'} · '
                  '${operationDeviceTime(refund['created_at'])} (device time)',
                ),
                trailing: auth.user.hasPermission('orders.view')
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: auth.user.hasPermission('orders.view')
                    ? () =>
                        context.push('/orders/${refund['order_id']}/financials')
                    : null,
              ),
          ],
          if ((shift['movements'] as List?)?.isNotEmpty == true) ...[
            const Divider(),
            const Text('Recorded cash movements'),
            for (final movement in shift['movements'] as List)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${movement['type'] == 'in' ? 'Cash added' : 'Cash removed'} '
                  '· ${_cash(movement['amount'])}',
                ),
                subtitle: Text(
                  '${movement['reason'] ?? 'No reason recorded'}\n'
                  '${operationDeviceTime(movement['created_at'])} (device time)',
                ),
              ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Check cash refunds and cash movements above against the drawer count. '
              'Saved orders on this device may still be unconfirmed and do not prove payment.',
            ),
          ),
          if (auth.user.hasPermission('orders.view') ||
              auth.user.hasPermission('orders.create'))
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('Review saved and unresolved orders'),
              subtitle: const Text(
                'This account and branch on this device; not necessarily this shift.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/pending-orders'),
            ),
        ],
      );

  Future<void> _retryOperation(Map<String, dynamic> operation) async {
    if (_pendingBusy) return;
    setState(() => _pendingBusy = true);
    try {
      final needsPin = RegExp(
        r'^/orders/\d+/refund$',
      ).hasMatch('${operation['path']}');
      final pin = needsPin
          ? await requestManagerPin(
              context,
              ref,
              action: 'Confirm saved refund',
            )
          : '';
      if (pin == null || !mounted) return;
      final repo = ref.read(operationsRepositoryProvider);
      if (pin.isEmpty) {
        await repo.retry(operation);
      } else {
        await repo.retry(operation, managerPin: pin);
      }
      ref.invalidate(shiftsProvider);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not confirm this action. Keep it and try again.',
            ),
          ),
        );
        await _load();
      }
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  Future<void> _dismissOperation(Map<String, dynamic> operation) async {
    if (_pendingBusy) return;
    setState(() => _pendingBusy = true);
    try {
      await ref.read(operationsRepositoryProvider).dismissRejected(operation);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not dismiss this rejected action. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingBusy = false);
    }
  }

  Widget _savedOperation(Map<String, dynamic> operation) =>
      _card('Saved action · ${savedOperationTitle(operation)}', [
        for (final detail in savedOperationDetails(operation)) Text(detail),
        Text(
          operation['rejected'] == true
              ? 'The server confirmed that this action was rejected. '
                  'Review the reason before retrying or dismissing it.'
              : 'Saved on this device; the result is not confirmed. '
                  'Retry this original action to check its result safely.',
        ),
        if (operation['error'] != null) Text('${operation['error']}'),
        TextButton(
          onPressed: _pendingBusy ? null : () => _retryOperation(operation),
          child: const Text('Retry original action'),
        ),
        if (operation['rejected'] == true)
          TextButton(
            onPressed: _pendingBusy ? null : () => _dismissOperation(operation),
            child: const Text('Dismiss rejected action'),
          ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Request details'),
          children: [
            SelectableText('Reference: ${operation['uuid']}'),
            Text('Request: ${operation['path']}'),
          ],
        ),
      ]);

  Widget _stock(AuthAuthenticated auth) => Column(
        children: [
          for (final raw in _data as List)
            Builder(
              builder: (_) {
                final ingredient = Map<String, dynamic>.from(raw as Map);
                final unit =
                    (ingredient['unit'] as Map?)?['abbreviation'] ?? '';
                return _card('${ingredient['name']}', [
                  _value(
                      'Recorded stock', '${ingredient['current_stock']} $unit'),
                  if (auth.user.hasPermission('inventory.adjust'))
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => _form(
                            'Count ${ingredient['name']}',
                            '/stock/count',
                            const [
                              OperationField(
                                'counted_stock',
                                'Actual counted quantity',
                                number: true,
                              ),
                              OperationField('reason', 'Count note'),
                              OperationField(
                                'unit_cost',
                                'Unit cost (optional stock valuation)',
                                number: true,
                                optional: true,
                              ),
                            ],
                            extra: {
                              'ingredient_id': ingredient['id'],
                              'expected_stock': num.parse(
                                '${ingredient['current_stock']}',
                              ),
                            },
                            explanation:
                                'Quantity is in $unit. If stock changes during counting, refresh and recount.',
                          ),
                          child: const Text('Record count'),
                        ),
                        OutlinedButton(
                          onPressed: () => _transfer(ingredient),
                          child: const Text('Transfer to branch'),
                        ),
                      ],
                    ),
                ]);
              },
            ),
        ],
      );

  Future<void> _transfer(Map<String, dynamic> source) async {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) return;
    final current = ref.read(currentBranchProvider)?.id;
    final destinations =
        auth.user.branches.where((b) => b.id != current).toList();
    if (destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You need access to another branch to transfer stock.'),
        ),
      );
      return;
    }
    final destination = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Destination branch'),
        children: destinations
            .map(
              (b) => SimpleDialogOption(
                onPressed: () => Navigator.pop(context, b.id),
                child: Text(b.name),
              ),
            )
            .toList(),
      ),
    );
    if (destination == null || !mounted) return;
    try {
      final rows = await ref
          .read(operationsRepositoryProvider)
          .get('/ingredients', branchId: destination) as List;
      if (!mounted || ref.read(currentBranchProvider)?.id != current) return;
      final matches = rows
          .cast<Map<String, dynamic>>()
          .where(
            (i) =>
                '${i['name']}'.trim().toLowerCase() ==
                    '${source['name']}'.trim().toLowerCase() &&
                i['is_active'] == true,
          )
          .toList();
      if (matches.length != 1) {
        throw const ValidationException(
          {},
          'Destination needs exactly one matching active ingredient.',
        );
      }
      await _form(
        'Transfer ${source['name']}',
        '/stock/transfer',
        const [
          OperationField('quantity', 'Quantity in source unit', number: true),
          OperationField('reason', 'Transfer reason'),
        ],
        extra: {
          'source_ingredient_id': source['id'],
          'destination_ingredient_id': matches.single['id'],
        },
        explanation:
            'Confirm the goods are physically received. Both branch balances update together.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is ApiException ? e.message : '$e')),
        );
      }
    }
  }

  Widget _availability() => Column(
        children: [
          for (final raw in _data as List)
            Builder(
              builder: (_) {
                final product = raw as Map<String, dynamic>;
                return _card('${product['name']}', [
                  _value(
                    'Available base servings',
                    product['available_servings'] ?? 'Recipe not configured',
                  ),
                  _value(
                    'Ingredient cost per serving',
                    product['ingredient_cost'] == null
                        ? 'Cost incomplete'
                        : _cash(product['ingredient_cost']),
                  ),
                  for (final v in (product['variants'] as List? ?? []))
                    _value(
                      '${v['variant_name']}',
                      '${v['available_servings'] ?? 'Untracked'} servings · ${v['ingredient_cost'] == null ? 'Cost incomplete' : _cash(v['ingredient_cost'])}',
                    ),
                ]);
              },
            ),
        ],
      );

  Widget _report() {
    final report = _data as Map<String, dynamic>;
    return _card(
        '${_days == 1 ? 'Today' : 'Last $_days days'} · selected branch', [
      for (final entry in const {
        'gross_sales': 'Gross receipts',
        'refunds': 'Refunds issued',
        'net_sales': 'Net receipts',
        'discounts': 'Discounts',
        'known_ingredient_cost': 'Known ingredient cost',
        'ingredient_margin': 'Ingredient margin',
        'wastage_cost': 'Known wastage cost',
        'cash_difference': 'Cash count difference',
      }.entries)
        _value(
          entry.value,
          report[entry.key] == null
              ? 'Incomplete costing'
              : _cash(report[entry.key]),
        ),
      _value('Items without cost snapshots', report['unknown_cost_items']),
      _value('Unpriced wastage entries', report['unpriced_wastage_movements']),
      _value('Shifts awaiting review', report['unreviewed_shifts']),
      _value(
        'Shifts with cash differences',
        report['cash_difference_shift_count'],
      ),
      for (final raw in (report['cash_difference_shifts'] as List? ?? []))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            'Shift #${raw['id']} · ${cashDifferenceDescription(raw['difference'])}',
          ),
          subtitle: Text(operationDeviceTime(raw['closed_at'])),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              context.push('/operations?section=Shifts&shift_id=${raw['id']}'),
        ),
      _value(
        'Stock count adjustments with a difference',
        report['stock_count_discrepancy_count'],
      ),
      const Text(
        'Read-only stock count history. Inspect the recorded quantity '
        'before and counted quantity after; no approval or new adjustment is created.',
      ),
      for (final raw in (report['stock_count_discrepancies'] as List? ?? []))
        Builder(
          builder: (context) {
            final delta = num.tryParse('${raw['quantity']}') ?? 0;
            final counted = num.tryParse('${raw['balance_after']}') ?? 0;
            final ingredient = InventoryIngredient(
              id: raw['ingredient_id'] as int,
              name: '${raw['ingredient_name']}',
              unit: InventoryUnit(
                id: raw['unit_id'] as int,
                name: '${raw['unit_name']}',
                abbreviation: '${raw['unit_abbreviation']}',
              ),
              currentStock:
                  (num.tryParse('${raw['current_stock']}') ?? 0).toDouble(),
              reorderThreshold:
                  (num.tryParse('${raw['reorder_threshold']}') ?? 0).toDouble(),
              isLowStock: false,
              isActive: raw['is_active'] == true || raw['is_active'] == 1,
            );
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${raw['ingredient_name']} · ${delta > 0 ? '+' : ''}$delta ${ingredient.unit.abbreviation}',
              ),
              subtitle: Text(
                'Recorded ${(counted - delta).toStringAsFixed(3)} → '
                'counted ${counted.toStringAsFixed(3)} ${ingredient.unit.abbreviation}\n'
                '${raw['reason']} · ${operationDeviceTime(raw['created_at'])} (device time)',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(
                '/inventory/history?movement_id=${raw['id']}',
                extra: ingredient,
              ),
            );
          },
        ),
      _value(
        'Cash payments outside a shift',
        report['unassigned_cash_payments'],
      ),
      const SizedBox(height: 12),
      const Text(
        'Ingredient margin uses receipt and consumption dates; it excludes wastage, rent, salaries and other operating costs. Refunds are reported on the date issued.',
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen(currentBranchProvider, (old, next) {
      if (old?.id != next?.id) {
        _shiftFilterId = null;
        _load();
      }
    });
    if (auth is! AuthAuthenticated) {
      return const Scaffold(
        body: PageContent(
          maxWidth: 1000,
          child: Center(child: Text('Sign in to continue.')),
        ),
      );
    }
    if (ref.watch(currentBranchProvider) == null) {
      return const Scaffold(
        appBar: PageAppBar(title: Text('Daily Operations')),
        body: PageContent(
          maxWidth: 1000,
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Select a branch to view Daily Operations.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    final sections = [
      'Shifts',
      if (auth.user.hasPermission('inventory.view')) ...[
        'Stock counts',
        'Availability',
      ],
      if (auth.user.hasPermission('reports.view')) 'Owner report',
    ];
    return Scaffold(
      appBar: PageAppBar(
        title: const Text('Daily Operations'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () => context.go('/pos'),
            icon: const Icon(Icons.point_of_sale),
            tooltip: 'New takeaway order',
          ),
        ],
      ),
      body: PageContent(
        maxWidth: 1000,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              ref.watch(currentBranchProvider)?.name ?? 'Select a branch',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sections
                  .map(
                    (s) => ChoiceChip(
                      label: Text(s),
                      selected: _section == s,
                      onSelected: (_) {
                        setState(() => _section = s);
                        _load();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            if (_section == 'Owner report') ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final days in [1, 7, 30])
                    ChoiceChip(
                      label: Text(days == 1 ? 'Today' : '$days days'),
                      selected: _days == days,
                      onSelected: (_) {
                        setState(() => _days = days);
                        _load();
                      },
                    ),
                ],
              ),
              if (auth.user.branches.length > 1)
                SwitchListTile(
                  title: const Text('Compare accessible branches'),
                  value: _compare,
                  onChanged: (v) {
                    setState(() => _compare = v);
                    _load();
                  },
                ),
            ],
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _card('Could not load operations', [
                Text(_error!),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ])
            else if (_data != null)
              switch (_section) {
                'Stock counts' => _stock(auth),
                'Availability' => _availability(),
                'Owner report' => _report(),
                _ => _shifts(auth),
              },
            if (!_loading && _section == 'Owner report')
              for (final branch in _comparisons)
                _card('${branch['branch']}', [
                  _value('Gross receipts', _cash(branch['gross_sales'])),
                  _value('Net receipts', _cash(branch['net_sales'])),
                  _value('Cash difference', _cash(branch['cash_difference'])),
                  _value('Cost incomplete items', branch['unknown_cost_items']),
                ]),
            for (final operation in _pending) _savedOperation(operation),
          ],
        ),
      ),
    );
  }
}
