import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/application/pos_catalog_state.dart';
import 'package:top_coffee_pos/features/pos/domain/pos_models.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/product_search_field.dart';

void main() {
  test('catalog finds a product by case-insensitive SKU', () {
    const product = PosProduct(id: 1, name: 'Latte', sku: 'COF-123', description: null,
      category: null, price: 3.5, variants: []);
    const catalog = PosCatalogLoaded(categories: [], products: [product], searchQuery: 'cof-123');
    expect(catalog.visibleProducts.single.id, 1);
  });

  testWidgets('scanner Enter submits a SKU and keeps search ready for the next scan', (tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: ProductSearchField(onChanged: (_) {}, onSubmitted: submitted.add))));
    await tester.enterText(find.byType(TextField), 'COF-123');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(submitted, ['COF-123']);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '');
    expect(field.focusNode!.hasFocus, isTrue);
  });
}
