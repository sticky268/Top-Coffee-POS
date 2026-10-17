import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../../core/branch/current_branch_provider.dart';
import '../application/auth_controller.dart';
import '../application/auth_state.dart';

/// Returns an ephemeral PIN, an empty string if policy does not require one,
/// or null on cancellation. Never save the returned value in a journal/cache.
Future<String?> requestManagerPin(
  BuildContext context,
  WidgetRef ref, {
  required String action,
}) async {
  final auth = ref.read(authControllerProvider);
  if (auth is! AuthAuthenticated) {
    throw const AuthException('Sign in again before approving this action.');
  }
  if (!auth.user.requireManagerPin) return '';
  if (!auth.user.canApproveCheckout) {
    throw const AuthException(
      'A manager must sign in and enter their own PIN.',
    );
  }
  final branch = ref.read(currentBranchProvider)?.id;
  final pin = await showDialog<String>(
    context: context,
    builder: (_) => ManagerPinPrompt(action: action, manager: auth.user.name),
  );
  if (!context.mounted) return null;
  final current = ref.read(authControllerProvider);
  if (current is! AuthAuthenticated ||
      current.user.id != auth.user.id ||
      ref.read(currentBranchProvider)?.id != branch) {
    throw const AuthException(
      'Account or branch changed. Review the action again.',
    );
  }
  return pin;
}

class ManagerPinPrompt extends StatefulWidget {
  const ManagerPinPrompt({
    super.key,
    required this.action,
    required this.manager,
  });
  final String action;
  final String manager;

  @override
  State<ManagerPinPrompt> createState() => _ManagerPinPromptState();
}

class _ManagerPinPromptState extends State<ManagerPinPrompt> {
  final _pin = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _pin.clear();
    _pin.dispose();
    super.dispose();
  }

  void _approve() {
    if (_form.currentState!.validate()) Navigator.of(context).pop(_pin.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.action),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${widget.manager}, enter your own manager PIN to approve.'),
                const SizedBox(height: 12),
                TextFormField(
                  key: const ValueKey('manager-pin-input'),
                  controller: _pin,
                  autofocus: true,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: null,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(labelText: 'Manager PIN'),
                  validator: (value) =>
                      RegExp(r'^[0-9]{6,12}$').hasMatch(value ?? '')
                          ? null
                          : 'Enter 6–12 digits.',
                  onFieldSubmitted: (_) => _approve(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set or reset your PIN in Settings using your account password. Approval requires a connection.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _approve, child: const Text('Approve')),
        ],
      );
}
