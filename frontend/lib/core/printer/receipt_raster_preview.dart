import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'receipt_raster.dart';

class ReceiptRasterPreview extends StatefulWidget {
  const ReceiptRasterPreview({super.key, required this.payload});
  final Map<String, dynamic> payload;

  @override
  State<ReceiptRasterPreview> createState() => _ReceiptRasterPreviewState();
}

class _ReceiptRasterPreviewState extends State<ReceiptRasterPreview> {
  late Future<Uint8List> _image;

  @override
  void initState() {
    super.initState();
    _image = receiptPreviewPng(widget.payload);
  }

  @override
  void didUpdateWidget(covariant ReceiptRasterPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _image = receiptPreviewPng(widget.payload);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                    'Receipt preview could not load. Reopen receipt settings to retry.'));
          }
          final data = snapshot.data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return Semantics(
              label: 'Receipt preview using the iPhone print layout',
              image: true,
              child: Image.memory(data,
                  width: double.infinity,
                  fit: BoxFit.fitWidth,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.high));
        },
      );
}
