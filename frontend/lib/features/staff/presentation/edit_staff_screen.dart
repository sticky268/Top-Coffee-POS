import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/domain/auth_models.dart';
import '../../../core/subscription/subscription_action_guard.dart';
import '../data/staff_repository.dart';
import '../domain/staff_models.dart';

class EditStaffScreen extends ConsumerStatefulWidget {
  const EditStaffScreen({
    super.key,
    required this.staffId,
  });

  final int staffId;

  @override
  ConsumerState<EditStaffScreen> createState() => _EditStaffScreenState();
}

class _EditStaffScreenState extends ConsumerState<EditStaffScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  static const _roles = <String>[
    'admin',
    'manager',
    'cashier',
    'kitchen_staff',
  ];

  List<String> _availableRoles() {
    final authState = ref.read(authControllerProvider);

    if (authState is AuthAuthenticated && authState.user.hasRole('admin')) {
      return _roles;
    }

    return const [
      'cashier',
      'kitchen_staff',
    ];
  }

  StaffMember? _staff;
  String? _selectedRole;
  final Set<int> _selectedBranchIds = <int>{};
  int? _primaryBranchId;
  bool _isActive = true;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await ref
          .read(staffRepositoryProvider)
          .getStaffMember(widget.staffId);

      if (!mounted) return;

      _nameController.text = staff.name;
      _emailController.text = staff.email;
      _phoneController.text = staff.phone ?? '';
      _selectedRole = staff.primaryRole.isEmpty ? null : staff.primaryRole;
      _selectedBranchIds
        ..clear()
        ..addAll(staff.branches.map((branch) => branch.id));
      _primaryBranchId = staff.primaryBranch?.id;
      _isActive = staff.isActive;
      _staff = staff;

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = _messageFor(e);
      });
    }
  }

  List<BranchSummary> _availableBranches() {
    final authState = ref.read(authControllerProvider);

    if (authState is AuthAuthenticated) {
      return authState.user.branches;
    }

    return const [];
  }

  Future<void> _updateStaff() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedRole == null) {
      setState(() {
        _errorMessage = 'Please select a role.';
      });
      return;
    }

    if (_selectedBranchIds.isEmpty) {
      setState(() {
        _errorMessage = 'Please assign at least one branch.';
      });
      return;
    }

    if (_primaryBranchId == null ||
        !_selectedBranchIds.contains(_primaryBranchId)) {
      setState(() {
        _errorMessage = 'Please select a primary branch.';
      });
      return;
    }

    if (_staff != null && _selectedRole != _staff!.primaryRole) {
      final confirmed = await _confirmChange(
        title: 'Change role?',
        message: 'This will change ${_staff!.name} from '
            '${_roleLabel(_staff!.primaryRole)} to '
            '${_roleLabel(_selectedRole!)}.',
      );

      if (!confirmed || !mounted) {
        return;
      }
    }

    if (_staff != null && _isActive != _staff!.isActive && !_isActive) {
      final confirmed = await _confirmChange(
        title: 'Deactivate account?',
        message: 'This will prevent ${_staff!.name} from using the system.',
      );

      if (!confirmed || !mounted) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref.read(staffRepositoryProvider).updateStaff(
            id: widget.staffId,
            name: _nameController.text.trim(),
            email: _emailController.text.trim(),
            phone: _phoneController.text.trim(),
            password: _passwordController.text,
            role: _selectedRole!,
            branchIds: _selectedBranchIds.toList(),
            primaryBranchId: _primaryBranchId!,
            isActive: _isActive,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Staff member updated successfully.'),
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorMessage = _messageFor(e);
      });
    }
  }

  Future<bool> _confirmChange({
    required String title,
    required String message,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  String _messageFor(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }

    return message;
  }

  String? _requiredValidator(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }

    return null;
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required.';
    }

    final email = value.trim();
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!emailPattern.hasMatch(email)) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  String? _passwordValidator(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final canModify = SubscriptionActionGuard.canModify(ref);
    final theme = Theme.of(context);
    final branches = _availableBranches();
    final authState = ref.watch(authControllerProvider);
    final isEditingSelf =
        authState is AuthAuthenticated && authState.user.id == widget.staffId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Staff'),
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : _errorMessage != null && _staff == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      children: [
                        Text(
                          'Edit staff account',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Update this staff member’s account, role, and branch access.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        _SectionCard(
                          title: 'Personal information',
                          children: [
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                hintText: 'Enter full name',
                              ),
                              validator: (value) =>
                                  _requiredValidator(value, 'Full name'),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'staff@example.com',
                              ),
                              validator: _emailValidator,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Phone',
                                hintText: 'Optional',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Account',
                          children: [
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                labelText: 'New password',
                                hintText:
                                    'Leave blank to keep current password',
                              ),
                              validator: _passwordValidator,
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                              initialValue:
                                  _availableRoles().contains(_selectedRole)
                                      ? _selectedRole
                                      : null,
                              decoration: const InputDecoration(
                                labelText: 'Role',
                              ),
                              items: _availableRoles()
                                  .map(
                                    (role) => DropdownMenuItem<String>(
                                      value: role,
                                      child: Text(_roleLabel(role)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _isSaving
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _selectedRole = value;
                                      });
                                    },
                              validator: (value) =>
                                  value == null ? 'Role is required.' : null,
                            ),
                            const SizedBox(height: 8),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Active account'),
                              subtitle: Text(
                                isEditingSelf
                                    ? 'You cannot deactivate your own account.'
                                    : 'Allow this staff member to use the system.',
                              ),
                              value: _isActive,
                              onChanged: _isSaving || isEditingSelf
                                  ? null
                                  : (value) {
                                      setState(() {
                                        _isActive = value;
                                      });
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _SectionCard(
                          title: 'Branch access',
                          children: [
                            if (branches.isEmpty)
                              Text(
                                'No accessible branches are available.',
                                style: theme.textTheme.bodyMedium,
                              )
                            else
                              ...branches.map(
                                (branch) => CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(branch.name),
                                  subtitle: Text(branch.code),
                                  value: _selectedBranchIds.contains(branch.id),
                                  onChanged: _isSaving
                                      ? null
                                      : (selected) {
                                          setState(() {
                                            if (selected == true) {
                                              _selectedBranchIds.add(branch.id);
                                            } else {
                                              _selectedBranchIds
                                                  .remove(branch.id);

                                              if (_primaryBranchId ==
                                                  branch.id) {
                                                _primaryBranchId = null;
                                              }
                                            }
                                          });
                                        },
                                ),
                              ),
                            if (_selectedBranchIds.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              DropdownButtonFormField<int>(
                                initialValue: branches.any(
                                  (branch) =>
                                      branch.id == _primaryBranchId &&
                                      _selectedBranchIds.contains(branch.id),
                                )
                                    ? _primaryBranchId
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Primary branch',
                                ),
                                items: branches
                                    .where(
                                      (branch) => _selectedBranchIds
                                          .contains(branch.id),
                                    )
                                    .map(
                                      (branch) => DropdownMenuItem<int>(
                                        value: branch.id,
                                        child: Text(
                                          '${branch.name} (${branch.code})',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isSaving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _primaryBranchId = value;
                                        });
                                      },
                                validator: (value) => value == null
                                    ? 'Primary branch is required.'
                                    : null,
                              ),
                            ],
                          ],
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: theme.colorScheme.errorContainer,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 52,
                          child: FilledButton(
                            onPressed:
                                _isSaving || !canModify ? null : _updateStaff,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Save Changes'),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'kitchen_staff':
        return 'Kitchen Staff';
      case 'cashier':
        return 'Cashier';
      case 'manager':
        return 'Manager';
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
