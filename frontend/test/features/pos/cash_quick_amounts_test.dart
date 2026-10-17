import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/features/pos/presentation/widgets/cash_quick_amounts.dart';

void main() {
  test('suggestions include exact and never less than due', () {
    expect(cashQuickAmounts(3.5), [3.5, 5, 10, 20]);
    expect(cashQuickAmounts(20), [20, 50, 100]);
    expect(cashQuickAmounts(125.25), [125.25, 200]);
    expect(cashQuickAmounts(200), [200]);
    expect(cashQuickAmounts(double.nan), isEmpty);
    expect(cashQuickAmounts(-1), isEmpty);
  });
}
