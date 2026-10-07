import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

class TableManagementScreen extends ConsumerStatefulWidget {
  const TableManagementScreen({super.key});

  @override
  ConsumerState<TableManagementScreen> createState() =>
      _TableManagementScreenState();
}

class _TableManagementScreenState extends ConsumerState<TableManagementScreen> {
  List<PosTable> _tables = [];
  bool _isLoading = true;
  String? _error;
  int? _branchId;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _branchId = ref.read(currentBranchProvider)?.id;
    _loadTables();
  }

  Future<void> _loadTables() async {
    final loadVersion = ++_loadVersion;
    final branchId = _branchId;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final tables = await ref.read(posRepositoryProvider).getTables(branchId: branchId);

      if (!mounted || loadVersion != _loadVersion || branchId != _branchId) return;

      final sortedTables = [...tables]
        ..sort((a, b) {
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
      if (!mounted || loadVersion != _loadVersion || branchId != _branchId) return;

      setState(() {
        _error = 'Unable to load tables.';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'occupied':
        return AppColors.semantic(context, AppColors.warning);
      case 'reserved':
        return AppColors.semantic(context, AppColors.info);
      default:
        return AppColors.semantic(context, AppColors.success);
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
    ref.listen(currentBranchProvider, (previous, next) {
      if (previous?.id == next?.id) return;
      _branchId = next?.id;
      ++_loadVersion;
      if (mounted) {
        setState(() {
          _tables = [];
          _isLoading = true;
          _error = null;
        });
      }
      _loadTables();
    });

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Table Management',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Manage restaurant tables and their current status.',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.semantic(context, AppColors.muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pos_ui.IconButton(
                    tooltip: 'Refresh',
                    onPressed: _isLoading ? null : _loadTables,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  pos_ui.PrimaryButton.icon(
                    onPressed: _showAddTableDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Table'),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildContent()),
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
            await ref
                .read(posRepositoryProvider)
                .createTable(
                  name: name,
                  capacity: capacity,
                  section: section,
                  shape: shape,
                  color: color,
                  isActive: isActive,
                  branchId: _branchId,
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
            pos_ui.SecondaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            pos_ui.DangerButton(
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
      await ref.read(posRepositoryProvider).deleteTable(tableId: table.id, branchId: _branchId);

      if (!mounted) return;

      await _loadTables();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Unable to delete table: $e')));
    }
  }

  Future<void> _showEditTableDialog(PosTable table) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return _EditTableDialog(
          table: table,
          onSave:
              (name, capacity, status, section, shape, color, isActive) async {
                await ref
                    .read(posRepositoryProvider)
                    .updateTable(
                      tableId: table.id,
                      name: name,
                      capacity: capacity,
                      status: status,
                      section: section,
                      shape: shape,
                      color: color,
                      isActive: isActive,
                      branchId: _branchId,
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
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.semantic(context, AppColors.error),
            ),
            const SizedBox(height: 16),
            Text(_error!),
            const SizedBox(height: 16),
            pos_ui.OutlinedButton.icon(
              onPressed: _loadTables,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_tables.isEmpty) {
      return const Center(child: Text('No tables found.'));
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
  const _AddTableDialog({required this.onCreate, required this.initialName});

  final String initialName;

  final Future<void> Function(
    String name,
    int capacity,
    String? section,
    String shape,
    String? color,
    bool isActive,
  )
  onCreate;

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
                decoration: const InputDecoration(labelText: 'Section'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('No section')),
                  DropdownMenuItem(value: 'Indoor', child: Text('Indoor')),
                  DropdownMenuItem(value: 'Outdoor', child: Text('Outdoor')),
                  DropdownMenuItem(value: 'VIP', child: Text('VIP')),
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
                decoration: const InputDecoration(labelText: 'Shape'),
                items: const [
                  DropdownMenuItem(value: 'square', child: Text('Square')),
                  DropdownMenuItem(
                    value: 'rectangle',
                    child: Text('Rectangle'),
                  ),
                  DropdownMenuItem(value: 'round', child: Text('Round')),
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
                decoration: const InputDecoration(labelText: 'Color'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Default')),
                  DropdownMenuItem(value: 'blue', child: Text('Blue')),
                  DropdownMenuItem(value: 'green', child: Text('Green')),
                  DropdownMenuItem(value: 'orange', child: Text('Orange')),
                  DropdownMenuItem(value: 'purple', child: Text('Purple')),
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
                const SizedBox(height: 16),
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
        pos_ui.SecondaryButton(
          onPressed: _isSaving
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),
        pos_ui.PrimaryButton(
          onPressed: _isSaving ? null : _create,
          isLoading: _isSaving,
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _EditTableDialog extends StatefulWidget {
  const _EditTableDialog({required this.table, required this.onSave});

  final PosTable table;
  final Future<void> Function(
    String name,
    int capacity,
    String status,
    String? section,
    String shape,
    String? color,
    bool isActive,
  )
  onSave;

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
    _capacityController = TextEditingController(
      text: widget.table.capacity.toString(),
    );
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
                decoration: const InputDecoration(labelText: 'Section'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('No section')),
                  DropdownMenuItem(value: 'Indoor', child: Text('Indoor')),
                  DropdownMenuItem(value: 'Outdoor', child: Text('Outdoor')),
                  DropdownMenuItem(value: 'VIP', child: Text('VIP')),
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
                decoration: const InputDecoration(labelText: 'Shape'),
                items: const [
                  DropdownMenuItem(value: 'square', child: Text('Square')),
                  DropdownMenuItem(
                    value: 'rectangle',
                    child: Text('Rectangle'),
                  ),
                  DropdownMenuItem(value: 'round', child: Text('Round')),
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
                decoration: const InputDecoration(labelText: 'Color'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Default')),
                  DropdownMenuItem(value: 'blue', child: Text('Blue')),
                  DropdownMenuItem(value: 'green', child: Text('Green')),
                  DropdownMenuItem(value: 'orange', child: Text('Orange')),
                  DropdownMenuItem(value: 'purple', child: Text('Purple')),
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
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(
                    value: 'available',
                    child: Text('Available'),
                  ),
                  DropdownMenuItem(value: 'occupied', child: Text('Occupied')),
                  DropdownMenuItem(value: 'reserved', child: Text('Reserved')),
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
                const SizedBox(height: 16),
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
        pos_ui.SecondaryButton(
          onPressed: _isSaving
              ? null
              : () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),
        pos_ui.PrimaryButton(
          onPressed: _isSaving ? null : _save,
          isLoading: _isSaving,
          child: const Text('Save'),
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
        return AppColors.semantic(context, AppColors.info);
      case 'green':
        return AppColors.semantic(context, AppColors.success);
      case 'orange':
        return AppColors.semantic(context, AppColors.warning);
      case 'purple':
        return AppColors.semantic(context, AppColors.plum);
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
      'occupied' => AppColors.tint(context, AppColors.warning),
      'reserved' => AppColors.tint(context, AppColors.info),
      _ => Theme.of(context).colorScheme.surface,
    };

    return Card(
      elevation: 1,
      color: cardBackgroundColor,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Text(
              table.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              '${table.capacity} seats',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
