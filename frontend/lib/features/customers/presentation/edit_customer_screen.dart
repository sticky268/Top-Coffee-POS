import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/subscription/subscription_action_guard.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../application/customer_detail_controller.dart';
import '../application/customer_detail_state.dart';

class EditCustomerScreen extends ConsumerStatefulWidget {
  const EditCustomerScreen({
    required this.customerId,
    required this.customer,
    super.key,
  });

  final int customerId;
  final CustomerDetailLoaded customer;

  @override
  ConsumerState<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends ConsumerState<EditCustomerScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _notesController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final customer = widget.customer.customer;

    _nameController = TextEditingController(text: customer.name);
    _phoneController = TextEditingController(text: customer.phone ?? '');
    _emailController = TextEditingController(text: customer.email ?? '');
    _notesController = TextEditingController(text: customer.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!SubscriptionActionGuard.canModify(ref)) return;

    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer name is required.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final customer = await ref
        .read(customerDetailControllerProvider(widget.customerId).notifier)
        .updateCustomer(
          name: name,
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (customer == null) {
      final state = ref.read(
        customerDetailControllerProvider(widget.customerId),
      );

      if (state is CustomerDetailError) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(state.message)));
      }

      return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Customer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _nameController,
            enabled: !_isSaving && SubscriptionActionGuard.canModify(ref),
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _phoneController,
            enabled: !_isSaving && SubscriptionActionGuard.canModify(ref),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Phone',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            enabled: !_isSaving && SubscriptionActionGuard.canModify(ref),
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            enabled: !_isSaving && SubscriptionActionGuard.canModify(ref),
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          pos_ui.PrimaryButton(
            onPressed: _isSaving || !SubscriptionActionGuard.canModify(ref)
                ? null
                : _save,
            isLoading: _isSaving,
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
