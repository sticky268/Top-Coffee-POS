import 'package:flutter/material.dart';

/// A printer result can never change the already completed payment state.
class CashDrawerStatus extends StatelessWidget {
  const CashDrawerStatus({super.key, this.result});
  final Future<String?>? result;

  @override
  Widget build(BuildContext context) {
    if (result == null) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: result,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Payment completed. Sending cash drawer command…'));
        }
        final warning = snapshot.hasError
            ? 'Payment completed. Check the cash drawer before opening it manually.'
            : snapshot.data;
        if (warning == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(warning, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );
      },
    );
  }
}
