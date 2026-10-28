import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:top_coffee_pos/core/network/api_exceptions.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/products/data/products_repository.dart';
import 'package:top_coffee_pos/features/products/domain/managed_product_models.dart';
import 'package:top_coffee_pos/features/products/presentation/product_form_screen.dart';
import 'package:top_coffee_pos/features/products/presentation/product_photo_editor.dart';

class _Products extends Mock implements ProductsRepository {}

const _product =
    ManagedProduct(id: 1, name: 'Latte', categoryId: 1, basePrice: 3);
const _category = PosCategory(id: 1, name: 'Coffee', sortOrder: 0);

Future<void> _native(WidgetTester tester, bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(done(), isTrue);
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
  setUpAll(() => registerFallbackValue(_product));

  testWidgets(
      'photo choice, adjustment, cancel and upload keep the chosen crop',
      (tester) async {
    final file = (await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('photo-form-');
      addTearDown(() => directory.delete(recursive: true));
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
          const Rect.fromLTWH(0, 0, 20, 10), Paint()..color = Colors.green);
      final picture = recorder.endRecording();
      final image = await picture.toImage(20, 10);
      picture.dispose();
      try {
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        final file = File(p.join(directory.path, 'photo.png'));
        await file.writeAsBytes(bytes.buffer.asUint8List());
        return file;
      } finally {
        image.dispose();
      }
    }))!;
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => file.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final repository = _Products();
    XFile? uploaded;
    when(() => repository.updateProduct(1, any(),
        imageFile: any(named: 'imageFile'))).thenAnswer((invocation) async {
      uploaded = invocation.namedArguments[#imageFile] as XFile?;
      throw const ValidationException({}, 'Test save intercepted');
    });
    await tester.pumpWidget(ProviderScope(
        overrides: [
          productsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
            home: ProductFormScreen(
                args: ProductFormArgs(
                    categories: [_category], initialProduct: _product)))));
    await tester.pumpAndSettle();
    await _tap(tester, 'Choose Photo');
    await _native(
        tester,
        () => find
            .byKey(const ValueKey('product-photo-canvas'))
            .evaluate()
            .isNotEmpty);
    await _tap(tester, 'Fit whole photo');
    await tester.tap(find.text('Use Photo'));
    await _native(
        tester, () => find.byType(ProductPhotoEditor).evaluate().isEmpty);
    await _tap(tester, 'Adjust Photo');
    await _native(
        tester,
        () => find
            .byKey(const ValueKey('product-photo-canvas'))
            .evaluate()
            .isNotEmpty);
    await tester.scrollUntilVisible(find.byType(Slider), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, .5);
    await _tap(tester, 'Fill frame');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _tap(tester, 'Save Changes');
    await tester.pumpAndSettle();
    expect(uploaded, isNotNull);
    final bytes = (await tester.runAsync(() => uploaded!.readAsBytes()))!;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      try {
        final pixels =
            (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        expect(image.width, 1024);
        // The cancelled Fill operation must not replace the saved Fit border.
        final corner = (50 * image.width + 512) * 4;
        expect(pixels.getUint8(corner), 255);
        expect(pixels.getUint8(corner + 1), 255);
        expect(pixels.getUint8(corner + 2), 255);
      } finally {
        image.dispose();
      }
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cancelling photo selection leaves the existing product unchanged',
      (tester) async {
    const channel = MethodChannel('plugins.flutter.io/image_picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final repository = _Products();
    await tester.pumpWidget(ProviderScope(
        overrides: [
          productsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
            home: ProductFormScreen(
                args: ProductFormArgs(
                    categories: [_category], initialProduct: _product)))));
    await tester.pumpAndSettle();
    await _tap(tester, 'Choose Photo');
    await tester.pumpAndSettle();
    expect(find.byType(ProductPhotoEditor), findsNothing);
    expect(find.text('Adjust Photo'), findsNothing);
    verifyNever(() =>
        repository.updateProduct(1, any(), imageFile: any(named: 'imageFile')));
    expect(tester.takeException(), isNull);
  });
}
