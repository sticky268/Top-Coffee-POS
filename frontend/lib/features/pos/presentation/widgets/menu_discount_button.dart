import 'package:flutter/material.dart';
import '../../../../core/theme/coffee_studio_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/branch/current_branch_provider.dart';
import '../../../auth/data/auth_repository.dart';
import '../../application/cart_controller.dart';

class MenuDiscountButton extends ConsumerWidget {
  const MenuDiscountButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(cartControllerProvider).menuDiscount;
    final button = TextButton.icon(
      icon: const Icon(Icons.local_offer_outlined),
      label: Text(
        offer == null ? 'Choose saved discount' : '${offer['name']} · change',
      ),
      onPressed: () async {
        final branch = ref.read(currentBranchProvider)?.id;
        if (branch == null) return;
        try {
          final response = await ref.read(apiClientProvider).request(
                (dio) => dio.get(
                  '/menu/discounts',
                  queryParameters: {'branch_id': branch},
                ),
              );
          if (!context.mounted) return;
          final offers = (response.data['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          final selected = await showModalBottomSheet<Map<String, dynamic>>(
            context: context,
            showDragHandle: true,
            builder: (sheet) => SafeArea(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: const Text('No saved discount'),
                    onTap: () => Navigator.pop(sheet, <String, dynamic>{}),
                  ),
                  if (offers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No active offers for this branch.'),
                    ),
                  for (final entry in offers)
                    ListTile(
                      title: Text('${entry['name']}'),
                      subtitle: Text(
                        '${entry['value']}${entry['type'] == 'percent' ? '%' : ' off'}${entry['requires_manager'] == true ? ' · manager required' : ''}',
                      ),
                      onTap: () => Navigator.pop(sheet, entry),
                    ),
                ],
              ),
            ),
          );
          if (selected == null || !context.mounted) return;
          ref
              .read(cartControllerProvider.notifier)
              .selectMenuDiscount(selected.isEmpty ? null : selected);
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not load saved discounts. $e')),
            );
          }
        }
      },
    );
    if (!CoffeeStudioTheme.active(context)) return button;
    return OutlinedButton.icon(
        onPressed: button.onPressed,
        icon: const Icon(Icons.local_offer_outlined),
        label: Text(
            offer == null ? 'Saved discount' : '${offer['name']} · change'));
  }
}
