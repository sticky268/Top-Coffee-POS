import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exceptions.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/data/auth_repository.dart';

class ManagerPinSettingsCard extends ConsumerStatefulWidget {
  const ManagerPinSettingsCard({super.key, required this.userId});
  final int userId;

  @override
  ConsumerState<ManagerPinSettingsCard> createState() =>
      _ManagerPinSettingsCardState();
}

class _ManagerPinSettingsCardState
    extends ConsumerState<ManagerPinSettingsCard> {
  final _password = TextEditingController();
  final _pin = TextEditingController();
  final _confirmation = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    for (final controller in [_password, _pin, _confirmation]) {
      controller.clear();
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated ||
        auth.user.id != widget.userId ||
        !auth.user.canApproveCheckout)
      return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(apiClientProvider)
          .request(
            (dio) => dio.post(
              '/auth/manager-pin',
              data: {
                'expected_user_id': widget.userId,
                'current_password': _password.text,
                'pin': _pin.text,
                'pin_confirmation': _confirmation.text,
              },
            ),
          );
      if (mounted)
        setState(
          () => _message =
              'Manager PIN saved. Use it only with your own signed-in account.',
        );
    } catch (error) {
      if (mounted)
        setState(
          () => _message = error is ApiException
              ? error.message
              : 'Could not save PIN. Try again when connected.',
        );
    } finally {
      if (mounted) {
        for (final controller in [_password, _pin, _confirmation]) {
          controller.clear();
        }
        setState(() => _busy = false);
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      enabled: !_busy,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: null,
      keyboardType: numeric
          ? TextInputType.number
          : TextInputType.visiblePassword,
      inputFormatters: numeric
          ? [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ]
          : null,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        if ((value ?? '').isEmpty) return 'Required';
        if (numeric && !RegExp(r'^[0-9]{6,12}$').hasMatch(value!))
          return 'Use 6–12 digits.';
        if (controller == _confirmation && value != _pin.text)
          return 'PINs must match.';
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Manager PIN', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Set or reset your own PIN for voids and refunds. Confirm your account password. Do not share it. Five failed checks lock approval for 15 minutes; resetting the PIN cannot bypass that wait.',
            ),
            _field('Current account password', _password),
            _field('New manager PIN', _pin, numeric: true),
            _field('Confirm manager PIN', _confirmation, numeric: true),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save manager PIN'),
            ),
          ],
        ),
      ),
    ),
  );
}
