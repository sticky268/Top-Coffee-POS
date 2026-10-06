import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/printer/printer_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../../../features/pos/domain/pos_models.dart';
import '../data/receipt_settings.dart';

class ReceiptSettingsScreen extends StatefulWidget {
  const ReceiptSettingsScreen({super.key});

  @override
  State<ReceiptSettingsScreen> createState() => _ReceiptSettingsScreenState();
}

class _ReceiptSettingsScreenState extends State<ReceiptSettingsScreen> {
  @override
  void initState() {
    super.initState();
    _loadLogo();
    _loadSettings();
  }

  bool showLogo = true;
  String logoPosition = 'Center';
  String logoSize = 'Medium';
  Uint8List? logoBytes;

  String fontStyle = 'Default';
  String bodyFontSize = 'Medium';
  String businessFontSize = 'Large';
  String footerFontSize = 'Medium';
  bool boldBusinessName = true;
  bool boldTotal = true;
  bool boldFooter = true;

  bool showOrderNumber = true;
  bool showDateTime = true;
  bool showCashier = true;
  bool showTable = true;
  bool showOrderType = true;

  bool showItemName = true;
  bool showQuantity = true;
  bool showUnitPrice = true;
  bool showLineTotal = true;

  bool showPaymentMethod = true;
  bool showTendered = true;
  bool showChange = true;
  bool showSplitPayments = true;

  bool printerEnabled = true;

  final TextEditingController printerIpController = TextEditingController(
    text: '192.168.1.111',
  );

  final TextEditingController businessNameController = TextEditingController(
    text: 'TOP COFFEE',
  );

  final TextEditingController branchNameController = TextEditingController(
    text: 'Phnom Penh Branch',
  );

  final TextEditingController footerController = TextEditingController(
    text: 'Thank you for visiting Top Coffee!',
  );

  OrderReceipt _buildBitmapTestReceipt() {
    const items = <OpenOrderItem>[
      OpenOrderItem(
        id: 1,
        productName: 'Iced Latte',
        variantName: 'Large',
        quantity: 2,
        unitPrice: 3.50,
        lineTotal: 7.00,
      ),
      OpenOrderItem(
        id: 2,
        productName: 'Cappuccino',
        variantName: 'Medium',
        quantity: 1,
        unitPrice: 3.00,
        lineTotal: 3.00,
      ),
      OpenOrderItem(
        id: 3,
        productName: 'សូកូឡាក្តៅ',
        variantName: null,
        quantity: 1,
        unitPrice: 2.50,
        lineTotal: 2.50,
      ),
    ];

    const payment = PaymentConfirmation(
      id: 1,
      method: 'Cash',
      amount: 12.00,
      tendered: 15.00,
      changeDue: 2.50,
      status: 'completed',
    );

    return OrderReceipt(
      orderId: 9999,
      uuid: 'bitmap-test-receipt',
      orderType: 'Dine In',
      status: 'completed',
      subtotal: 12.50,
      discountTotal: 0.50,
      total: 12.00,
      branchName: 'Phnom Penh Branch',
      branchCode: 'PP01',
      cashierName: 'Test Cashier',
      tableName: 'T3',
      items: items,
      payment: payment,
      payments: const [payment],
      createdAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    businessNameController.dispose();
    branchNameController.dispose();
    footerController.dispose();
    printerIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Settings')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;

          if (isWide) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _buildSettingsPanel()),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _buildPreviewPanel()),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSettingsPanel(),
              const SizedBox(height: 24),
              _buildPreviewPanel(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsPanel() {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildSection(
          title: 'Business Information',
          icon: Icons.store_outlined,
          children: [
            TextField(
              controller: businessNameController,
              decoration: const InputDecoration(
                labelText: 'Business name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: branchNameController,
              decoration: const InputDecoration(
                labelText: 'Branch name',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Logo',
          icon: Icons.image_outlined,
          children: [
            _buildSwitch(
              'Show logo',
              showLogo,
              (value) => setState(() => showLogo = value),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: logoPosition,
              decoration: const InputDecoration(
                labelText: 'Logo position',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Left', child: Text('Left')),
                DropdownMenuItem(value: 'Center', child: Text('Center')),
                DropdownMenuItem(value: 'Right', child: Text('Right')),
              ],
              onChanged: showLogo
                  ? (value) {
                      if (value != null) {
                        setState(() => logoPosition = value);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: logoSize,
              decoration: const InputDecoration(
                labelText: 'Logo size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Small', child: Text('Small')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Large', child: Text('Large')),
              ],
              onChanged: showLogo
                  ? (value) {
                      if (value != null) {
                        setState(() => logoSize = value);
                      }
                    }
                  : null,
            ),
            const SizedBox(height: 16),
            pos_ui.OutlinedButton.icon(
              onPressed: showLogo ? _pickLogo : null,
              icon: const Icon(Icons.upload_outlined),
              label: Text(logoBytes == null ? 'Upload Logo' : 'Change Logo'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (logoBytes != null) ...[
              const SizedBox(height: 8),
              pos_ui.DangerButton.outlinedIcon(
                onPressed: _removeLogo,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove Logo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Font Settings',
          icon: Icons.text_fields_outlined,
          children: [
            DropdownButtonFormField<String>(
              initialValue: fontStyle,
              decoration: const InputDecoration(
                labelText: 'Font style',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Default', child: Text('Default')),
                DropdownMenuItem(
                  value: 'Sans Serif',
                  child: Text('Sans Serif'),
                ),
                DropdownMenuItem(value: 'Serif', child: Text('Serif')),
                DropdownMenuItem(value: 'Monospace', child: Text('Monospace')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => fontStyle = value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: businessFontSize,
              decoration: const InputDecoration(
                labelText: 'Business name size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Small', child: Text('Small')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Large', child: Text('Large')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => businessFontSize = value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: bodyFontSize,
              decoration: const InputDecoration(
                labelText: 'Body font size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Small', child: Text('Small')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Large', child: Text('Large')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => bodyFontSize = value);
                }
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: footerFontSize,
              decoration: const InputDecoration(
                labelText: 'Footer font size',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'Small', child: Text('Small')),
                DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                DropdownMenuItem(value: 'Large', child: Text('Large')),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => footerFontSize = value);
                }
              },
            ),
            const SizedBox(height: 8),
            _buildSwitch(
              'Bold business name',
              boldBusinessName,
              (value) => setState(() => boldBusinessName = value),
            ),
            _buildSwitch(
              'Bold total',
              boldTotal,
              (value) => setState(() => boldTotal = value),
            ),
            _buildSwitch(
              'Bold footer',
              boldFooter,
              (value) => setState(() => boldFooter = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Receipt Information',
          icon: Icons.receipt_long_outlined,
          children: [
            _buildSwitch(
              'Order number',
              showOrderNumber,
              (value) => setState(() => showOrderNumber = value),
            ),
            _buildSwitch(
              'Date & time',
              showDateTime,
              (value) => setState(() => showDateTime = value),
            ),
            _buildSwitch(
              'Cashier',
              showCashier,
              (value) => setState(() => showCashier = value),
            ),
            _buildSwitch(
              'Table',
              showTable,
              (value) => setState(() => showTable = value),
            ),
            _buildSwitch(
              'Order type',
              showOrderType,
              (value) => setState(() => showOrderType = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Item Display',
          icon: Icons.shopping_bag_outlined,
          children: [
            _buildSwitch(
              'Item name',
              showItemName,
              (value) => setState(() => showItemName = value),
            ),
            _buildSwitch(
              'Quantity',
              showQuantity,
              (value) => setState(() => showQuantity = value),
            ),
            _buildSwitch(
              'Unit price',
              showUnitPrice,
              (value) => setState(() => showUnitPrice = value),
            ),
            _buildSwitch(
              'Line total',
              showLineTotal,
              (value) => setState(() => showLineTotal = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Payment',
          icon: Icons.payments_outlined,
          children: [
            _buildSwitch(
              'Payment method',
              showPaymentMethod,
              (value) => setState(() => showPaymentMethod = value),
            ),
            _buildSwitch(
              'Tendered',
              showTendered,
              (value) => setState(() => showTendered = value),
            ),
            _buildSwitch(
              'Change',
              showChange,
              (value) => setState(() => showChange = value),
            ),
            _buildSwitch(
              'Split-payment breakdown',
              showSplitPayments,
              (value) => setState(() => showSplitPayments = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Footer',
          icon: Icons.short_text_outlined,
          children: [
            TextField(
              controller: footerController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Footer message',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSection(
          title: 'Printer Settings',
          icon: Icons.print_outlined,
          children: [
            _buildSwitch(
              'Enable receipt printing',
              printerEnabled,
              (value) => setState(() => printerEnabled = value),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: printerIpController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Printer IP Address',
                hintText: '192.168.1.111',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lan_outlined),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: pos_ui.OutlinedButton.icon(
                onPressed: () async {
                  final ipAddress = printerIpController.text.trim();

                  if (ipAddress.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the printer IP address first.'),
                      ),
                    );
                    return;
                  }

                  final printerService = PrinterService();

                  try {
                    await printerService.connect(ipAddress);
                    await printerService.printTest();

                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Test print sent successfully.'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Printer test failed: $e')),
                    );
                  } finally {
                    try {
                      await printerService.disconnect();
                    } catch (_) {
                      // Ignore disconnect errors after the test.
                    }
                  }
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('Test Print'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: pos_ui.OutlinedButton.icon(
                onPressed: () async {
                  final ipAddress = printerIpController.text.trim();

                  if (ipAddress.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the printer IP address first.'),
                      ),
                    );
                    return;
                  }

                  final printerService = PrinterService();

                  try {
                    await printerService.connect(ipAddress);
                    await printerService.printKhmerTest();

                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Khmer test print sent successfully.'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Khmer printer test failed: $e')),
                    );
                  } finally {
                    try {
                      await printerService.disconnect();
                    } catch (_) {
                      // Ignore disconnect errors after the test.
                    }
                  }
                },
                icon: const Icon(Icons.language_outlined),
                label: const Text('Print Khmer Test'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: pos_ui.OutlinedButton.icon(
                onPressed: () async {
                  final ipAddress = printerIpController.text.trim();

                  if (ipAddress.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the printer IP address first.'),
                      ),
                    );
                    return;
                  }

                  final printerService = PrinterService();

                  try {
                    await printerService.connect(ipAddress);

                    final receipt = _buildBitmapTestReceipt();

                    await printerService.printReceiptBitmapTest(receipt);

                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bitmap receipt test sent successfully.'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Bitmap receipt test failed: $e')),
                    );
                  } finally {
                    try {
                      await printerService.disconnect();
                    } catch (_) {
                      // Ignore disconnect errors after the test.
                    }
                  }
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Print Bitmap Receipt Test'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: pos_ui.OutlinedButton.icon(
                onPressed: () async {
                  final ipAddress = printerIpController.text.trim();

                  if (ipAddress.isEmpty) {
                    return;
                  }

                  final printerService = PrinterService();

                  try {
                    await printerService.connect(ipAddress);

                    await printerService.printBitmapStressTest();

                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Bitmap stress test sent successfully.'),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) {
                      return;
                    }

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Bitmap stress test failed: $e')),
                    );
                  } finally {
                    try {
                      await printerService.disconnect();
                    } catch (_) {
                      // Ignore disconnect errors after the test.
                    }
                  }
                },
                icon: const Icon(Icons.height_outlined),
                label: const Text('Print Bitmap Stress Test'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: pos_ui.PrimaryButton.icon(
            onPressed: () async {
              await _saveSettings();

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt settings saved.')),
              );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save Settings'),
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility_outlined),
                const SizedBox(width: 8),
                Text(
                  'Live Preview',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildReceiptPreview(),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();

    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) {
      return;
    }

    final bytes = await image.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      logoBytes = bytes;
    });

    await _saveLogo(bytes);
  }

  Future<void> _loadSettings() async {
    final settings = await ReceiptSettings.load();

    if (!mounted) {
      return;
    }

    setState(() {
      businessNameController.text = settings.businessName;
      branchNameController.text = settings.branchName;
      logoPosition = settings.logoPosition;
      logoSize = settings.logoSize;
      fontStyle = settings.fontStyle;
      bodyFontSize = settings.bodyFontSize;
      businessFontSize = settings.businessFontSize;
      footerFontSize = settings.footerFontSize;
      boldBusinessName = settings.boldBusinessName;
      boldTotal = settings.boldTotal;
      boldFooter = settings.boldFooter;
      showOrderNumber = settings.showOrderNumber;
      showDateTime = settings.showDateTime;
      showCashier = settings.showCashier;
      showTable = settings.showTable;
      showOrderType = settings.showOrderType;
      showItemName = settings.showItemName;
      showQuantity = settings.showQuantity;
      showUnitPrice = settings.showUnitPrice;
      showLineTotal = settings.showLineTotal;
      showPaymentMethod = settings.showPaymentMethod;
      showTendered = settings.showTendered;
      showChange = settings.showChange;
      showSplitPayments = settings.showSplitPayments;
      printerEnabled = settings.printerEnabled;
      printerIpController.text = settings.printerIpAddress;
      footerController.text = settings.footer;
    });
  }

  Future<void> _saveSettings() async {
    final settings = ReceiptSettings(
      businessName: businessNameController.text,
      branchName: branchNameController.text,
      logoPosition: logoPosition,
      logoSize: logoSize,
      fontStyle: fontStyle,
      bodyFontSize: bodyFontSize,
      businessFontSize: businessFontSize,
      footerFontSize: footerFontSize,
      boldBusinessName: boldBusinessName,
      boldTotal: boldTotal,
      boldFooter: boldFooter,
      showOrderNumber: showOrderNumber,
      showDateTime: showDateTime,
      showCashier: showCashier,
      showTable: showTable,
      showOrderType: showOrderType,
      showItemName: showItemName,
      showQuantity: showQuantity,
      showUnitPrice: showUnitPrice,
      showLineTotal: showLineTotal,
      showPaymentMethod: showPaymentMethod,
      showTendered: showTendered,
      showChange: showChange,
      showSplitPayments: showSplitPayments,
      footer: footerController.text,
      printerEnabled: printerEnabled,
      printerIpAddress: printerIpController.text.trim(),
    );

    await settings.save();
  }

  Future<void> _saveLogo(Uint8List bytes) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/receipt_logo.png');

    await file.writeAsBytes(bytes);
  }

  Future<void> _loadLogo() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/receipt_logo.png');

    if (!await file.exists()) {
      return;
    }

    final bytes = await file.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      logoBytes = bytes;
    });
  }

  Future<void> _removeLogo() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/receipt_logo.png');

    if (await file.exists()) {
      await file.delete();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      logoBytes = null;
    });
  }

  TextStyle _receiptFontStyle({double? fontSize, FontWeight? fontWeight}) {
    String? family;

    switch (fontStyle) {
      case 'Sans Serif':
        family = 'sans-serif';
        break;
      case 'Serif':
        family = 'serif';
        break;
      case 'Monospace':
        family = 'monospace';
        break;
      default:
        family = null;
    }

    return TextStyle(
      fontFamily: family,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: AppColors.receiptInk,
    );
  }

  double _bodyFontSize() {
    switch (bodyFontSize) {
      case 'Small':
        return 12;
      case 'Large':
        return 16;
      default:
        return 14;
    }
  }

  double _businessFontSize() {
    switch (businessFontSize) {
      case 'Small':
        return 16;
      case 'Large':
        return 22;
      default:
        return 18;
    }
  }

  double _footerFontSize() {
    switch (footerFontSize) {
      case 'Small':
        return 11;
      case 'Large':
        return 15;
      default:
        return 13;
    }
  }

  Widget _buildPreviewItem({
    required String name,
    required String quantity,
    required String price,
    required String amount,
    bool header = false,
  }) {
    final textStyle = header
        ? const TextStyle(fontWeight: FontWeight.w600)
        : null;

    return Row(
      children: [
        Expanded(
          child: Text(
            header ? name : (showItemName ? name : ''),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            header ? quantity : (showQuantity ? quantity : ''),
            textAlign: TextAlign.center,
            style: textStyle,
          ),
        ),
        SizedBox(
          width: 68,
          child: Text(
            header ? price : (showUnitPrice ? price : ''),
            textAlign: TextAlign.right,
            style: textStyle,
          ),
        ),
        SizedBox(
          width: 76,
          child: Text(
            header ? amount : (showLineTotal ? amount : ''),
            textAlign: TextAlign.right,
            style: textStyle ?? const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: AppColors.receiptPaper,
      child: DefaultTextStyle(
        style: _receiptFontStyle(fontSize: _bodyFontSize()),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showLogo)
              Align(
                alignment: logoPosition == 'Left'
                    ? Alignment.centerLeft
                    : logoPosition == 'Right'
                    ? Alignment.centerRight
                    : Alignment.center,
                child: logoBytes != null
                    ? Image.memory(
                        logoBytes!,
                        width: logoSize == 'Small'
                            ? 48
                            : logoSize == 'Large'
                            ? 120
                            : 80,
                        height: logoSize == 'Small'
                            ? 32
                            : logoSize == 'Large'
                            ? 80
                            : 56,
                        fit: BoxFit.contain,
                      )
                    : Icon(
                        Icons.local_cafe,
                        size: logoSize == 'Small'
                            ? 32
                            : logoSize == 'Large'
                            ? 64
                            : 48,
                      ),
              ),
            if (showLogo) const SizedBox(height: 8),
            Text(
              businessNameController.text.isEmpty
                  ? 'TOP COFFEE'
                  : businessNameController.text,
              textAlign: TextAlign.center,
              style: _receiptFontStyle(
                fontSize: _businessFontSize(),
                fontWeight: boldBusinessName
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            Text(branchNameController.text, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Divider(),
            if (showOrderNumber) const Text('Order #: 1025'),
            if (showDateTime) const Text('Date: 19/09/2026 10:35 AM'),
            if (showCashier) const Text('Cashier: Admin'),
            if (showTable) const Text('Table: T3'),
            if (showOrderType) const Text('Type: Dine-in'),
            const Divider(),
            _buildPreviewItem(
              name: 'ITEM',
              quantity: 'QTY',
              price: 'PRICE',
              amount: 'AMOUNT',
              header: true,
            ),
            const Divider(height: 16),
            _buildPreviewItem(
              name: 'Americano',
              quantity: '2',
              price: '\$2.00',
              amount: '\$4.00',
            ),
            const SizedBox(height: 8),
            _buildPreviewItem(
              name: 'Iced Latte',
              quantity: '1',
              price: '\$3.50',
              amount: '\$3.50',
            ),
            const Divider(),
            const Text('Subtotal:                 \$7.50'),
            const Text('Discount:                 \$0.50'),
            Text(
              'TOTAL:                    \$7.00',
              style: _receiptFontStyle(
                fontWeight: boldTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const Divider(),
            if (showPaymentMethod) const Text('Payment: CASH'),
            if (showTendered) const Text('Tendered:                \$10.00'),
            if (showChange) const Text('Change:                   \$3.00'),
            if (showSplitPayments) const SizedBox(height: 4),
            if (showSplitPayments)
              const Text('Split payments: hidden when not applicable'),
            const SizedBox(height: 16),
            Text(
              footerController.text,
              textAlign: TextAlign.center,
              style: _receiptFontStyle(
                fontSize: _footerFontSize(),
                fontWeight: boldFooter ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSwitch(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }
}
