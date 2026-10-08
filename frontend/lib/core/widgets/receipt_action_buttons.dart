import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../receipt/customer_bill.dart';
import '../receipt/receipt_action_service.dart';
import 'app_buttons.dart' as pos_ui;

bool canIssueReceiptForOrderStatus(String status) => status == 'completed';

class ReceiptActionButtons extends ConsumerStatefulWidget {
  const ReceiptActionButtons({
    super.key,
    required this.orderId,
    this.showHeading = false,
  });

  final int orderId;
  final bool showHeading;

  @override
  ConsumerState<ReceiptActionButtons> createState() =>
      _ReceiptActionButtonsState();
}

class _ReceiptActionButtonsState extends ConsumerState<ReceiptActionButtons> {
  bool _isPrinting = false;
  bool _isSharing = false;

  Future<void> _printReceipt() async {
    if (_isPrinting || _isSharing) return;

    setState(() => _isPrinting = true);
    try {
      await ref.read(receiptActionServiceProvider).printReceipt(widget.orderId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt printed successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(error, 'Could not print receipt'))),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _shareElectronicReceipt() async {
    if (_isPrinting || _isSharing) return;

    final shareOrigin = _shareOrigin(context);

    setState(() => _isSharing = true);
    try {
      await ref
          .read(receiptActionServiceProvider)
          .shareElectronicReceipt(
            widget.orderId,
            sharePositionOrigin: shareOrigin,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFor(error, 'Could not create E-Receipt')),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isPrinting || _isSharing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text(
            'Receipt',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Print a paid receipt or share a PDF E-Receipt.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _DocumentButtonLayout(
          primary: pos_ui.OutlinedButton.icon(
            onPressed: busy ? null : _printReceipt,
            isLoading: _isPrinting,
            icon: const Icon(Icons.print_outlined),
            label: Text(_isPrinting ? 'Printing...' : 'Print Receipt'),
          ),
          secondary: pos_ui.SecondaryButton.icon(
            onPressed: busy ? null : _shareElectronicReceipt,
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long_outlined),
            label: Text(_isSharing ? 'Preparing...' : 'E-Receipt'),
          ),
        ),
      ],
    );
  }
}

class BillActionButtons extends ConsumerStatefulWidget {
  const BillActionButtons({
    super.key,
    required this.bill,
    this.showHeading = false,
  });

  final CustomerBill bill;
  final bool showHeading;

  @override
  ConsumerState<BillActionButtons> createState() => _BillActionButtonsState();
}

class _BillActionButtonsState extends ConsumerState<BillActionButtons> {
  bool _isPrinting = false;
  bool _isSharing = false;

  Future<void> _printBill() async {
    if (_isPrinting || _isSharing) return;

    setState(() => _isPrinting = true);
    try {
      await ref.read(receiptActionServiceProvider).printBill(widget.bill);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill printed successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(error, 'Could not print bill'))),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _shareElectronicBill() async {
    if (_isPrinting || _isSharing) return;

    final shareOrigin = _shareOrigin(context);

    setState(() => _isSharing = true);
    try {
      await ref
          .read(receiptActionServiceProvider)
          .shareElectronicBill(
            widget.bill,
            sharePositionOrigin: shareOrigin,
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageFor(error, 'Could not create E-Bill'))),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isPrinting || _isSharing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text(
            'Customer Bill',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.bill.isDraft
                ? 'Preview for the customer before payment. This is marked Draft / Unpaid.'
                : 'Give this unpaid bill to the customer before collecting payment.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        _DocumentButtonLayout(
          primary: pos_ui.OutlinedButton.icon(
            onPressed: busy ? null : _printBill,
            isLoading: _isPrinting,
            icon: const Icon(Icons.print_outlined),
            label: Text(_isPrinting ? 'Printing...' : 'Print Bill'),
          ),
          secondary: pos_ui.SecondaryButton.icon(
            onPressed: busy ? null : _shareElectronicBill,
            icon: _isSharing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: Text(_isSharing ? 'Preparing...' : 'E-Bill'),
          ),
        ),
      ],
    );
  }
}

class _DocumentButtonLayout extends StatelessWidget {
  const _DocumentButtonLayout({
    required this.primary,
    required this.secondary,
  });

  final Widget primary;
  final Widget secondary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: 10),
              secondary,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: primary),
            const SizedBox(width: 10),
            Expanded(child: secondary),
          ],
        );
      },
    );
  }
}

String _messageFor(Object error, String fallback) {
  if (error is StateError) {
    return error.message.toString();
  }
  return '$fallback: $error';
}

Rect? _shareOrigin(BuildContext context) {
  final renderBox = context.findRenderObject() as RenderBox?;
  return renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
}

Future<void> showPaymentReceiptDialog({
  required BuildContext context,
  required int orderId,
  required String orderReference,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.check_circle_outline, size: 46),
      title: const Text('Payment completed'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order $orderReference is completed.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ReceiptActionButtons(orderId: orderId),
          ],
        ),
      ),
      actions: [
        pos_ui.PosActionButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

Future<void> showLastReceiptDialog({
  required BuildContext context,
  required int orderId,
  required String orderReference,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.receipt_long_outlined, size: 42),
      title: const Text('Last Receipt'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Order $orderReference',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ReceiptActionButtons(orderId: orderId),
          ],
        ),
      ),
      actions: [
        pos_ui.SecondaryButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
