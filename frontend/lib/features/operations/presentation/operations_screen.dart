import 'package:flutter/material.dart';

import '../../../core/widgets/page_content.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/network/api_exceptions.dart';
import '../../../core/offline/order_sync.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/operations_repository.dart';
import 'operation_form.dart';

class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});
  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  String _section = 'Shifts';
  int _days = 1;
  bool _compare = false;
  List<Map<String, dynamic>> _comparisons = [];
  dynamic _data;
  List<Map<String, dynamic>> _pending = [];
  String? _error;
  bool _loading = true;
  int _generation = 0;
  final _money = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
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
  }) async {
    final selected = ref.read(currentBranchProvider)?.id;
    await showOperationForm(
      context,
      title: title,
      fields: fields,
      explanation: explanation,
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
    final mine = list.where(
      (s) => s['user_id'] == auth.user.id && s['status'] == 'open',
    );
    final pendingOrders = ref.watch(pendingOrdersProvider).asData?.value;
    final closeSafe =
        pendingOrders != null &&
        pendingOrders.every((o) => o.status == 'synced') &&
        _pending.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mine.isEmpty &&
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
        for (final shift in list)
          _card('Shift #${shift['id']} · ${shift['status']}', [
            _value('Cashier ID', shift['user_id']),
            _value('Opened', shift['created_at']),
            _value('Opening cash', _cash(shift['opening_cash'])),
            _value('Cash sales', _cash(shift['cash_sales'])),
            _value('Cash refunds', _cash(shift['cash_refunds'])),
            _value(
              'Cash added / removed',
              '${_cash(shift['cash_in'])} / ${_cash(shift['cash_out'])}',
            ),
            _value(
              'Expected drawer cash',
              _cash(shift['expected_cash'] ?? shift['live_expected_cash']),
            ),
            if (shift['status'] == 'closed') ...[
              _value('Counted cash', _cash(shift['counted_cash'])),
              _value('Difference', _cash(shift['difference'])),
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
                        'Confirm you have checked the cash count and closing note.',
                  ),
                  child: const Text('Confirm review'),
                ),
            ],
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
                            explanation:
                                'Count the drawer before entering the amount. A difference needs a reason.',
                          ),
                    child: const Text('Close shift'),
                  ),
                ],
              ),
              if (!closeSafe)
                const Text(
                  'Confirm all saved orders and pending operations before closing.',
                ),
            ],
          ]),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No shifts for this branch yet.'),
          ),
      ],
    );
  }

  Widget _stock(AuthAuthenticated auth) => Column(
    children: [
      for (final raw in _data as List)
        Builder(
          builder: (_) {
            final ingredient = Map<String, dynamic>.from(raw as Map);
            final unit = (ingredient['unit'] as Map?)?['abbreviation'] ?? '';
            return _card('${ingredient['name']}', [
              _value('Recorded stock', '${ingredient['current_stock']} $unit'),
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
    final destinations = auth.user.branches
        .where((b) => b.id != current)
        .toList();
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
      final rows =
          await ref
                  .read(operationsRepositoryProvider)
                  .get('/ingredients', branchId: destination)
              as List;
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
      '${_days == 1 ? 'Today' : 'Last $_days days'} · selected branch',
      [
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
        _value(
          'Unpriced wastage entries',
          report['unpriced_wastage_movements'],
        ),
        _value('Shifts awaiting review', report['unreviewed_shifts']),
        _value(
          'Cash payments outside a shift',
          report['unassigned_cash_payments'],
        ),
        const SizedBox(height: 12),
        const Text(
          'Ingredient margin uses receipt and consumption dates; it excludes wastage, rent, salaries and other operating costs. Refunds are reported on the date issued.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    ref.listen(currentBranchProvider, (old, next) {
      if (old?.id != next?.id) _load();
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
      return Scaffold(
        appBar: AppBar(title: const Text('Daily Operations')),
        body: const PageContent(
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
      appBar: AppBar(
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
            for (final operation in _pending)
              _card('Saved operation · ${operation['path']}', [
                Text(
                  operation['rejected'] == true
                      ? 'Server rejected this request.'
                      : 'Confirmation pending. Retry the original request.',
                ),
                if (operation['error'] != null) Text('${operation['error']}'),
                Text('Reference: ${operation['uuid']}'),
                TextButton(
                  onPressed: () async {
                    try {
                      await ref
                          .read(operationsRepositoryProvider)
                          .retry(operation);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$e')));
                      }
                    }
                    if (mounted) _load();
                  },
                  child: const Text('Retry original request'),
                ),
                if (operation['rejected'] == true)
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(operationsRepositoryProvider)
                          .dismissRejected(operation);
                      if (mounted) _load();
                    },
                    child: const Text('Dismiss rejected request'),
                  ),
              ]),
          ],
        ),
      ),
    );
  }
}
