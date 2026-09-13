import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

class TableManagementScreen extends ConsumerStatefulWidget {
  const TableManagementScreen({super.key});

  @override
  ConsumerState<TableManagementScreen> createState() =>
      _TableManagementScreenState();
}

class _TableManagementScreenState
    extends ConsumerState<TableManagementScreen> {
  List<PosTable> _tables = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTables();
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
        return aNumber.compareTo(bNumber);
      });

      setState(() {
        _tables = sortedTables;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to load tables.';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'occupied':
        return Colors.orange;
      case 'reserved':
        return Colors.blue;
      default:
        return Colors.green;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Table Management',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Manage restaurant tables and their current status.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: _isLoading ? null : _loadTables,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _showAddTableDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Table'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _nextTableName() {
    var highestNumber = 0;

    final pattern = RegExp(r'^T(\d+)$', caseSensitive: false);

    for (final table in _tables) {
      final match = pattern.firstMatch(table.name.trim());

      if (match != null) {
        final number = int.tryParse(match.group(1) ?? '');

        if (number != null && number > highestNumber) {
          highestNumber = number;
        }
      }
    }

    return 'T${highestNumber + 1}';
  }

  Future<void> _showAddTableDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _AddTableDialog(
          initialName: _nextTableName(),
          onCreate: (name, capacity, section, shape, color, isActive) async {
            await ref.read(posRepositoryProvider).createTable(
              name: name,
              capacity: capacity,
              section: section,
              shape: shape,
              color: color,
              isActive: isActive,
            );
          },
        );
      },
    );

    if (!mounted || result != true) {
      return;
    }

    await _loadTables();
  }
  Future<void> _showDeleteTableDialog(PosTable table) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Table'),
          content: Text(
            'Are you sure you want to delete ${table.name}? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref.read(posRepositoryProvider).deleteTable(
        tableId: table.id,
      );

      if (!mounted) return;

      await _loadTables();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to delete table: $e'),
        ),
      );
    }
  }
  Future<void> _showEditTableDialog(PosTable table) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _EditTableDialog(
          table: table,
          onSave: (
            name,
            capacity,
            status,
            section,
            shape,
            color,
            isActive,
          ) async {
            await ref.read(posRepositoryProvider).updateTable(
              tableId: table.id,
              name: name,
              capacity: capacity,
              status: status,
              section: section,
              shape: shape,
              color: color,
              isActive: isActive,
            );
          },
        );
      },
    );

    if (!mounted || result != true) {
      return;
    }

    await _loadTables();
  }

  Widget _buildContent() {
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
              color: Colors.redAccent,
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
        child: Text('No tables found.'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final crossAxisCount = width >= 1200
            ? 5
            : width >= 900
                ? 4
                : width >= 600
                    ? 3
                    : 2;

        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 1.10,
          ),
          itemCount: _tables.length,
          itemBuilder: (context, index) {
            final table = _tables[index];
            return _TableCard(
              table: table,
              statusColor: _statusColor(table.status),
              statusLabel: _statusLabel(table.status),
              onEdit: () {
                _showEditTableDialog(table);
              },
              onDelete: () {
                _showDeleteTableDialog(table);
              },
            );
          },
        );
      },
    );
  }
}

class _AddTableDialog extends StatefulWidget {
  const _AddTableDialog({
    required this.onCreate,
    required this.initialName,
  });

  final String initialName;

  final Future<void> Function(
    String name,
    int capacity,
    String? section,
    String shape,
    String? color,
    bool isActive,
  ) onCreate;

  @override
  State<_AddTableDialog> createState() => _AddTableDialogState();
}

class _AddTableDialogState extends State<_AddTableDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;

  String? _section;
  String _shape = 'square';
  String? _color;
  bool _isActive = true;

  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _capacityController = TextEditingController(text: '4');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    final capacity = int.tryParse(_capacityController.text.trim());

    if (name.isEmpty) {
      setState(() {
        _error = 'Please enter a table name.';
      });
      return;
    }

    if (capacity == null || capacity < 1) {
      setState(() {
        _error = 'Capacity must be at least 1.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await widget.onCreate(
        name,
        capacity,
        _section,
        _shape,
        _color,
        _isActive,
      );

      if (!mounted) return;

      final navigator = Navigator.of(context);
      await Future<void>.delayed(Duration.zero);

      if (!mounted) return;

      navigator.pop(true);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _error = 'Unable to create table.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Table'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Table name',
                  hintText: 'Example: T9',
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() {
                      _error = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _capacityController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Capacity',
                  hintText: 'Number of seats',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() {
                      _error = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _section,
                decoration: const InputDecoration(
                  labelText: 'Section',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('No section'),
                  ),
                  DropdownMenuItem(
                    value: 'Indoor',
                    child: Text('Indoor'),
                  ),
                  DropdownMenuItem(
                    value: 'Outdoor',
                    child: Text('Outdoor'),
                  ),
                  DropdownMenuItem(
                    value: 'VIP',
                    child: Text('VIP'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _section = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _shape,
                decoration: const InputDecoration(
                  labelText: 'Shape',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'square',
                    child: Text('Square'),
                  ),
                  DropdownMenuItem(
                    value: 'rectangle',
                    child: Text('Rectangle'),
                  ),
                  DropdownMenuItem(
                    value: 'round',
                    child: Text('Round'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          _shape = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _color,
                decoration: const InputDecoration(
                  labelText: 'Color',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Default'),
                  ),
                  DropdownMenuItem(
                    value: 'blue',
                    child: Text('Blue'),
                  ),
                  DropdownMenuItem(
                    value: 'green',
                    child: Text('Green'),
                  ),
                  DropdownMenuItem(
                    value: 'orange',
                    child: Text('Orange'),
                  ),
                  DropdownMenuItem(
                    value: 'purple',
                    child: Text('Purple'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _color = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Show this table for new orders'),
                value: _isActive,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _create,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
class _EditTableDialog extends StatefulWidget {
  const _EditTableDialog({
    required this.table,
    required this.onSave,
  });

  final PosTable table;
  final Future<void> Function(
    String name,
    int capacity,
    String status,
    String? section,
    String shape,
    String? color,
    bool isActive,
  ) onSave;

  @override
  State<_EditTableDialog> createState() => _EditTableDialogState();
}

class _EditTableDialogState extends State<_EditTableDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _capacityController;

  late String _status;
  late String? _section;
  late String _shape;
  late String? _color;
  late bool _isActive;

  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: widget.table.name);
    _capacityController =
        TextEditingController(text: widget.table.capacity.toString());
    _status = widget.table.status;
    _section = widget.table.section;
    _shape = widget.table.shape;
    _color = widget.table.color;
    _isActive = widget.table.isActive;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final capacity = int.tryParse(_capacityController.text.trim());

    if (name.isEmpty) {
      setState(() {
        _error = 'Please enter a table name.';
      });
      return;
    }

    if (capacity == null || capacity < 1) {
      setState(() {
        _error = 'Capacity must be at least 1.';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      await widget.onSave(
        name,
        capacity,
        _status,
        _section,
        _shape,
        _color,
        _isActive,
      );

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _error = 'Unable to update table: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Table'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Table name',
                  hintText: 'Example: T9',
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() {
                      _error = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _capacityController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Capacity',
                  hintText: 'Number of seats',
                ),
                keyboardType: TextInputType.number,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() {
                      _error = null;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _section,
                decoration: const InputDecoration(
                  labelText: 'Section',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('No section'),
                  ),
                  DropdownMenuItem(
                    value: 'Indoor',
                    child: Text('Indoor'),
                  ),
                  DropdownMenuItem(
                    value: 'Outdoor',
                    child: Text('Outdoor'),
                  ),
                  DropdownMenuItem(
                    value: 'VIP',
                    child: Text('VIP'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _section = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _shape,
                decoration: const InputDecoration(
                  labelText: 'Shape',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'square',
                    child: Text('Square'),
                  ),
                  DropdownMenuItem(
                    value: 'rectangle',
                    child: Text('Rectangle'),
                  ),
                  DropdownMenuItem(
                    value: 'round',
                    child: Text('Round'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          _shape = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _color,
                decoration: const InputDecoration(
                  labelText: 'Color',
                ),
                items: const [
                  DropdownMenuItem(
                    value: null,
                    child: Text('Default'),
                  ),
                  DropdownMenuItem(
                    value: 'blue',
                    child: Text('Blue'),
                  ),
                  DropdownMenuItem(
                    value: 'green',
                    child: Text('Green'),
                  ),
                  DropdownMenuItem(
                    value: 'orange',
                    child: Text('Orange'),
                  ),
                  DropdownMenuItem(
                    value: 'purple',
                    child: Text('Purple'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _color = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(
                  labelText: 'Status',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'available',
                    child: Text('Available'),
                  ),
                  DropdownMenuItem(
                    value: 'occupied',
                    child: Text('Occupied'),
                  ),
                  DropdownMenuItem(
                    value: 'reserved',
                    child: Text('Reserved'),
                  ),
                ],
                onChanged: _isSaving
                    ? null
                    : (value) {
                        if (value == null) return;

                        setState(() {
                          _status = value;
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active'),
                subtitle: const Text('Show this table for new orders'),
                value: _isActive,
                onChanged: _isSaving
                    ? null
                    : (value) {
                        setState(() {
                          _isActive = value;
                        });
                      },
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.statusColor,
    required this.statusLabel,
    required this.onEdit,
    required this.onDelete,
  });

  final PosTable table;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color _customColor(BuildContext context) {
    switch (table.color?.toLowerCase()) {
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'purple':
        return Colors.purple;
      default:
        return statusColor;
    }
  }

  BorderRadius _shapeBorderRadius() {
    switch (table.shape) {
      case 'round':
        return BorderRadius.circular(100);
      case 'rectangle':
        return BorderRadius.circular(12);
      default:
        return BorderRadius.circular(12);
    }
  }

  double _shapeWidth() {
    switch (table.shape) {
      case 'rectangle':
        return 64;
      case 'round':
        return 46;
      default:
        return 46;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _customColor(context);
    final hasSection = table.section != null && table.section!.isNotEmpty;

    final cardBackgroundColor = switch (table.status) {
      'occupied' => Colors.orange.withValues(alpha: 0.10),
      'reserved' => Colors.blue.withValues(alpha: 0.08),
      _ => Colors.white,
    };

    return Card(
      elevation: 0,
      color: cardBackgroundColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.grey.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: _shapeWidth(),
                  height: 46,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.10),
                    borderRadius: _shapeBorderRadius(),
                  ),
                  child: Icon(
                    table.shape == 'round'
                        ? Icons.circle_outlined
                        : table.shape == 'rectangle'
                            ? Icons.crop_16_9
                            : Icons.square_outlined,
                    color: accentColor,
                  ),
                ),
                const Spacer(),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'delete') {
                      onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(
              table.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${table.capacity} seats',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            if (hasSection) ...[
              const SizedBox(height: 8),
              Text(
                table.section!,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}






