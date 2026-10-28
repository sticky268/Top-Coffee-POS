import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ProductPhotoEdit {
  const ProductPhotoEdit(this.bytes,
      {required this.zoom, required this.offset});
  final Uint8List bytes;
  final double zoom;
  final Offset offset;
}

/// Uses the same normalized geometry for the preview and the uploaded image.
Rect productPhotoRect(Size source, Size frame, double zoom, Offset offset) {
  final scale =
      math.max(frame.width / source.width, frame.height / source.height) * zoom;
  final size = Size(source.width * scale, source.height * scale);
  return Rect.fromLTWH(
    (frame.width - size.width) / 2 + offset.dx * frame.width,
    (frame.height - size.height) / 2 + offset.dy * frame.height,
    size.width,
    size.height,
  );
}

void _paintPhoto(
    Canvas canvas, Size size, ui.Image image, double zoom, Offset offset) {
  canvas.drawColor(Colors.white, BlendMode.src);
  canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      productPhotoRect(Size(image.width.toDouble(), image.height.toDouble()),
          size, zoom, offset),
      Paint()..filterQuality = FilterQuality.high);
}

/// Bounded, flattened PNG: positioning is saved in the picture itself.
Future<Uint8List> renderProductPhoto(
  ui.Image image, {
  required double zoom,
  required Offset offset,
}) async {
  final recorder = ui.PictureRecorder();
  _paintPhoto(Canvas(recorder), const Size.square(1024), image, zoom, offset);
  final picture = recorder.endRecording();
  try {
    final output = await picture.toImage(1024, 1024);
    try {
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not prepare photo.');
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      output.dispose();
    }
  } finally {
    picture.dispose();
  }
}

class ProductPhotoEditor extends StatefulWidget {
  const ProductPhotoEditor({super.key, required this.source, this.initialEdit});
  final XFile source;
  final ProductPhotoEdit? initialEdit;

  @override
  State<ProductPhotoEditor> createState() => _ProductPhotoEditorState();
}

class _ProductPhotoEditorState extends State<ProductPhotoEditor> {
  ui.Image? _image;
  String? _error;
  bool _saving = false;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  double _gestureZoom = 1;
  Offset _gestureOffset = Offset.zero;
  Offset _gestureFocal = Offset.zero;

  double get _fit => _image == null
      ? 1
      : math.min(_image!.width, _image!.height) /
          math.max(_image!.width, _image!.height);

  double get _minZoom => math.min(.25, _fit);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (await widget.source.length() > 25 * 1024 * 1024) {
        throw const FormatException('Photo is too large.');
      }
      final bytes = await widget.source.readAsBytes();
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.Image? decoded;
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final scale = math.min(
              1.0, 2048 / math.max(descriptor.width, descriptor.height));
          final codec = await descriptor.instantiateCodec(
            targetWidth: math.max(1, (descriptor.width * scale).round()),
            targetHeight: math.max(1, (descriptor.height * scale).round()),
          );
          try {
            decoded = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
      if (!mounted) {
        decoded.dispose();
        return;
      }
      setState(() {
        _image = decoded;
        _zoom = (widget.initialEdit?.zoom ?? 1).clamp(_minZoom, 4);
        _offset = _bounded(widget.initialEdit?.offset ?? Offset.zero, _zoom);
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not open this photo. Choose a supported picture under 25 MB.');
      }
    }
  }

  Offset _bounded(Offset value, double zoom) {
    final image = _image!;
    final shortest = math.min(image.width, image.height);
    final x = (image.width / shortest * zoom - 1).abs() / 2;
    final y = (image.height / shortest * zoom - 1).abs() / 2;
    return Offset(value.dx.clamp(-x, x), value.dy.clamp(-y, y));
  }

  void _setZoom(double zoom, {bool center = false}) => setState(() {
        _zoom = zoom;
        _offset = center ? Offset.zero : _bounded(_offset, zoom);
      });

  Future<void> _save() async {
    if (_saving || _image == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final bytes =
          await renderProductPhoto(_image!, zoom: _zoom, offset: _offset);
      if (mounted) {
        Navigator.of(context)
            .pop(ProductPhotoEdit(bytes, zoom: _zoom, offset: _offset));
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not prepare this photo. Please try again.';
        });
      }
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(title: const Text('Adjust product photo')),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 12,
                runSpacing: 8,
                children: [
                  TextButton(
                      onPressed:
                          _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: _image == null || _saving ? null : _save,
                      child: Text(_saving ? 'Preparing photo…' : 'Use Photo')),
                ]),
          ),
          body: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text('Move and scale your picture until the product fits.'),
              const SizedBox(height: 8),
              const Text(
                  'Drag to reposition. Pinch to zoom, or use the slider.'),
              const SizedBox(height: 16),
              if (_image == null && _error == null)
                const Center(child: CircularProgressIndicator()),
              if (_image != null) ...[
                Center(
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: math.min(
                                420, MediaQuery.sizeOf(context).height * .45)),
                        child: AspectRatio(
                            aspectRatio: 1,
                            child: LayoutBuilder(builder: (_, bounds) {
                              final side = bounds.maxWidth;
                              return Semantics(
                                label: 'Product photo preview',
                                image: true,
                                child: ClipRect(
                                    child: GestureDetector(
                                  key: const ValueKey('product-photo-canvas'),
                                  onScaleStart: _saving
                                      ? null
                                      : (details) {
                                          _gestureZoom = _zoom;
                                          _gestureOffset = _offset;
                                          _gestureFocal =
                                              details.localFocalPoint / side -
                                                  const Offset(.5, .5);
                                        },
                                  onScaleUpdate: _saving
                                      ? null
                                      : (details) => setState(() {
                                            _zoom =
                                                (_gestureZoom * details.scale)
                                                    .clamp(_minZoom, 4);
                                            final focal =
                                                details.localFocalPoint / side -
                                                    const Offset(.5, .5);
                                            _offset = _bounded(
                                                focal -
                                                    (_gestureFocal -
                                                            _gestureOffset) *
                                                        (_zoom / _gestureZoom),
                                                _zoom);
                                          }),
                                  child: CustomPaint(
                                      painter: _PhotoPainter(
                                          _image!, _zoom, _offset),
                                      child: const SizedBox.expand()),
                                )),
                              );
                            })))),
                const SizedBox(height: 12),
                Text('Zoom ${(_zoom * 100).round()}%'),
                Semantics(
                    label: 'Photo zoom',
                    child: Slider(
                      min: _minZoom,
                      max: 4,
                      value: _zoom,
                      label: '${(_zoom * 100).round()}%',
                      onChanged: _saving ? null : (value) => _setZoom(value),
                    )),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton(
                      onPressed:
                          _saving ? null : () => _setZoom(_fit, center: true),
                      child: const Text('Fit whole photo')),
                  OutlinedButton(
                      onPressed:
                          _saving ? null : () => _setZoom(1, center: true),
                      child: const Text('Fill frame')),
                  TextButton(
                      onPressed:
                          _saving ? null : () => _setZoom(1, center: true),
                      child: const Text('Reset')),
                ]),
              ],
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
            ]),
          )),
        ),
      );
}

class _PhotoPainter extends CustomPainter {
  const _PhotoPainter(this.image, this.zoom, this.offset);
  final ui.Image image;
  final double zoom;
  final Offset offset;

  @override
  void paint(Canvas canvas, Size size) =>
      _paintPhoto(canvas, size, image, zoom, offset);
  @override
  bool shouldRepaint(_PhotoPainter oldDelegate) =>
      image != oldDelegate.image ||
      zoom != oldDelegate.zoom ||
      offset != oldDelegate.offset;
}
