import 'package:flutter/material.dart';

import 'printer_service.dart';

class PrinterTestScreen extends StatefulWidget {
  const PrinterTestScreen({super.key});

  @override
  State<PrinterTestScreen> createState() => _PrinterTestScreenState();
}

class _PrinterTestScreenState extends State<PrinterTestScreen> {
  final PrinterService _printerService = PrinterService();
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.1.111',
  );

  String _status = 'Not connected';
  bool _busy = false;

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await _runAction(() async {
      await _printerService.connect(_ipController.text.trim());

      if (!mounted) return;

      setState(() {
        _status = 'Connected';
      });
    });
  }

  Future<void> _printTest() async {
    await _runAction(() async {
      await _printerService.printTest();

      if (!mounted) return;

      setState(() {
        _status = 'Test print sent';
      });
    });
  }

  Future<void> _disconnect() async {
    await _runAction(() async {
      await _printerService.disconnect();

      if (!mounted) return;

      setState(() {
        _status = 'Disconnected';
      });
    });
  }

  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _status = 'Working...';
    });

    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _status = 'Error: $error';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Test'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Printer IP address',
                hintText: '192.168.1.111',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _status,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _connect,
              child: const Text('Connect'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _printTest,
              child: const Text('Print Test'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _busy ? null : _disconnect,
              child: const Text('Disconnect'),
            ),
          ],
        ),
      ),
    );
  }
}