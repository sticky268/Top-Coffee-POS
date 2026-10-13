import 'package:flutter/material.dart';

import '../../../core/network/api_exceptions.dart';

class OperationField {
  const OperationField(
    this.keyName,
    this.label, {
    this.initial = '',
    this.options,
    this.number = false,
    this.optional = false,
  });
  final String keyName;
  final String label;
  final String initial;
  final List<String>? options;
  final bool number;
  final bool optional;
}

Future<bool?> showOperationForm(
  BuildContext context, {
  required String title,
  required List<OperationField> fields,
  required Future<void> Function(Map<String, dynamic>) save,
  String? explanation,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _OperationForm(
    title: title,
    fields: fields,
    save: save,
    explanation: explanation,
  ),
);

class _OperationForm extends StatefulWidget {
  const _OperationForm({
    required this.title,
    required this.fields,
    required this.save,
    this.explanation,
  });
  final String title;
  final List<OperationField> fields;
  final Future<void> Function(Map<String, dynamic>) save;
  final String? explanation;
  @override
  State<_OperationForm> createState() => _OperationFormState();
}

class _OperationFormState extends State<_OperationForm> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selected = {};
  bool _busy = false;
  Map<String, dynamic>? _submitted;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.options != null) {
        _selected[f.keyName] = f.options!.first;
      } else {
        _controllers[f.keyName] = TextEditingController(text: f.initial);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final values = <String, dynamic>{};
      for (final f in widget.fields) {
        final text = f.options != null
            ? _selected[f.keyName]!
            : _controllers[f.keyName]!.text.trim();
        if (text.isEmpty && f.optional) continue;
        values[f.keyName] = f.number ? num.parse(text) : text;
      }
      _submitted ??= values;
      await widget.save(_submitted!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (e is ApiException && e is! NetworkException && e is! ServerException)
        _submitted = null;
      if (mounted) {
        setState(() => _error = e is ApiException ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.explanation != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(widget.explanation!),
                  ),
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: f.options != null
                        ? DropdownButtonFormField<String>(
                            initialValue: _selected[f.keyName],
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.options!
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(o),
                                  ),
                                )
                                .toList(),
                            onChanged: _busy || _submitted != null
                                ? null
                                : (v) =>
                                      setState(() => _selected[f.keyName] = v!),
                          )
                        : TextFormField(
                            controller: _controllers[f.keyName],
                            enabled: !_busy && _submitted == null,
                            decoration: InputDecoration(labelText: f.label),
                            keyboardType: f.number
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : TextInputType.text,
                            validator: (v) {
                              final text = (v ?? '').trim();
                              if (text.isEmpty) {
                                return f.optional ? null : 'Required';
                              }
                              if (f.number) {
                                final number = num.tryParse(text);
                                if (number == null ||
                                    !number.isFinite ||
                                    number < 0) {
                                  return 'Enter a non-negative number';
                                }
                              }
                              return null;
                            },
                          ),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Confirming…' : 'Confirm'),
        ),
      ],
    ),
  );
}
