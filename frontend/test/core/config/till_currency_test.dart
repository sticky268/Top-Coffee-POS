import 'package:flutter_test/flutter_test.dart';
import 'package:top_coffee_pos/core/config/till_currency.dart';

void main() {
  test('shop rate and shortcuts preserve USD cents with no change rounding', () {
    expect(TillCurrency.rielPerDollar, 4000);
    expect(TillCurrency.rielForUsd(3.5), 14000);
    expect(TillCurrency.rielForUsd(0.06), 240);
    expect(TillCurrency.rielQuickAmounts(3.5), [20000, 50000, 100000]);
    expect(TillCurrency.usdForRielNote(20000), 5);
    expect(TillCurrency.usdForRielNote(50000), 12.5);
    expect(() => TillCurrency.usdForRielNote(500), throwsArgumentError);
    expect(TillCurrency.rielQuickAmounts(double.nan), isEmpty);
  });
}
