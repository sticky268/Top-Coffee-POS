import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

class SelectTableScreen extends ConsumerStatefulWidget {
  const SelectTableScreen({super.key});

  @override
  ConsumerState<SelectTableScreen> createState() => _SelectTableScreenState();
}

class _SelectTableScreenState extends ConsumerState<SelectTableScreen> {
  List<PosTable> _tables = [];
  bool _isLoading = true;
  String? _error;
  VoidCallback? _routerListener;

// 0 = Auto, otherwise fixed column count.
  int _tableColumns = 0;

  Future<void> _loadTableLayoutPreference() async {
    final preferences = await SharedPreferences.getInstance();
    final savedColumns = preferences.getInt('pos_table_columns') ?? 0;

    if (!mounted) return;

    if ([0, 2, 3, 4, 5].contains(savedColumns)) {
      setState(() {
        _tableColumns = savedColumns;
      });
    }
  }

  Future<void> _saveTableLayoutPreference(int columns) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt('pos_table_columns', columns);
  }

  @override
  void initState() {
    super.initState();
    _loadTableLayoutPreference();
    _loadTables();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final router = GoRouter.of(context);

    if (_routerListener == null) {
      _routerListener = () {
        if (!mounted) return;

        final location = router.routerDelegate.currentConfiguration.uri.path;

        if (location == '/pos/select-table') {
          _loadTables();
        }
      };

      router.routerDelegate.addListener(_routerListener!);
    }
  }

  @override
  void dispose() {
    if (_routerListener != null) {
      GoRouter.of(context).routerDelegate.removeListener(_routerListener!);
    }

    super.dispose();
  }

  Future<void> _loadTables() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tables = await ref.read(posRepositoryProvider).getTables();

      if (!mounted) return;

      final sortedTables = [...tables]..sort((a, b) {
          final aNumber =
              int.tryParse(a.name.replaceFirst(RegExp(r'^\D+'), '')) ?? 0;
          final bNumber =
              int.tryParse(b.name.replaceFirst(RegExp(r'^\D+'), '')) ?? 0;

          if (aNumber != bNumber) {
            return aNumber.compareTo(bNumber);
          }

          return a.name.compareTo(b.name);
        });

      setState(() {
        _tables = sortedTables;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = 'Unable to load tables.';
      });
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'occupied':
        return 'Occupied';
      case 'reserved':
        return 'Reserved';
      default:
        return 'Available';
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final colorScheme = Theme.of(context).colorScheme;

    switch (status) {
      case 'occupied':
        return colorScheme.error;
      case 'reserved':
        return colorScheme.tertiary;
      default:
        return colorScheme.primary;
    }
  }

  void _selectTable(PosTable table) {
    if (table.status == 'available') {
      context.go('/pos', extra: table);
      return;
    }

    if (table.status == 'occupied' && table.activeOrderId != null) {
      context.push('/pos/open-order/${table.activeOrderId}');
      return;
    }

    if (table.status == 'reserved') {
      _showTableMessage(
        title: 'Table Reserved',
        message: '${table.name} is currently reserved.',
        icon: Icons.event_seat,
      );
      return;
    }

    if (table.status == 'occupied' && table.activeOrderId == null) {
      _showTableMessage(
        title: 'Table Occupied',
        message:
            '${table.name} is marked as occupied, but there is no active order.',
        icon: Icons.warning_amber_rounded,
      );
    }
  }

  void _showTableMessage({
    required String title,
    required String message,
    required IconData icon,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Table'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadTables,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildToolbar(context),
          const Divider(height: 1),
          Expanded(
            child: _buildContent(context),
          ),
        ],
      ),
      floatingActionButton: _tables.isEmpty || _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                context.push('/tables');
              },
              icon: const Icon(Icons.table_restaurant),
              label: const Text('Manage Tables'),
            ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _LegendItem(
            color: Colors.green,
            label: 'Available',
          ),
          _LegendItem(
            color: Colors.orange,
            label: 'Occupied',
          ),
          _LegendItem(
            color: Colors.blue,
            label: 'Reserved',
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Table Layout:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _tableColumns,
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Auto')),
                  DropdownMenuItem(value: 2, child: Text('2 Columns')),
                  DropdownMenuItem(value: 3, child: Text('3 Columns')),
                  DropdownMenuItem(value: 4, child: Text('4 Columns')),
                  DropdownMenuItem(value: 5, child: Text('5 Columns')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _tableColumns = value;
                  });
                  _saveTableLayoutPreference(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadTables,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_tables.isEmpty) {
      return const Center(
        child: Text('No tables available.'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final SliverGridDelegate gridDelegate;

        if (_tableColumns == 0) {
          const maxCardWidth = 190.0;

          gridDelegate = const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: maxCardWidth,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.70,
          );
        } else {
          gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _tableColumns,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.70,
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          gridDelegate: gridDelegate,
          itemCount: _tables.length,
          itemBuilder: (context, index) {
            final table = _tables[index];

            if (!table.isActive) {
              return const SizedBox.shrink();
            }

            return _SelectTableCard(
              table: table,
              statusLabel: _statusLabel(table.status),
              statusColor: _statusColor(context, table.status),
              enabled: true,
              onTap: () => _selectTable(table),
            );
          },
        );
      },
    );
  }
}

class _SelectTableCard extends StatelessWidget {
  const _SelectTableCard({
    required this.table,
    required this.statusLabel,
    required this.statusColor,
    required this.enabled,
    required this.onTap,
  });

  final PosTable table;
  final String statusLabel;
  final Color statusColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final cardBackgroundColor = switch (table.status) {
      'occupied' => Colors.orange.shade50,
      'reserved' => Colors.blue.shade50,
      _ => Colors.green.shade50,
    };

    final actionLabel = switch (table.status) {
      'available' => 'Start Order',
      'occupied' when table.activeOrderId != null => 'Open Order',
      'occupied' => 'No Active Order',
      'reserved' => 'Reserved',
      _ => statusLabel,
    };

    return Card(
      color: cardBackgroundColor,
      clipBehavior: Clip.antiAlias,
      elevation: enabled ? 1 : 0,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.table_restaurant,
                  size: 32,
                  color: statusColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                table.name,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${table.capacity} ${table.capacity == 1 ? 'seat' : 'seats'}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              if (table.section != null &&
                  table.section!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  table.section!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                actionLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
