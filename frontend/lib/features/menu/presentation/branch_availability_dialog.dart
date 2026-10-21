import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../data/menu_repository.dart';

class BranchAvailabilityDialog extends ConsumerStatefulWidget {
  const BranchAvailabilityDialog({super.key, required this.product});
  final MenuRecord product;
  @override
  ConsumerState<BranchAvailabilityDialog> createState() => _AvailabilityState();
}

class _AvailabilityState extends ConsumerState<BranchAvailabilityDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController price;
  late final int branchId;
  bool available = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    branchId = ref.read(currentBranchProvider)!.id;
    final branch = (widget.product['branches'] as List)
        .cast<Map>()
        .firstWhere((b) => b['id'] == branchId);
    final pivot = branch['pivot'] as Map;
    available = pivot['is_available'] == true || pivot['is_available'] == 1;
    price = TextEditingController(text: '${pivot['price_override'] ?? ''}');
  }

  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !saving,
      child: AlertDialog(
        title: const Text('Branch pricing & availability'),
        content: Form(
            key: form,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  '${widget.product['name']} · ${ref.read(currentBranchProvider)?.name}'),
              const SizedBox(height: 16),
              TextFormField(
                controller: price,
                enabled: !saving,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                    labelText: 'Branch price override',
                    helperText:
                        'Leave empty to use base price \$${widget.product['base_price']}'),
                validator: (v) =>
                    v!.isEmpty || RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v)
                        ? null
                        : 'Enter a nonnegative price with up to 2 decimals',
              ),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available at this branch'),
                  value: available,
                  onChanged:
                      saving ? null : (v) => setState(() => available = v)),
              const Text(
                  'Shared base prices and other branches are unchanged.'),
              if (error != null)
                Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ]))),
        actions: [
          TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      setState(() => saving = true);
                      try {
                        await ref.read(menuRepositoryProvider).saveAvailability(
                            widget.product['id'] as int,
                            branchId,
                            available,
                            price.text.trim().isEmpty
                                ? null
                                : price.text.trim());
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (mounted)
                          setState(() {
                            error = menuError(e);
                            saving = false;
                          });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'))
        ],
      ));
}
