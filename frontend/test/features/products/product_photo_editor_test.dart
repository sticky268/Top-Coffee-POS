import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:top_coffee_pos/features/products/presentation/product_photo_editor.dart';

Future<ui.Image> _fixture({bool portrait = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100), Paint()..color = Colors.red);
  canvas.drawRect(
      portrait
          ? const Rect.fromLTWH(0, 100, 100, 100)
          : const Rect.fromLTWH(100, 0, 100, 100),
      Paint()..color = Colors.blue);
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(portrait ? 100 : 200, portrait ? 200 : 100);
  } finally {
    picture.dispose();
  }
}

Future<Uint8List> _source() async {
  final image = await _fixture();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<void> _checkPixels(
    Uint8List png, List<({int x, int y, Color color})> samples) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      expect(image.width, 1024);
      expect(image.height, 1024);
      expect(png.length, lessThan(5 * 1024 * 1024));
      final data =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (final sample in samples) {
        final i = (sample.y * image.width + sample.x) * 4;
        expect(data.getUint8(i), (sample.color.r * 255).round());
        expect(data.getUint8(i + 1), (sample.color.g * 255).round());
        expect(data.getUint8(i + 2), (sample.color.b * 255).round());
        expect(data.getUint8(i + 3), 255);
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<void> _open(
  WidgetTester tester,
  XFile file, {
  ProductPhotoEdit? initial,
  ValueChanged<ProductPhotoEdit?>? onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      final result =
                          await Navigator.of(context).push<ProductPhotoEdit>(
                        MaterialPageRoute(
                            builder: (_) => ProductPhotoEditor(
                                source: file, initialEdit: initial)),
                      );
                      onResult?.call(result);
                    },
                    child: const Text('Open editor')),
              ))));
  await tester.tap(find.text('Open editor'));
  await tester.pump();
  await _waitNative(tester, () {
    final button = find.widgetWithText(FilledButton, 'Use Photo');
    return (button.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(button).onPressed != null) ||
        find.textContaining('Could not open this photo.').evaluate().isNotEmpty;
  });
}

Future<void> _waitNative(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue, reason: 'Native image operation did not complete');
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(find.text(label), 200,
      scrollable: find.byType(Scrollable).last);
  await tester.pump();
  await tester.tap(find.text(label));
  await tester.pump();
}

void main() {
  testWidgets('portrait photos fit without losing their top or bottom',
      (tester) async {
    await tester.runAsync(() async {
      final image = await _fixture(portrait: true);
      try {
        final result =
            await renderProductPhoto(image, zoom: .5, offset: Offset.zero);
        await _checkPixels(result, [
          (x: 50, y: 512, color: Colors.white),
          (x: 512, y: 100, color: Colors.red),
          (x: 512, y: 900, color: Colors.blue),
        ]);
      } finally {
        image.dispose();
      }
    });
  });

  testWidgets('oversize input is rejected before image decoding',
      (tester) async {
    await _open(
        tester,
        XFile.fromData(Uint8List(0),
            path: 'large.png', length: 26 * 1024 * 1024));
    expect(find.textContaining('Could not open this photo.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fit preserves the full landscape photo in the saved PNG',
      (tester) async {
    await tester.runAsync(() async {
      final image = await _fixture();
      try {
        final result =
            await renderProductPhoto(image, zoom: .5, offset: Offset.zero);
        await _checkPixels(result, [
          (x: 512, y: 50, color: Colors.white),
          (x: 100, y: 512, color: Colors.red),
          (x: 900, y: 512, color: Colors.blue),
        ]);
      } finally {
        image.dispose();
      }
    });
  });

  testWidgets('drag and zoom change saved pixels, not only the preview',
      (tester) async {
    await tester.runAsync(() async {
      final image = await _fixture();
      try {
        for (final x in [-.5, .5]) {
          final result =
              await renderProductPhoto(image, zoom: 1, offset: Offset(x, 0));
          await _checkPixels(result,
              [(x: 512, y: 512, color: x > 0 ? Colors.red : Colors.blue)]);
        }
        final result =
            await renderProductPhoto(image, zoom: .25, offset: Offset.zero);
        await _checkPixels(result, [
          (x: 100, y: 512, color: Colors.white),
          (x: 400, y: 512, color: Colors.red),
          (x: 600, y: 512, color: Colors.blue),
        ]);
      } finally {
        image.dispose();
      }
    });
  });

  testWidgets('editor saves fit choice and restores it when adjusted again',
      (tester) async {
    final bytes = (await tester.runAsync(_source))!;
    final file = XFile.fromData(bytes, path: 'source.png');
    ProductPhotoEdit? result;
    await _open(tester, file, onResult: (value) => result = value);
    await tester.scrollUntilVisible(find.byType(Slider), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);
    await _tap(tester, 'Fit whole photo');
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, .5);
    await tester.tap(find.text('Use Photo'));
    await _waitNative(
        tester, () => find.byType(ProductPhotoEditor).evaluate().isEmpty);
    expect(result, isNotNull);
    expect(result!.zoom, .5);
    await tester.runAsync(() => _checkPixels(result!.bytes, [
          (x: 512, y: 50, color: Colors.white),
          (x: 100, y: 512, color: Colors.red),
        ]));
    await _open(tester, file, initial: result);
    await tester.scrollUntilVisible(find.byType(Slider), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, .5);
    await _tap(tester, 'Reset');
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
  });

  testWidgets('slider and drag are retained in the returned photo edit',
      (tester) async {
    final bytes = (await tester.runAsync(_source))!;
    ProductPhotoEdit? result;
    await _open(tester, XFile.fromData(bytes, path: 'source.png'),
        onResult: (value) => result = value);
    await tester.scrollUntilVisible(find.byType(Slider), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(2);
    await tester.pump();
    await tester
        .ensureVisible(find.byKey(const ValueKey('product-photo-canvas')));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('product-photo-canvas')),
        const Offset(40, 25));
    await tester.pump();
    await tester.tap(find.text('Use Photo'));
    await _waitNative(
        tester, () => find.byType(ProductPhotoEditor).evaluate().isEmpty);
    expect(result!.zoom, 2);
    expect(result!.offset.dx, greaterThan(0));
    expect(result!.offset.dy, greaterThan(0));
  });

  testWidgets('Cancel returns no replacement photo', (tester) async {
    final bytes = (await tester.runAsync(_source))!;
    var completed = false;
    ProductPhotoEdit? result;
    await _open(tester, XFile.fromData(bytes, path: 'source.png'),
        onResult: (value) {
      result = value;
      completed = true;
    });
    await _tap(tester, 'Fit whole photo');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('invalid photo shows a recoverable error and can be cancelled',
      (tester) async {
    await _open(
        tester, XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'bad.png'));
    expect(find.textContaining('Could not open this photo.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use Photo'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Open editor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(360, 640), const Size(740, 360)]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('photo controls fit $size at text scale $scale',
          (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final bytes = (await tester.runAsync(_source))!;
        await _open(tester, XFile.fromData(bytes, path: 'source.png'));
        expect(find.text('Use Photo').hitTestable(), findsOneWidget);
        expect(find.text('Cancel').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
