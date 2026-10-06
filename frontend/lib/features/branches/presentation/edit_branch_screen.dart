import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../data/branch_repository.dart';
import '../domain/branch_models.dart';

class EditBranchScreen extends ConsumerStatefulWidget {
  const EditBranchScreen({required this.branchId, super.key});

  final int branchId;

  @override
  ConsumerState<EditBranchScreen> createState() => _EditBranchScreenState();
}

class _EditBranchScreenState extends ConsumerState<EditBranchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _timezoneController = TextEditingController();

  Branch? _branch;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;
  bool _isActive = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBranch();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _loadBranch() async {
    try {
      final branch = await ref
          .read(branchRepositoryProvider)
          .getBranch(widget.branchId);

      if (!mounted) return;

      setState(() {
        _branch = branch;
        _nameController.text = branch.name;
        _codeController.text = branch.code;
        _addressController.text = branch.address ?? '';
        _phoneController.text = branch.phone ?? '';
        _timezoneController.text = branch.timezone;
        _isActive = branch.isActive;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _errorText(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(branchRepositoryProvider)
          .updateBranch(
            id: widget.branchId,
            name: _nameController.text.trim(),
            code: _codeController.text.trim(),
            address: _addressController.text.trim(),
            phone: _phoneController.text.trim(),
            timezone: _timezoneController.text.trim(),
            isActive: _isActive,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch updated successfully')),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _errorText(e);
        _isSaving = false;
      });
    }
  }

  Future<void> _delete() async {
    final branch = _branch;
    if (branch == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete branch?'),
          content: Text(
            'This will delete "${branch.name}". This action cannot be undone.',
          ),
          actions: [
            pos_ui.SecondaryButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            pos_ui.DangerButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(branchRepositoryProvider).deleteBranch(widget.branchId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Branch deleted successfully')),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = _errorText(e);
        _isDeleting = false;
      });
    }
  }

  String _errorText(Object error) {
    if (error is ApiException) {
      return error.message;
    }

    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Branch')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Branch'),
        actions: [
          pos_ui.IconButton(
            tooltip: 'Delete branch',
            onPressed: _isSaving || _isDeleting ? null : _delete,
            isLoading: _isDeleting,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Branch Information',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Branch Name',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Branch name is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'Branch Code',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Branch code is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        decoration: const InputDecoration(
                          labelText: 'Address',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.next,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        decoration: const InputDecoration(
                          labelText: 'Phone',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _timezoneController,
                        decoration: const InputDecoration(
                          labelText: 'Timezone',
                          border: OutlineInputBorder(),
                        ),
                        textInputAction: TextInputAction.done,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Timezone is required';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: SwitchListTile(
                  title: const Text('Active'),
                  subtitle: const Text(
                    'Allow this branch to be used in the system',
                  ),
                  value: _isActive,
                  onChanged: _isSaving || _isDeleting
                      ? null
                      : (value) {
                          setState(() {
                            _isActive = value;
                          });
                        },
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: pos_ui.PrimaryButton(
                  onPressed: _isSaving || _isDeleting ? null : _save,
                  isLoading: _isSaving,
                  child: const Text('Save Changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
